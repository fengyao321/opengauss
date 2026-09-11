/* -------------------------------------------------------------------------
 *
 * ubtshrink.cpp
 *    UBTree Index Online Physical Shrink Implementation.
 *    (Phase 3: Online Concurrent Shrink & Micro-second Lock Escalation Truncate)
 *
 * Portions Copyright (c) 2020 Huawei Technologies Co.,Ltd.
 *
 * IDENTIFICATION
 *    src/gausskernel/storage/access/ubtree/ubtshrink.cpp
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"
#include "access/nbtree.h"
#include "access/ubtree.h"
#include "access/ubtreepcr.h"
#include "access/xloginsert.h"
#include "access/xlogproc.h"
#include "catalog/pg_am.h"
#include "catalog/pg_type.h"
#include "catalog/storage.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "storage/buf/bufmgr.h"
#include "storage/lmgr.h"
#include "storage/smgr/smgr.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/rel_gs.h"

/* Timeout (ms) for attempting brief AccessExclusiveLock during online truncation */
#define UBTREE_SHRINK_LOCK_TIMEOUT_MS 200
#define UBTREE_SHRINK_LOCK_RETRY_INTERVAL_US 5000 /* 5ms */

/* Maximum number of pages to migrate in a single shrink invocation */
#define UBTREE_SHRINK_MAX_MIGRATE_DEFAULT 512
/* Cost-benefit threshold: maximum victim/gain ratio (0.5 means <= 50% victim to freed gain) */
#define UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT 0.50

/*
 * Invalidate and remove any pending entries in Recycle Queue (both FREED and EMPTY forks)
 * whose block number is >= targetMaxBlock.
 */
static void UBTreePurgeRecycleQueueAboveWatermark(Relation rel, BlockNumber targetMaxBlock)
{
    if (!RecycleQueueInitialized(rel)) {
        return;
    }

    /* Iterate over both freed fork and empty fork */
    UBTRecycleForkNumber forks[] = {RECYCLE_FREED_FORK, RECYCLE_EMPTY_FORK};
    for (int i = 0; i < 2; i++) {
        UBTRecycleForkNumber fork = forks[i];
        const BlockNumber metaBlockNumber = (BlockNumber)fork;
        Buffer metaBuf = ReadRecycleQueueBuffer(rel, metaBlockNumber);
        LockBuffer(metaBuf, BT_READ);
        UBTRecycleMeta metaData = (UBTRecycleMeta)PageGetContents(BufferGetPage(metaBuf));
        BlockNumber startBlkno = metaData->headBlkno;
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);

        if (!BlockNumberIsValid(startBlkno)) {
            continue;
        }

        Buffer currBuf = ReadRecycleQueueBuffer(rel, startBlkno);
        LockBuffer(currBuf, BT_WRITE);
        currBuf = MoveToEndpointPage(rel, currBuf, true, BT_WRITE);

        BlockNumber firstVisited = BufferGetBlockNumber(currBuf);
        for (;;) {
            Page page = BufferGetPage(currBuf);
            BlockNumber currBlkno = BufferGetBlockNumber(currBuf);
            UBTRecycleQueueHeader header = GetRecycleQueueHeader(page, currBlkno);

            uint16 offset = header->head;
            while (IsNormalOffset(offset)) {
                UBTRecycleQueueItem item = HeaderGetItem(header, offset);
                uint16 nextOffset = item->next;

                if (BlockNumberIsValid(item->blkno) && item->blkno >= targetMaxBlock) {
                    /* Invalidate this entry since the block will be physically truncated */
                    RemoveOneItemFromPage(rel, currBuf, offset);
                }
                offset = nextOffset;
            }

            if ((header->flags & URQ_TAIL_PAGE) != 0) {
                UnlockReleaseBuffer(currBuf);
                break;
            }

            BlockNumber nextBlkno = header->nextBlkno;
            UnlockReleaseBuffer(currBuf);

            if (nextBlkno == firstVisited || !BlockNumberIsValid(nextBlkno)) {
                break;
            }

            currBuf = ReadRecycleQueueBuffer(rel, nextBlkno);
            LockBuffer(currBuf, BT_WRITE);
        }
    }
}

typedef struct UBTreeFreeBlockEntry {
    BlockNumber blkno;
    BlockNumber queueBlk;
    uint16 offset;
} UBTreeFreeBlockEntry;

typedef struct UBTreeURQInventory {
    UBTreeFreeBlockEntry *entries;
    int count;
    int capacity;
} UBTreeURQInventory;

static int CompareFreeBlockEntries(const void *a, const void *b)
{
    BlockNumber blkA = ((const UBTreeFreeBlockEntry *)a)->blkno;
    BlockNumber blkB = ((const UBTreeFreeBlockEntry *)b)->blkno;
    if (blkA < blkB) {
        return -1;
    }
    if (blkA > blkB) {
        return 1;
    }
    return 0;
}

/*
 * Collect valid, transaction-visible free blocks from the UBTree Recycle Queue (URQ).
 * The resulting list is deduplicated and sorted ascending by block number.
 */
static void UBTreeCollectURQFreeBlocks(Relation rel, UBTreeURQInventory *inv)
{
    inv->count = 0;
    inv->capacity = 1024;
    inv->entries = (UBTreeFreeBlockEntry *)palloc0(sizeof(UBTreeFreeBlockEntry) * inv->capacity);

    if (!RecycleQueueInitialized(rel)) {
        return;
    }

    TransactionId oldestXmin = u_sess->utils_cxt.RecentGlobalDataXmin;
    UBTRecycleForkNumber forks[] = {RECYCLE_FREED_FORK, RECYCLE_EMPTY_FORK};

    for (int i = 0; i < 2; i++) {
        UBTRecycleForkNumber fork = forks[i];
        const BlockNumber metaBlockNumber = (BlockNumber)fork;
        Buffer metaBuf = ReadRecycleQueueBuffer(rel, metaBlockNumber);
        LockBuffer(metaBuf, BT_READ);
        UBTRecycleMeta metaData = (UBTRecycleMeta)PageGetContents(BufferGetPage(metaBuf));
        BlockNumber startBlkno = metaData->headBlkno;
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);

        if (!BlockNumberIsValid(startBlkno)) {
            continue;
        }

        Buffer currBuf = ReadRecycleQueueBuffer(rel, startBlkno);
        LockBuffer(currBuf, BT_READ);
        currBuf = MoveToEndpointPage(rel, currBuf, true, BT_READ);

        BlockNumber firstVisited = BufferGetBlockNumber(currBuf);
        for (;;) {
            Page page = BufferGetPage(currBuf);
            BlockNumber currBlkno = BufferGetBlockNumber(currBuf);
            UBTRecycleQueueHeader header = GetRecycleQueueHeader(page, currBlkno);

            uint16 offset = header->head;
            while (IsNormalOffset(offset)) {
                UBTRecycleQueueItem item = HeaderGetItem(header, offset);
                uint16 nextOffset = item->next;

                if (BlockNumberIsValid(item->blkno)) {
                    bool visible = true;
                    if (TransactionIdIsValid(item->xid) && TransactionIdIsValid(oldestXmin)) {
                        if (TransactionIdFollowsOrEquals(item->xid, oldestXmin)) {
                            visible = false;
                        }
                    }
                    if (visible) {
                        if (inv->count >= inv->capacity) {
                            inv->capacity *= 2;
                            inv->entries = (UBTreeFreeBlockEntry *)repalloc(inv->entries,
                                                                            sizeof(UBTreeFreeBlockEntry) * inv->capacity);
                        }
                        inv->entries[inv->count].blkno = item->blkno;
                        inv->entries[inv->count].queueBlk = currBlkno;
                        inv->entries[inv->count].offset = offset;
                        inv->count++;
                    }
                }
                offset = nextOffset;
            }

            if ((header->flags & URQ_TAIL_PAGE) != 0) {
                UnlockReleaseBuffer(currBuf);
                break;
            }

            BlockNumber nextBlkno = header->nextBlkno;
            UnlockReleaseBuffer(currBuf);

            if (nextBlkno == firstVisited || !BlockNumberIsValid(nextBlkno)) {
                break;
            }

            currBuf = ReadRecycleQueueBuffer(rel, nextBlkno);
            LockBuffer(currBuf, BT_READ);
        }
    }

    if (inv->count > 1) {
        qsort(inv->entries, inv->count, sizeof(UBTreeFreeBlockEntry), CompareFreeBlockEntries);
        int writeIdx = 1;
        for (int readIdx = 1; readIdx < inv->count; readIdx++) {
            if (inv->entries[readIdx].blkno != inv->entries[writeIdx - 1].blkno) {
                inv->entries[writeIdx++] = inv->entries[readIdx];
            }
        }
        inv->count = writeIdx;
    }
}

/*
 * Scan backwards from trailing blocks of UBTree index to evaluate shrink feasibility.
 */
void UBTreeShrinkCheckInternal(Relation rel, UBTreeShrinkStats *stats, BlockNumber maxPages, double costRatio)
{
    if (stats == NULL || rel == NULL) {
        return;
    }

    BlockNumber effectiveMaxPages = (maxPages > 0) ? maxPages : UBTREE_SHRINK_MAX_MIGRATE_DEFAULT;
    double effectiveCostRatio = (costRatio > 0.0 && costRatio <= 1.0) ? costRatio : UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT;

    stats->totalBlocks = RelationGetNumberOfBlocks(rel);
    stats->freedTailBlocks = 0;
    stats->migratedBlocks = 0;
    stats->targetMaxBlock = stats->totalBlocks;
    stats->migrateTargetCutoff = stats->totalBlocks;
    stats->lockEscalationSuccess = true;
    stats->success = true;

    /* Segment-page tables do not support physical file truncation */
    if (RelationIsSegmentTable(rel)) {
        stats->totalBlocks = 0;
        stats->freedTailBlocks = 0;
        stats->migratedBlocks = 0;
        stats->targetMaxBlock = 0;
        stats->migrateTargetCutoff = 0;
        stats->lockEscalationSuccess = false;
        stats->success = false;
        return;
    }

    if (stats->totalBlocks <= FirstNormalBlockNumber + 1) {
        return;
    }

    /*
     * Walk backwards from the very last block of the index file.
     * Pages that are dead/empty can be safely truncated directly.
     * The first active block encountered establishes the truncation boundary.
     */
    BlockNumber currentBlk = stats->totalBlocks - 1;
    while (currentBlk > FirstNormalBlockNumber) {
        Buffer buf = ReadBuffer(rel, currentBlk);
        LockBuffer(buf, BT_READ);
        Page page = BufferGetPage(buf);
        UBTPageOpaqueInternal opaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(page);

        bool isNew = PageIsNew(page);
        bool isDead = (isNew || P_ISDELETED(opaque));

        if (!isDead && P_ISHALFDEAD(opaque)) {
            /* Try to unlink half-dead page to promote to P_ISDELETED */
            LockBuffer(buf, BUFFER_LOCK_UNLOCK);
            if (ConditionalLockBuffer(buf)) {
                page = BufferGetPage(buf);
                opaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(page);
                if (P_ISHALFDEAD(opaque)) {
                    bool rightsib_empty = false;
                    if (UBTreeUnlinkHalfDeadPage(rel, buf, &rightsib_empty, NULL)) {
                        isDead = true;
                    }
                }
                LockBuffer(buf, BUFFER_LOCK_UNLOCK);
            }
        } else {
            LockBuffer(buf, BUFFER_LOCK_UNLOCK);
        }
        ReleaseBuffer(buf);

        if (isDead) {
            stats->freedTailBlocks++;
        } else {
            break;
        }

        currentBlk--;
    }

    stats->targetMaxBlock = stats->totalBlocks - stats->freedTailBlocks;

    /*
     * Targeted Migration: Check if further truncation is possible by migrating
     * isolated active pages (leaf or internal) from high-watermark blocks to free slots
     * in lower blocks.
     * We use a URQ-driven compaction strategy:
     * 1. Collect free blocks from the UBTree Recycle Queue (URQ) and sort them ascending.
     * 2. Scan backwards from targetMaxBlock - 1 to identify active victim pages.
     * 3. Match victims with the lowest available free slots from URQ (or fallback dead pages).
     * 4. When all victims above tentativeCutoff can be accommodated by free slots strictly below tentativeCutoff,
     *    we compute the cost/benefit ratio and update bestCutoff.
     */
    if (stats->targetMaxBlock > FirstNormalBlockNumber + 2) {
        UBTreeURQInventory inv;
        UBTreeCollectURQFreeBlocks(rel, &inv);

        BlockNumber highScan = stats->targetMaxBlock - 1;
        BlockNumber victimsCount = 0;
        int freeSlotIdx = 0;
        BlockNumber maxAllocatedSlot = 0;

        BlockNumber bestCutoff = stats->targetMaxBlock;
        BlockNumber bestVictims = 0;
        BlockNumber bestFreed = stats->freedTailBlocks;

        while (highScan > FirstNormalBlockNumber && victimsCount < effectiveMaxPages) {
            Buffer hBuf = ReadBuffer(rel, highScan);
            LockBuffer(hBuf, BT_READ);
            Page hPage = BufferGetPage(hBuf);
            UBTPageOpaqueInternal hOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(hPage);

            bool hDead = (PageIsNew(hPage) || P_ISDELETED(hOpaque));
            bool hRoot = P_ISROOT(hOpaque);

            LockBuffer(hBuf, BUFFER_LOCK_UNLOCK);
            ReleaseBuffer(hBuf);

            if (hDead) {
                /* Dead page encountered: check if highScan can be an eligible cutoff */
                if (victimsCount > 0) {
                    BlockNumber minSafeCutoff = maxAllocatedSlot + 1;
                    if (highScan >= minSafeCutoff) {
                        BlockNumber tentativeCutoff = highScan;
                        BlockNumber tentativeFreed = stats->totalBlocks - tentativeCutoff;
                        if (tentativeFreed > bestFreed) {
                            double ratio = (double)victimsCount / (double)tentativeFreed;
                            if (ratio <= effectiveCostRatio) {
                                bestVictims = victimsCount;
                                bestCutoff = tentativeCutoff;
                                bestFreed = tentativeFreed;
                            }
                        }
                    }
                }
            } else if (!hRoot) {
                /* Active page: candidate victim */
                /* Find next available slot in inv strictly below highScan */
                while (freeSlotIdx < inv.count && inv.entries[freeSlotIdx].blkno >= highScan) {
                    freeSlotIdx++;
                }

                if (freeSlotIdx < inv.count) {
                    maxAllocatedSlot = Max(maxAllocatedSlot, inv.entries[freeSlotIdx].blkno);
                    victimsCount++;
                    freeSlotIdx++;

                    BlockNumber minSafeCutoff = maxAllocatedSlot + 1;
                    if (highScan >= minSafeCutoff) {
                        BlockNumber tentativeCutoff = highScan;
                        BlockNumber tentativeFreed = stats->totalBlocks - tentativeCutoff;
                        if (tentativeFreed > bestFreed) {
                            double ratio = (double)victimsCount / (double)tentativeFreed;
                            if (ratio <= effectiveCostRatio) {
                                bestVictims = victimsCount;
                                bestCutoff = tentativeCutoff;
                                bestFreed = tentativeFreed;
                            }
                        }
                    }
                } else {
                    /* No more free slots in URQ below highScan */
                    break;
                }
            } else {
                /* Root page encountered, stop */
                break;
            }

            highScan--;
        }

        if (inv.entries != NULL) {
            pfree(inv.entries);
        }

        if (bestVictims > 0 && bestCutoff < stats->targetMaxBlock) {
            stats->migratedBlocks = bestVictims;
            stats->migrateTargetCutoff = bestCutoff;
        }
    }
}

/*
 * Phase 3 Online Physical Truncation with brief Lock Escalation.
 */
static bool UBTreeOnlineTruncate(Relation rel, BlockNumber targetMaxBlock, UBTreeShrinkStats *stats)
{
    bool lockAcquired = false;
    int maxRetries = (UBTREE_SHRINK_LOCK_TIMEOUT_MS * 1000) / UBTREE_SHRINK_LOCK_RETRY_INTERVAL_US;

    /*
     * Attempt to briefly escalate to AccessExclusiveLock without blocking concurrent operations.
     */
    for (int retry = 0; retry < maxRetries; retry++) {
        if (ConditionalLockRelation(rel, AccessExclusiveLock)) {
            lockAcquired = true;
            break;
        }
        pg_usleep(UBTREE_SHRINK_LOCK_RETRY_INTERVAL_US);
        CHECK_FOR_INTERRUPTS();
    }

    if (!lockAcquired) {
        /* Could not acquire lock in brief window; back out gracefully */
        stats->lockEscalationSuccess = false;
        return false;
    }

    stats->lockEscalationSuccess = true;

    /*
     * Double-Check under AccessExclusiveLock:
     * Ensure no concurrent transaction extended or wrote active pages into the tail region
     * between the initial check and acquiring AccessExclusiveLock.
     */
    UBTreeShrinkStats recheckStats;
    UBTreeShrinkCheckInternal(rel, &recheckStats);

    /* If the valid truncation boundary shifted higher, adjust targetMaxBlock or abort if no blocks can be freed */
    if (recheckStats.targetMaxBlock > targetMaxBlock) {
        targetMaxBlock = recheckStats.targetMaxBlock;
    }

    stats->targetMaxBlock = targetMaxBlock;
    stats->freedTailBlocks = recheckStats.totalBlocks > targetMaxBlock ? (recheckStats.totalBlocks - targetMaxBlock) : 0;

    if (stats->freedTailBlocks == 0 || targetMaxBlock >= recheckStats.totalBlocks) {
        UnlockRelation(rel, AccessExclusiveLock);
        return true;
    }

    /* Under AccessExclusiveLock: purge URQ and safely truncate file */
    UBTreePurgeRecycleQueueAboveWatermark(rel, targetMaxBlock);

    LockRelationForExtension(rel, ExclusiveLock);
    BlockNumber currentTotal = RelationGetNumberOfBlocks(rel);
    if (currentTotal > targetMaxBlock) {
        RelationTruncate(rel, targetMaxBlock);
    }
    UnlockRelationForExtension(rel, ExclusiveLock);

    UnlockRelation(rel, AccessExclusiveLock);

    return true;
}

/*
 * Migrate one active page (leaf or internal non-root page) from victimBlk
 * to a newly allocated free page below targetMaxBlock.
 * Locks coupling:
 * 1. victimBuf (BT_WRITE)
 * 2. leftBuf (BT_WRITE)
 * 3. rightBuf (BT_WRITE)
 * 4. parentBuf (BT_WRITE via UBTreeSearch/UBTreeGetStackBuf)
 */
static bool UBTreeMigrateOnePage(Relation rel, BlockNumber victimBlk, BlockNumber targetMaxBlock, bool isOnline,
                                 BlockNumber targetFreeBlk = InvalidBlockNumber,
                                 BlockNumber targetQueueBlk = InvalidBlockNumber,
                                 uint16 targetOffset = 0)
{
    /* Refresh transaction horizon for URQ page recycling */
    TransactionId recycleXmin = InvalidTransactionId;
    TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
    if (TransactionIdIsValid(recycleXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = recycleXmin;
    } else if (TransactionIdIsValid(oldestXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = oldestXmin;
    }

    /*
     * Step 1: Read victim page to inspect topology and construct search key.
     * We only hold a read lock momentarily to inspect the page and build the key,
     * then unlock it so UBTreeSearch can safely descend without self-deadlock.
     */
    Buffer victimBuf = ReadBuffer(rel, victimBlk);
    LockBuffer(victimBuf, BT_READ);
    Page victimPage = BufferGetPage(victimBuf);
    UBTPageOpaqueInternal victimOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(victimPage);

    /* Verify victim page is still an active, non-root page (leaf or internal) */
    if (P_ISROOT(victimOpaque) ||
        P_ISDELETED(victimOpaque) || P_ISHALFDEAD(victimOpaque) || P_INCOMPLETE_SPLIT(victimOpaque)) {
        _bt_relbuf(rel, victimBuf);
        return false;
    }

    bool isRightMost = P_RIGHTMOST(victimOpaque);
    bool isLeaf = P_ISLEAF(victimOpaque);
    uint16 victimLevel = victimOpaque->btpo.level;
    BlockNumber leftBlk = victimOpaque->btpo_prev;
    BlockNumber rightBlk = victimOpaque->btpo_next;

    /* Construct search key for parent downlink */
    IndexTuple targetKey = NULL;
    BTScanInsert itupKey = NULL;

    if (!isRightMost) {
        ItemId hikeyItem = PageGetItemId(victimPage, P_HIKEY);
        targetKey = CopyIndexTuple((IndexTuple)PageGetItem(victimPage, hikeyItem));
        itupKey = UBTreeMakeScanKey(rel, targetKey);
        itupKey->pivotsearch = true;
    } else {
        OffsetNumber maxoff = PageGetMaxOffsetNumber(victimPage);
        OffsetNumber keyOff = isLeaf ? 1 : 2;
        if (maxoff >= keyOff) {
            ItemId item = PageGetItemId(victimPage, keyOff);
            targetKey = CopyIndexTuple((IndexTuple)PageGetItem(victimPage, item));
            itupKey = UBTreeMakeScanKey(rel, targetKey);
            itupKey->pivotsearch = false;
        } else if (leftBlk != P_NONE) {
            Buffer lbuf = ReadBuffer(rel, leftBlk);
            LockBuffer(lbuf, BT_READ);
            Page leftPage = BufferGetPage(lbuf);
            if (PageGetMaxOffsetNumber(leftPage) >= P_HIKEY) {
                ItemId leftHiKeyItem = PageGetItemId(leftPage, P_HIKEY);
                targetKey = CopyIndexTuple((IndexTuple)PageGetItem(leftPage, leftHiKeyItem));
                itupKey = UBTreeMakeScanKey(rel, targetKey);
                itupKey->pivotsearch = true;
            }
            _bt_relbuf(rel, lbuf);
        }
    }

    /* Release read lock on victim page before searching to prevent self-deadlock */
    LockBuffer(victimBuf, BUFFER_LOCK_UNLOCK);

    Buffer parentBuf = InvalidBuffer;
    OffsetNumber parentOff = InvalidOffsetNumber;

    if (itupKey != NULL) {
        /*
         * Step 2: Search B-Tree from root to find parent stack.
         * With no write locks held, UBTreeSearch will not deadlock with our thread.
         */
        Buffer leafSearchBuf = InvalidBuffer;
        BTStack stack = UBTreeSearch(rel, itupKey, &leafSearchBuf, BT_READ);
        if (BufferIsValid(leafSearchBuf)) {
            _bt_relbuf(rel, leafSearchBuf);
        }

        if (stack != NULL) {
            BTStack targetStack = NULL;
            for (BTStack s = stack; s != NULL; s = s->bts_parent) {
                if (s->bts_btentry == victimBlk) {
                    targetStack = s;
                    break;
                }
            }
            if (targetStack == NULL && isLeaf) {
                targetStack = stack;
                targetStack->bts_btentry = victimBlk;
            }
            if (targetStack != NULL) {
                parentBuf = UBTreeGetStackBuf(rel, targetStack);
                if (BufferIsValid(parentBuf)) {
                    parentOff = targetStack->bts_offset;
                }
            }
            _bt_freestack(stack);
        }

        pfree(itupKey);
        if (targetKey != NULL) {
            pfree(targetKey);
        }
    }

    if (!BufferIsValid(parentBuf) || parentOff == InvalidOffsetNumber) {
        if (BufferIsValid(parentBuf)) {
            _bt_relbuf(rel, parentBuf);
            parentBuf = InvalidBuffer;
            parentOff = InvalidOffsetNumber;
        }

        /*
         * Level-aware parent locator fallback:
         * Works universally for both internal pages (victimLevel > 0) and leaf pages (victimLevel == 0).
         * Safely check metadata level, retrieve the leftmost block of parentLevel (victimLevel + 1),
         * and scan across the parent level using UBTreeGetStackBuf to locate and lock the parent downlink.
         */
        Buffer metabuf = _bt_getbuf(rel, BTREE_METAPAGE, BT_READ);
        Page metapg = BufferGetPage(metabuf);
        BTMetaPageData *metad = BTPageGetMeta(metapg);
        uint32 maxLevel = metad->btm_level;
        _bt_relbuf(rel, metabuf);

        uint16 parentLevel = victimLevel + 1;
        if (parentLevel <= maxLevel) {
            Buffer pbuf = UBTreeGetEndPoint(rel, parentLevel, false);
            if (BufferIsValid(pbuf)) {
                BTStackData fakestack;
                fakestack.bts_blkno = BufferGetBlockNumber(pbuf);
                fakestack.bts_offset = InvalidOffsetNumber;
                fakestack.bts_btentry = victimBlk;
                fakestack.bts_parent = NULL;
                _bt_relbuf(rel, pbuf);

                parentBuf = UBTreeGetStackBuf(rel, &fakestack);
                if (BufferIsValid(parentBuf)) {
                    parentOff = fakestack.bts_offset;
                }
            }
        }
    }

    if (!BufferIsValid(parentBuf) || parentOff == InvalidOffsetNumber) {
        if (BufferIsValid(parentBuf)) {
            _bt_relbuf(rel, parentBuf);
        }
        ReleaseBuffer(victimBuf);
        return false;
    }

    /*
     * Step 3: Now acquire write lock on victimBuf and verify state.
     * Top-down locking: parentBuf is already held with BT_WRITE, now lock victimBuf.
     */
    if (isOnline) {
        if (!ConditionalLockBuffer(victimBuf)) {
            _bt_relbuf(rel, parentBuf);
            ReleaseBuffer(victimBuf);
            return false;
        }
    } else {
        LockBuffer(victimBuf, BT_WRITE);
    }

    victimPage = BufferGetPage(victimBuf);
    victimOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(victimPage);
    if (P_ISROOT(victimOpaque) || P_ISDELETED(victimOpaque) || P_ISHALFDEAD(victimOpaque)) {
        _bt_relbuf(rel, victimBuf);
        _bt_relbuf(rel, parentBuf);
        return false;
    }

    Page parentPage = BufferGetPage(parentBuf);
    ItemId pItem = PageGetItemId(parentPage, parentOff);
    IndexTuple pItup = (IndexTuple)PageGetItem(parentPage, pItem);
    if (BTreeInnerTupleGetDownLink(pItup) != victimBlk) {
        _bt_relbuf(rel, victimBuf);
        _bt_relbuf(rel, parentBuf);
        return false;
    }

    /*
     * Step 4: Lock left sibling if exists.
     */
    Buffer leftBuf = InvalidBuffer;
    if (leftBlk != P_NONE) {
        leftBuf = ReadBuffer(rel, leftBlk);
        if (isOnline) {
            if (!ConditionalLockBuffer(leftBuf)) {
                ReleaseBuffer(leftBuf);
                _bt_relbuf(rel, victimBuf);
                _bt_relbuf(rel, parentBuf);
                return false;
            }
        } else {
            LockBuffer(leftBuf, BT_WRITE);
        }
        Page leftPage = BufferGetPage(leftBuf);
        UBTPageOpaqueInternal leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        if (leftOpaque->btpo_next != victimBlk || P_ISDELETED(leftOpaque)) {
            _bt_relbuf(rel, leftBuf);
            _bt_relbuf(rel, victimBuf);
            _bt_relbuf(rel, parentBuf);
            return false;
        }
    }

    /*
     * Step 5: Lock right sibling if exists.
     */
    Buffer rightBuf = InvalidBuffer;
    if (!isRightMost && rightBlk != P_NONE) {
        rightBuf = ReadBuffer(rel, rightBlk);
        if (isOnline) {
            if (!ConditionalLockBuffer(rightBuf)) {
                ReleaseBuffer(rightBuf);
                if (BufferIsValid(leftBuf)) {
                    _bt_relbuf(rel, leftBuf);
                }
                _bt_relbuf(rel, victimBuf);
                _bt_relbuf(rel, parentBuf);
                return false;
            }
        } else {
            LockBuffer(rightBuf, BT_WRITE);
        }
        Page rightPage = BufferGetPage(rightBuf);
        UBTPageOpaqueInternal rightOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(rightPage);
        if (rightOpaque->btpo_prev != victimBlk || P_ISDELETED(rightOpaque)) {
            _bt_relbuf(rel, rightBuf);
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, victimBuf);
            _bt_relbuf(rel, parentBuf);
            return false;
        }
    }

    /*
     * Step 6: Allocate free page below targetMaxBlock.
     * If a specific targetFreeBlk from URQ was designated, try to acquire it first.
     */
    Buffer newBuf = InvalidBuffer;
    BlockNumber newBlk = InvalidBlockNumber;
    UBTRecycleQueueAddress newAddr;
    newAddr.queueBuf = InvalidBuffer;
    bool fromURQDirect = false;

    if (BlockNumberIsValid(targetFreeBlk) && targetFreeBlk < targetMaxBlock &&
        targetFreeBlk != leftBlk && targetFreeBlk != rightBlk && targetFreeBlk != victimBlk &&
        (!BufferIsValid(parentBuf) || targetFreeBlk != BufferGetBlockNumber(parentBuf))) {
        Buffer testBuf = ReadBuffer(rel, targetFreeBlk);
        bool gotLock = isOnline ? ConditionalLockBuffer(testBuf) : (LockBuffer(testBuf, BT_WRITE), true);
        if (gotLock) {
            Page testPage = BufferGetPage(testBuf);
            UBTPageOpaqueInternal testOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(testPage);
            if (PageIsNew(testPage) || P_ISDELETED(testOpaque)) {
                newBuf = testBuf;
                newBlk = targetFreeBlk;
                fromURQDirect = true;
            } else {
                LockBuffer(testBuf, BUFFER_LOCK_UNLOCK);
                ReleaseBuffer(testBuf);
            }
        } else {
            ReleaseBuffer(testBuf);
        }
    }

    if (!BufferIsValid(newBuf)) {
        for (int retry = 0; retry < 50; retry++) {
            UBTRecycleQueueAddress addr;
            addr.queueBuf = InvalidBuffer;
            newBuf = UBTreeGetAvailablePage(rel, RECYCLE_FREED_FORK, &addr, NULL);
            if (newBuf == InvalidBuffer) {
                newBuf = UBTreeGetAvailablePage(rel, RECYCLE_EMPTY_FORK, &addr, NULL);
            }
            if (newBuf == InvalidBuffer) {
                if (addr.queueBuf != InvalidBuffer) {
                    ReleaseBuffer(addr.queueBuf);
                }
                break;
            }
            newBlk = BufferGetBlockNumber(newBuf);
            if (newBlk < targetMaxBlock) {
                newAddr = addr;
                break;
            }
            if (addr.queueBuf != InvalidBuffer) {
                ReleaseBuffer(addr.queueBuf);
            }
            _bt_relbuf(rel, newBuf);
            newBuf = InvalidBuffer;
        }
    }

    if (newBuf == InvalidBuffer || newBlk >= targetMaxBlock) {
        for (BlockNumber blk = FirstNormalBlockNumber + 1; blk < targetMaxBlock; blk++) {
            if (blk == leftBlk || blk == rightBlk || blk == victimBlk ||
                (BufferIsValid(parentBuf) && blk == BufferGetBlockNumber(parentBuf))) {
                continue;
            }
            Buffer testBuf = ReadBuffer(rel, blk);
            bool gotLock = isOnline ? ConditionalLockBuffer(testBuf) : (LockBuffer(testBuf, BT_WRITE), true);
            if (gotLock) {
                Page testPage = BufferGetPage(testBuf);
                UBTPageOpaqueInternal testOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(testPage);
                if (PageIsNew(testPage) || P_ISDELETED(testOpaque)) {
                    newBuf = testBuf;
                    newBlk = blk;
                    newAddr.queueBuf = InvalidBuffer;
                    break;
                }
                LockBuffer(testBuf, BUFFER_LOCK_UNLOCK);
            }
            ReleaseBuffer(testBuf);
        }
    }

    if (newBuf == InvalidBuffer || newBlk >= targetMaxBlock) {
        if (newAddr.queueBuf != InvalidBuffer) {
            ReleaseBuffer(newAddr.queueBuf);
        }
        if (BufferIsValid(newBuf)) {
            _bt_relbuf(rel, newBuf);
        }
        if (BufferIsValid(rightBuf)) {
            _bt_relbuf(rel, rightBuf);
        }
        if (BufferIsValid(leftBuf)) {
            _bt_relbuf(rel, leftBuf);
        }
        _bt_relbuf(rel, victimBuf);
        _bt_relbuf(rel, parentBuf);
        return false;
    }

    /*
     * Step 7: Critical section - perform atomic migration.
     */
    START_CRIT_SECTION();

    Page newPage = BufferGetPage(newBuf);
    UBTreePageInit(newPage, BLCKSZ);
    memcpy(newPage, victimPage, BLCKSZ);

    UBTPageOpaqueInternal newOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(newPage);
    newOpaque->btpo_prev = leftBlk;
    newOpaque->btpo_next = rightBlk;

    /* Update sibling links */
    if (BufferIsValid(leftBuf)) {
        Page leftPage = BufferGetPage(leftBuf);
        UBTPageOpaqueInternal leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        leftOpaque->btpo_next = newBlk;
        MarkBufferDirty(leftBuf);
    }

    if (BufferIsValid(rightBuf)) {
        Page rightPage = BufferGetPage(rightBuf);
        UBTPageOpaqueInternal rightOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(rightPage);
        rightOpaque->btpo_prev = newBlk;
        MarkBufferDirty(rightBuf);
    }

    /* Update parent downlink */
    parentPage = BufferGetPage(parentBuf);
    pItem = PageGetItemId(parentPage, parentOff);
    pItup = (IndexTuple)PageGetItem(parentPage, pItem);
    UBTreeTupleSetDownLink(pItup, newBlk);
    MarkBufferDirty(parentBuf);

    /* Mark victim page as deleted and point its right-link to newBlk for in-flight forward scanners */
    victimOpaque->btpo_flags |= BTP_DELETED;
    victimOpaque->btpo_next = newBlk;
    ((UBTPageOpaque)victimOpaque)->xact = ReadNewTransactionId();

    MarkBufferDirty(newBuf);
    MarkBufferDirty(victimBuf);

    /* Emit atomic WAL for moving page */
    if (RelationNeedsWAL(rel)) {
        xl_ubtree2_shrink_move_leaf xlrec;
        XLogRecPtr recptr;

        xlrec.victimBlk = victimBlk;
        xlrec.newBlk = newBlk;
        xlrec.leftBlk = leftBlk;
        xlrec.rightBlk = rightBlk;
        xlrec.parentBlk = BufferGetBlockNumber(parentBuf);
        xlrec.parentOff = parentOff;
        xlrec.isRightMost = isRightMost;

        XLogBeginInsert();
        XLogRegisterData((char *)&xlrec, SizeOfUBTree2ShrinkMoveLeaf);
        XLogRegisterBuffer(0, newBuf, REGBUF_FORCE_IMAGE | REGBUF_STANDARD);
        XLogRegisterBuffer(1, victimBuf, REGBUF_STANDARD);
        if (BufferIsValid(leftBuf)) {
            XLogRegisterBuffer(2, leftBuf, REGBUF_STANDARD);
        }
        if (BufferIsValid(rightBuf)) {
            XLogRegisterBuffer(3, rightBuf, REGBUF_STANDARD);
        }
        XLogRegisterBuffer(4, parentBuf, REGBUF_STANDARD);

        recptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_MOVE_LEAF);

        PageSetLSN(newPage, recptr);
        PageSetLSN(victimPage, recptr);
        if (BufferIsValid(leftBuf)) {
            PageSetLSN(BufferGetPage(leftBuf), recptr);
        }
        if (BufferIsValid(rightBuf)) {
            PageSetLSN(BufferGetPage(rightBuf), recptr);
        }
        PageSetLSN(parentPage, recptr);
    }

    END_CRIT_SECTION();

    if (fromURQDirect && BlockNumberIsValid(targetQueueBlk)) {
        Buffer qbuf = ReadRecycleQueueBuffer(rel, targetQueueBlk);
        LockBuffer(qbuf, BT_WRITE);
        RemoveOneItemFromPage(rel, qbuf, targetOffset);
        UnlockReleaseBuffer(qbuf);
    } else if (newAddr.queueBuf != InvalidBuffer) {
        UBTreeRecordUsedPage(rel, newAddr);
        ReleaseBuffer(newAddr.queueBuf);
    }

    _bt_relbuf(rel, newBuf);
    if (BufferIsValid(rightBuf)) {
        _bt_relbuf(rel, rightBuf);
    }
    if (BufferIsValid(leftBuf)) {
        _bt_relbuf(rel, leftBuf);
    }
    _bt_relbuf(rel, victimBuf);
    _bt_relbuf(rel, parentBuf);

    return true;
}

/*
 * Iterate through high-watermark blocks (between migrateTargetCutoff and totalBlocks)
 * and migrate active pages (leaf or internal) down into free slots below migrateTargetCutoff.
 */
static void UBTreeMigratePages(Relation rel, UBTreeShrinkStats *stats, bool isOnline)
{
    if (stats->migratedBlocks == 0 || stats->migrateTargetCutoff >= stats->totalBlocks) {
        return;
    }

    UBTreeURQInventory inv;
    UBTreeCollectURQFreeBlocks(rel, &inv);

    BlockNumber currentBlk = stats->totalBlocks - 1;
    BlockNumber cutoff = stats->migrateTargetCutoff;
    BlockNumber migratedCount = 0;
    int freeSlotIdx = 0;

    while (currentBlk >= cutoff) {
        Buffer buf = ReadBuffer(rel, currentBlk);
        LockBuffer(buf, BT_READ);
        Page page = BufferGetPage(buf);
        UBTPageOpaqueInternal opaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(page);

        bool isDead = (PageIsNew(page) || P_ISDELETED(opaque));
        bool isRoot = P_ISROOT(opaque);

        LockBuffer(buf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(buf);

        if (!isDead && !isRoot) {
            BlockNumber targetFreeBlk = InvalidBlockNumber;
            BlockNumber targetQueueBlk = InvalidBlockNumber;
            uint16 targetOffset = 0;

            while (freeSlotIdx < inv.count) {
                if (inv.entries[freeSlotIdx].blkno < cutoff && inv.entries[freeSlotIdx].blkno < currentBlk) {
                    targetFreeBlk = inv.entries[freeSlotIdx].blkno;
                    targetQueueBlk = inv.entries[freeSlotIdx].queueBlk;
                    targetOffset = inv.entries[freeSlotIdx].offset;
                    freeSlotIdx++;
                    break;
                }
                freeSlotIdx++;
            }

            if (UBTreeMigrateOnePage(rel, currentBlk, stats->migrateTargetCutoff, isOnline,
                                     targetFreeBlk, targetQueueBlk, targetOffset)) {
                migratedCount++;
            }
        }

        if (currentBlk == 0) {
            break;
        }
        currentBlk--;
    }

    if (inv.entries != NULL) {
        pfree(inv.entries);
    }

    stats->migratedBlocks = migratedCount;
}

/*
 * Primary entry point for UBTree Index Shrink (Phase 3 Online / Phase 1 Offline).
 */
bool UBTreeShrink(Relation rel, UBTreeShrinkStats *stats, bool isOnline, BlockNumber maxPages, double costRatio)
{
    if (rel == NULL || RelationIsSegmentTable(rel)) {
        return false;
    }

    /* Refresh transaction horizon for URQ page recycling */
    TransactionId recycleXmin = InvalidTransactionId;
    TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
    if (TransactionIdIsValid(recycleXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = recycleXmin;
    } else if (TransactionIdIsValid(oldestXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = oldestXmin;
    }

    UBTreeShrinkCheckInternal(rel, stats, maxPages, costRatio);
    if (stats->totalBlocks <= FirstNormalBlockNumber + 1) {
        return true;
    }

    /* Execute targeted migration if eligible victim blocks were identified */
    int migrationRounds = 0;
    while (stats->migratedBlocks > 0 && migrationRounds < 10) {
        BlockNumber prevFreedTail = stats->freedTailBlocks;
        BlockNumber prevTargetMax = stats->targetMaxBlock;
        UBTreeMigratePages(rel, stats, isOnline);
        migrationRounds++;
        /* Re-evaluate shrink boundaries after migration */
        UBTreeShrinkCheckInternal(rel, stats, maxPages, costRatio);
        /* If no new tail blocks were freed, stop to prevent looping */
        if (stats->freedTailBlocks <= prevFreedTail && stats->targetMaxBlock >= prevTargetMax) {
            break;
        }
    }

    if (stats->freedTailBlocks == 0) {
        return true;
    }

    BlockNumber targetMaxBlock = stats->targetMaxBlock;

    if (isOnline) {
        /*
         * Phase 3: Online Shrink under ShareUpdateExclusiveLock with
         * microsecond lock escalation during physical truncate.
         */
        if (!UBTreeOnlineTruncate(rel, targetMaxBlock, stats)) {
            stats->success = false;
            return false;
        }
    } else {
        /*
         * Phase 1 Offline mode: Caller holds AccessExclusiveLock already.
         */
        UBTreePurgeRecycleQueueAboveWatermark(rel, targetMaxBlock);

        LockRelationForExtension(rel, ExclusiveLock);
        BlockNumber currentTotal = RelationGetNumberOfBlocks(rel);
        if (currentTotal > targetMaxBlock) {
            RelationTruncate(rel, targetMaxBlock);
        }
        UnlockRelationForExtension(rel, ExclusiveLock);
    }

    return true;
}

/*
 * SQL callable system function: gs_ubtree_shrink(relname text, is_online bool DEFAULT true)
 * Supports both Phase 3 Online Shrink and Phase 1 Offline Shrink.
 */
Datum gs_ubtree_shrink(PG_FUNCTION_ARGS)
{
    if (!superuser() && !systemDBA_arg(GetUserId())) {
        ereport(ERROR, (errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
                        errmsg("must be superuser or system admin to shrink index")));
    }

    text *relnameText = PG_GETARG_TEXT_P(0);
    bool isOnline = true;
    BlockNumber maxPages = UBTREE_SHRINK_MAX_MIGRATE_DEFAULT;
    double costRatio = UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT;

    if (PG_NARGS() > 1 && !PG_ARGISNULL(1)) {
        isOnline = PG_GETARG_BOOL(1);
    }
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2)) {
        int userMax = PG_GETARG_INT32(2);
        if (userMax > 0) {
            maxPages = (BlockNumber)userMax;
        }
    }
    if (PG_NARGS() > 3 && !PG_ARGISNULL(3)) {
        double userRatio = PG_GETARG_FLOAT8(3);
        if (userRatio > 0.0 && userRatio <= 1.0) {
            costRatio = userRatio;
        }
    }

    RangeVar *relvar = makeRangeVarFromNameList(textToQualifiedNameList(relnameText));

    /*
     * Locking strategy:
     * - Phase 3 Online Shrink: ShareUpdateExclusiveLock (allows concurrent SELECT/INSERT/DELETE)
     * - Phase 1 Offline Shrink: AccessExclusiveLock (exclusive maintenance mode)
     */
    LOCKMODE lockMode = isOnline ? ShareUpdateExclusiveLock : AccessExclusiveLock;
    Oid relid = RangeVarGetRelid(relvar, lockMode, false);
    Relation rel = index_open(relid, lockMode);

    if (rel->rd_rel->relam != UBTREE_AM_OID) {
        index_close(rel, lockMode);
        ereport(ERROR, (errcode(ERRCODE_WRONG_OBJECT_TYPE),
                        errmsg("\"%s\" is not a UBTree index", RelationGetRelationName(rel))));
    }

    if (RelationIsSegmentTable(rel)) {
        index_close(rel, lockMode);
        ereport(WARNING, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                          errmsg("cannot shrink segment-page UBTree index \"%s\"",
                                 RelationGetRelationName(rel))));
        PG_RETURN_BOOL(false);
    }

    UBTreeShrinkStats stats;
    bool result = UBTreeShrink(rel, &stats, isOnline, maxPages, costRatio);

    index_close(rel, lockMode);

    if (!result && isOnline && !stats.lockEscalationSuccess) {
        ereport(NOTICE, (errmsg("gs_ubtree_shrink for \"%s\" postponed: could not acquire brief exclusive lock "
                                "within timeout, non-blocking online shrink backed off.",
                                RelationGetRelationName(rel))));
    }

    PG_RETURN_BOOL(result);
}

/*
 * SQL callable system function: gs_ubtree_shrink_check(relname text)
 */
Datum gs_ubtree_shrink_check(PG_FUNCTION_ARGS)
{
    text *relnameText = PG_GETARG_TEXT_P(0);
    BlockNumber maxPages = UBTREE_SHRINK_MAX_MIGRATE_DEFAULT;
    double costRatio = UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT;

    if (PG_NARGS() > 1 && !PG_ARGISNULL(1)) {
        int userMax = PG_GETARG_INT32(1);
        if (userMax > 0) {
            maxPages = (BlockNumber)userMax;
        }
    }
    if (PG_NARGS() > 2 && !PG_ARGISNULL(2)) {
        double userRatio = PG_GETARG_FLOAT8(2);
        if (userRatio > 0.0 && userRatio <= 1.0) {
            costRatio = userRatio;
        }
    }

    RangeVar *relvar = makeRangeVarFromNameList(textToQualifiedNameList(relnameText));
    Oid relid = RangeVarGetRelid(relvar, AccessShareLock, false);

    Relation rel = index_open(relid, AccessShareLock);

    if (rel->rd_rel->relam != UBTREE_AM_OID) {
        index_close(rel, AccessShareLock);
        ereport(ERROR, (errcode(ERRCODE_WRONG_OBJECT_TYPE),
                        errmsg("\"%s\" is not a UBTree index", RelationGetRelationName(rel))));
    }

    if (RelationIsSegmentTable(rel)) {
        index_close(rel, AccessShareLock);
        ereport(WARNING, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                          errmsg("cannot check segment-page UBTree index \"%s\"",
                                 RelationGetRelationName(rel))));
        PG_RETURN_TEXT_P(cstring_to_text("TotalBlocks: 0, TargetMaxBlock: 0, FreeTailBlocks: 0, MigratedBlocks: 0 (Segment-page UBTree index does not support physical shrink)"));
    }

    /* Refresh transaction horizon for URQ page recycling check */
    TransactionId recycleXmin = InvalidTransactionId;
    TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
    if (TransactionIdIsValid(recycleXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = recycleXmin;
    } else if (TransactionIdIsValid(oldestXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = oldestXmin;
    }

    UBTreeShrinkStats stats;
    UBTreeShrinkCheckInternal(rel, &stats, maxPages, costRatio);

    index_close(rel, AccessShareLock);

    StringInfoData buf;
    initStringInfo(&buf);
    BlockNumber checkTargetMaxBlock = (stats.migratedBlocks > 0) ? stats.migrateTargetCutoff : stats.targetMaxBlock;
    BlockNumber checkFreedTailBlocks = (stats.migratedBlocks > 0) ? (stats.totalBlocks - stats.migrateTargetCutoff) : stats.freedTailBlocks;
    appendStringInfo(&buf, "TotalBlocks: %u, TargetMaxBlock: %u, FreeTailBlocks: %u, MigratedBlocks: %u",
                     stats.totalBlocks, checkTargetMaxBlock, checkFreedTailBlocks, stats.migratedBlocks);

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}
