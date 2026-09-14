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
void UBTreePurgeRecycleQueueAboveWatermark(Relation rel, BlockNumber targetMaxBlock)
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

/*
 * Check whether any buffer in relation with blkno >= firstDelBlock has an active pin.
 * Used as a safety barrier before RelationTruncate to prevent read beyond EOF or dirty page panic.
 */
static bool UBTreeCheckBuffersPinned(Relation rel, BlockNumber firstDelBlock)
{
    RelFileNode node = rel->rd_node;
    for (int i = 0; i < SegmentBufferStartID; i++) {
        BufferDesc *buf_desc = GetBufferDescriptor(i);
        if (!RelFileNodeEquals(buf_desc->tag.rnode, node)) {
            continue;
        }
        uint64 buf_state = LockBufHdr(buf_desc);
        if (RelFileNodeEquals(buf_desc->tag.rnode, node) &&
            buf_desc->tag.forkNum == MAIN_FORKNUM &&
            buf_desc->tag.blockNum >= firstDelBlock) {
            if (BUF_STATE_GET_REFCOUNT(buf_state) != 0) {
                UnlockBufHdr(buf_desc, buf_state);
                return true;
            }
        }
        UnlockBufHdr(buf_desc, buf_state);
    }
    return false;
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
static void UBTreeCollectURQFreeBlocks(Relation rel, UBTreeURQInventory *inv, TransactionId safeRecycleXmin)
{
    inv->count = 0;
    inv->capacity = 1024;
    inv->entries = (UBTreeFreeBlockEntry *)palloc0(sizeof(UBTreeFreeBlockEntry) * inv->capacity);

    if (!RecycleQueueInitialized(rel)) {
        return;
    }

    TransactionId oldestXmin = safeRecycleXmin;
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
void UBTreeShrinkCheckInternal(Relation rel, UBTreeShrinkStats *stats, BlockNumber maxPages, double costRatio,
                                TransactionId safeRecycleXmin)
{
    if (stats == NULL || rel == NULL) {
        return;
    }

    if (!TransactionIdIsValid(safeRecycleXmin)) {
        TransactionId recycleXmin = InvalidTransactionId;
        TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
        safeRecycleXmin = TransactionIdIsValid(recycleXmin) ? recycleXmin : oldestXmin;
        if (!TransactionIdIsValid(safeRecycleXmin)) {
            safeRecycleXmin = u_sess->utils_cxt.RecentGlobalDataXmin;
        }
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
        UBTreeCollectURQFreeBlocks(rel, &inv, safeRecycleXmin);

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

    /*
     * Safety Barrier: Check if any backend or background worker still holds
     * a pin on any buffer in [targetMaxBlock, currentTotal).
     * If so, gracefully back off instead of truncating under an active pin,
     * which would lead to 'read/write beyond EOF' PANIC.
     */
    if (UBTreeCheckBuffersPinned(rel, targetMaxBlock)) {
        UnlockRelation(rel, AccessExclusiveLock);
        stats->lockEscalationSuccess = false;
        return false;
    }

    /* Under AccessExclusiveLock: log URQ purge, purge URQ and safely truncate file */
    if (RelationNeedsWAL(rel)) {
        xl_ubtree2_urq_purge xlrec;
        xlrec.node = rel->rd_node;
        xlrec.targetMaxBlock = targetMaxBlock;

        XLogBeginInsert();
        XLogRegisterData((char *)&xlrec, SizeOfUBTree2UrqPurge);
        (void)XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_URQ_PURGE);
    }

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
 *
 * Implements Lehman-Yao Two-Phase Decoupled Migration Protocol:
 * Phase 1: Horizontal leaf chain migration (strictly Left-to-Right locking):
 *          leftBuf -> victimBuf -> rightBuf -> newBuf.
 *          Does NOT hold any parent lock, eliminating vertical AB-BA deadlocks with splits.
 *          Sets Lehman-Yao forwarding pointer on victimPage (BTP_DELETED + btpo_next = newBlk)
 *          to ensure concurrent index scans follow right-links to newBlk with zero loss.
 * Phase 2: Bottom-Up parent downlink correction:
 *          After Phase 1 locks are released, searches parent and updates downlink to newBlk.
 *          If parent concurrently split, follows right-links (_bt_moveright) to find the downlink.
 */
static bool UBTreeMigrateOnePage(Relation rel, BlockNumber victimBlk, BlockNumber targetMaxBlock, bool isOnline,
                                 BlockNumber targetFreeBlk = InvalidBlockNumber,
                                 BlockNumber targetQueueBlk = InvalidBlockNumber,
                                 uint16 targetOffset = 0,
                                 TransactionId safeRecycleXmin = InvalidTransactionId)
{
    /*
     * Step 1: Read victim page momentarily with BT_READ to inspect topology and construct search key.
     * We unlock it immediately so UBTreeSearch can safely descend without self-deadlock.
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

    /* Release read lock on victim page */
    LockBuffer(victimBuf, BUFFER_LOCK_UNLOCK);

    /*
     * Step 2: Allocate target free page below targetMaxBlock.
     * We do this BEFORE acquiring sibling write locks to minimize lock hold duration.
     */
    Buffer newBuf = InvalidBuffer;
    BlockNumber newBlk = InvalidBlockNumber;
    UBTRecycleQueueAddress newAddr;
    newAddr.queueBuf = InvalidBuffer;
    bool fromURQDirect = false;

    if (BlockNumberIsValid(targetFreeBlk) && targetFreeBlk < targetMaxBlock &&
        targetFreeBlk != leftBlk && targetFreeBlk != rightBlk && targetFreeBlk != victimBlk) {
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
            if (blk == leftBlk || blk == rightBlk || blk == victimBlk) {
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
        ReleaseBuffer(victimBuf);
        if (itupKey != NULL) {
            pfree(itupKey);
        }
        if (targetKey != NULL) {
            pfree(targetKey);
        }
        return false;
    }

    /*
     * Step 3: Phase 1 Horizontal Locking (Strictly Left-to-Right).
     * Lock sequence: leftBuf -> victimBuf -> rightBuf.
     * Note: newBuf is already held with BT_WRITE.
     */
    Buffer leftBuf = InvalidBuffer;
    if (leftBlk != P_NONE) {
        leftBuf = ReadBuffer(rel, leftBlk);
        if (isOnline) {
            if (!ConditionalLockBuffer(leftBuf)) {
                ReleaseBuffer(leftBuf);
                _bt_relbuf(rel, newBuf);
                if (newAddr.queueBuf != InvalidBuffer) {
                    ReleaseBuffer(newAddr.queueBuf);
                }
                ReleaseBuffer(victimBuf);
                if (itupKey != NULL) pfree(itupKey);
                if (targetKey != NULL) pfree(targetKey);
                return false;
            }
        } else {
            LockBuffer(leftBuf, BT_WRITE);
        }

        Page leftPage = BufferGetPage(leftBuf);
        UBTPageOpaqueInternal leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        /* Step right if left sibling split concurrently */
        while (P_ISDELETED(leftOpaque) || leftOpaque->btpo_next != victimBlk) {
            if (P_RIGHTMOST(leftOpaque) || leftBlk == leftOpaque->btpo_next) {
                _bt_relbuf(rel, leftBuf);
                _bt_relbuf(rel, newBuf);
                if (newAddr.queueBuf != InvalidBuffer) {
                    ReleaseBuffer(newAddr.queueBuf);
                }
                ReleaseBuffer(victimBuf);
                if (itupKey != NULL) pfree(itupKey);
                if (targetKey != NULL) pfree(targetKey);
                return false;
            }
            BlockNumber nextLeft = leftOpaque->btpo_next;
            _bt_relbuf(rel, leftBuf);
            leftBlk = nextLeft;
            leftBuf = ReadBuffer(rel, leftBlk);
            if (isOnline) {
                if (!ConditionalLockBuffer(leftBuf)) {
                    ReleaseBuffer(leftBuf);
                    _bt_relbuf(rel, newBuf);
                    if (newAddr.queueBuf != InvalidBuffer) {
                        ReleaseBuffer(newAddr.queueBuf);
                    }
                    ReleaseBuffer(victimBuf);
                    if (itupKey != NULL) pfree(itupKey);
                    if (targetKey != NULL) pfree(targetKey);
                    return false;
                }
            } else {
                LockBuffer(leftBuf, BT_WRITE);
            }
            leftPage = BufferGetPage(leftBuf);
            leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        }
    }

    /* Lock victimBuf */
    if (isOnline) {
        if (!ConditionalLockBuffer(victimBuf)) {
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, newBuf);
            if (newAddr.queueBuf != InvalidBuffer) {
                ReleaseBuffer(newAddr.queueBuf);
            }
            ReleaseBuffer(victimBuf);
            if (itupKey != NULL) pfree(itupKey);
            if (targetKey != NULL) pfree(targetKey);
            return false;
        }
    } else {
        LockBuffer(victimBuf, BT_WRITE);
    }

    victimPage = BufferGetPage(victimBuf);
    victimOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(victimPage);
    if (P_ISROOT(victimOpaque) || P_ISDELETED(victimOpaque) || P_ISHALFDEAD(victimOpaque) ||
        victimOpaque->btpo_prev != leftBlk) {
        _bt_relbuf(rel, victimBuf);
        if (BufferIsValid(leftBuf)) {
            _bt_relbuf(rel, leftBuf);
        }
        _bt_relbuf(rel, newBuf);
        if (newAddr.queueBuf != InvalidBuffer) {
            ReleaseBuffer(newAddr.queueBuf);
        }
        if (itupKey != NULL) pfree(itupKey);
        if (targetKey != NULL) pfree(targetKey);
        return false;
    }
    rightBlk = victimOpaque->btpo_next;

    /* Lock rightBuf */
    Buffer rightBuf = InvalidBuffer;
    if (!isRightMost && rightBlk != P_NONE) {
        rightBuf = ReadBuffer(rel, rightBlk);
        if (isOnline) {
            if (!ConditionalLockBuffer(rightBuf)) {
                ReleaseBuffer(rightBuf);
                _bt_relbuf(rel, victimBuf);
                if (BufferIsValid(leftBuf)) {
                    _bt_relbuf(rel, leftBuf);
                }
                _bt_relbuf(rel, newBuf);
                if (newAddr.queueBuf != InvalidBuffer) {
                    ReleaseBuffer(newAddr.queueBuf);
                }
                if (itupKey != NULL) pfree(itupKey);
                if (targetKey != NULL) pfree(targetKey);
                return false;
            }
        } else {
            LockBuffer(rightBuf, BT_WRITE);
        }
        Page rightPage = BufferGetPage(rightBuf);
        UBTPageOpaqueInternal rightOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(rightPage);
        if (rightOpaque->btpo_prev != victimBlk || P_ISDELETED(rightOpaque)) {
            _bt_relbuf(rel, rightBuf);
            _bt_relbuf(rel, victimBuf);
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, newBuf);
            if (newAddr.queueBuf != InvalidBuffer) {
                ReleaseBuffer(newAddr.queueBuf);
            }
            if (itupKey != NULL) pfree(itupKey);
            if (targetKey != NULL) pfree(targetKey);
            return false;
        }
    }

    /*
     * Step 4: Phase 1 Critical Section.
     * Perform page copy, relink horizontal sibling pointers, and stamp Lehman-Yao forwarding link.
     */
    START_CRIT_SECTION();

    Page newPage = BufferGetPage(newBuf);
    UBTreePageInit(newPage, BLCKSZ);
    errno_t cprc = memcpy_s(newPage, BLCKSZ, victimPage, BLCKSZ);
    securec_check(cprc, "\0", "\0");

    UBTPageOpaqueInternal newOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(newPage);
    newOpaque->btpo_prev = leftBlk;
    newOpaque->btpo_next = rightBlk;

    /* Update left sibling */
    if (BufferIsValid(leftBuf)) {
        Page leftPage = BufferGetPage(leftBuf);
        UBTPageOpaqueInternal leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        leftOpaque->btpo_next = newBlk;
        MarkBufferDirty(leftBuf);
    }

    /* Update right sibling */
    if (BufferIsValid(rightBuf)) {
        Page rightPage = BufferGetPage(rightBuf);
        UBTPageOpaqueInternal rightOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(rightPage);
        rightOpaque->btpo_prev = newBlk;
        MarkBufferDirty(rightBuf);
    }

    /*
     * Mark victim page as deleted and point its right-link to newBlk.
     * This forwarding pointer guarantees concurrent in-flight Lehman-Yao scanners follow
     * right-links into newBlk with zero tuple loss.
     */
    victimOpaque->btpo_flags |= BTP_DELETED;
    victimOpaque->btpo_next = newBlk;
    ((UBTPageOpaque)victimOpaque)->xact = ReadNewTransactionId();

    MarkBufferDirty(newBuf);
    MarkBufferDirty(victimBuf);

    if (RelationNeedsWAL(rel)) {
        xl_ubtree2_shrink_move_leaf xlrec;
        XLogRecPtr recptr;

        xlrec.victimBlk = victimBlk;
        xlrec.newBlk = newBlk;
        xlrec.leftBlk = leftBlk;
        xlrec.rightBlk = rightBlk;
        xlrec.isRightMost = isRightMost;

        XLogBeginInsert();
        XLogRegisterData((char *)&xlrec, SizeOfUBTree2ShrinkMoveLeaf);
        XLogRegisterBuffer(0, newBuf, REGBUF_STANDARD);
        XLogRegisterBuffer(1, victimBuf, REGBUF_STANDARD);
        if (BufferIsValid(leftBuf)) {
            XLogRegisterBuffer(2, leftBuf, REGBUF_STANDARD);
        }
        if (BufferIsValid(rightBuf)) {
            XLogRegisterBuffer(3, rightBuf, REGBUF_STANDARD);
        }

        recptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_MOVE_LEAF);

        PageSetLSN(newPage, recptr);
        PageSetLSN(victimPage, recptr);
        if (BufferIsValid(leftBuf)) {
            PageSetLSN(BufferGetPage(leftBuf), recptr);
        }
        if (BufferIsValid(rightBuf)) {
            PageSetLSN(BufferGetPage(rightBuf), recptr);
        }
    }

    END_CRIT_SECTION();

    if (fromURQDirect && BlockNumberIsValid(targetQueueBlk)) {
        Buffer qbuf = ReadRecycleQueueBuffer(rel, targetQueueBlk);
        LockBuffer(qbuf, BT_WRITE);
        RemoveOneItemFromPage(rel, qbuf, targetOffset);
        UnlockReleaseBuffer(qbuf);
    } else if (newAddr.queueBuf != InvalidBuffer) {
        UBTreeRecordUsedPage(rel, newAddr);
        newAddr.queueBuf = InvalidBuffer;
    }

    /* Release all Phase 1 leaf-level locks */
    _bt_relbuf(rel, newBuf);
    if (BufferIsValid(rightBuf)) {
        _bt_relbuf(rel, rightBuf);
    }
    if (BufferIsValid(leftBuf)) {
        _bt_relbuf(rel, leftBuf);
    }
    _bt_relbuf(rel, victimBuf);

    /*
     * Step 5: Phase 2 Bottom-Up Parent Downlink Correction.
     * All horizontal leaf locks are now freed. Search and update parent downlink independently.
     */
    Buffer parentBuf = InvalidBuffer;
    OffsetNumber parentOff = InvalidOffsetNumber;

    if (itupKey != NULL) {
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
    }

    if (!BufferIsValid(parentBuf) || parentOff == InvalidOffsetNumber) {
        if (BufferIsValid(parentBuf)) {
            _bt_relbuf(rel, parentBuf);
            parentBuf = InvalidBuffer;
            parentOff = InvalidOffsetNumber;
        }

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

    if (BufferIsValid(parentBuf)) {
        Page parentPage = BufferGetPage(parentBuf);
        /* Step right on parent level if downlink moved due to concurrent splits */
        while (parentOff > PageGetMaxOffsetNumber(parentPage) ||
               BTreeInnerTupleGetDownLink((IndexTuple)PageGetItem(parentPage, PageGetItemId(parentPage, parentOff))) != victimBlk) {
            bool foundOnPage = false;
            OffsetNumber maxoff = PageGetMaxOffsetNumber(parentPage);
            for (OffsetNumber off = P_FIRSTDATAKEY((UBTPageOpaqueInternal)PageGetSpecialPointer(parentPage));
                 off <= maxoff; off = OffsetNumberNext(off)) {
                IndexTuple itup = (IndexTuple)PageGetItem(parentPage, PageGetItemId(parentPage, off));
                if (BTreeInnerTupleGetDownLink(itup) == victimBlk) {
                    parentOff = off;
                    foundOnPage = true;
                    break;
                }
            }
            if (foundOnPage) {
                break;
            }
            UBTPageOpaqueInternal popaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(parentPage);
            if (P_RIGHTMOST(popaque)) {
                parentOff = InvalidOffsetNumber;
                break;
            }
            BlockNumber nextPBlk = popaque->btpo_next;
            _bt_relbuf(rel, parentBuf);
            parentBuf = _bt_getbuf(rel, nextPBlk, BT_WRITE);
            parentPage = BufferGetPage(parentBuf);
        }

        if (parentOff != InvalidOffsetNumber && BufferIsValid(parentBuf)) {
            START_CRIT_SECTION();
            parentPage = BufferGetPage(parentBuf);
            ItemId pItem = PageGetItemId(parentPage, parentOff);
            IndexTuple pItup = (IndexTuple)PageGetItem(parentPage, pItem);
            UBTreeTupleSetDownLink(pItup, newBlk);
            MarkBufferDirty(parentBuf);

            if (RelationNeedsWAL(rel)) {
                xl_ubtree2_shrink_update_parent pxlrec;
                pxlrec.parentBlk = BufferGetBlockNumber(parentBuf);
                pxlrec.parentOff = parentOff;
                pxlrec.oldChildBlk = victimBlk;
                pxlrec.newChildBlk = newBlk;

                XLogBeginInsert();
                XLogRegisterData((char *)&pxlrec, SizeOfUBTree2ShrinkUpdateParent);
                XLogRegisterBuffer(0, parentBuf, REGBUF_STANDARD);

                XLogRecPtr precptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_UPDATE_PARENT);
                PageSetLSN(parentPage, precptr);
            }
            END_CRIT_SECTION();
            _bt_relbuf(rel, parentBuf);
        } else if (BufferIsValid(parentBuf)) {
            _bt_relbuf(rel, parentBuf);
        }
    }

    if (itupKey != NULL) {
        pfree(itupKey);
    }
    if (targetKey != NULL) {
        pfree(targetKey);
    }

    return true;
}

/*
 * Iterate through high-watermark blocks (between migrateTargetCutoff and totalBlocks)
 * and migrate active pages (leaf or internal) down into free slots below migrateTargetCutoff.
 */
static void UBTreeMigratePages(Relation rel, UBTreeShrinkStats *stats, bool isOnline,
                               TransactionId safeRecycleXmin)
{
    if (stats->migratedBlocks == 0 || stats->migrateTargetCutoff >= stats->totalBlocks) {
        return;
    }

    UBTreeURQInventory inv;
    UBTreeCollectURQFreeBlocks(rel, &inv, safeRecycleXmin);

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
                                     targetFreeBlk, targetQueueBlk, targetOffset, safeRecycleXmin)) {
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

    /* Compute safe transaction horizon locally without mutating session-level global state */
    TransactionId recycleXmin = InvalidTransactionId;
    TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
    TransactionId safeRecycleXmin = TransactionIdIsValid(recycleXmin) ? recycleXmin : oldestXmin;
    if (!TransactionIdIsValid(safeRecycleXmin)) {
        safeRecycleXmin = u_sess->utils_cxt.RecentGlobalDataXmin;
    }

    UBTreeShrinkCheckInternal(rel, stats, maxPages, costRatio, safeRecycleXmin);
    if (stats->totalBlocks <= FirstNormalBlockNumber + 1) {
        return true;
    }

    /* Execute targeted migration if eligible victim blocks were identified */
    int migrationRounds = 0;
    while (stats->migratedBlocks > 0 && migrationRounds < 10) {
        BlockNumber prevFreedTail = stats->freedTailBlocks;
        BlockNumber prevTargetMax = stats->targetMaxBlock;
        BlockNumber victimsInRound = stats->migratedBlocks;

        UBTreeMigratePages(rel, stats, isOnline, safeRecycleXmin);
        migrationRounds++;
        /* Re-evaluate shrink boundaries after migration */
        UBTreeShrinkCheckInternal(rel, stats, maxPages, costRatio, safeRecycleXmin);
        /* If no new tail blocks were freed, stop to prevent looping */
        if (stats->freedTailBlocks <= prevFreedTail && stats->targetMaxBlock >= prevTargetMax) {
            break;
        }
        /* Adaptive diminishing returns: break if gain is less than 20% of migrated victims */
        if (stats->freedTailBlocks > prevFreedTail) {
            BlockNumber gained = stats->freedTailBlocks - prevFreedTail;
            if (victimsInRound > 5 && gained * 5 < victimsInRound) {
                break;
            }
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
        if (RelationNeedsWAL(rel)) {
            xl_ubtree2_urq_purge xlrec;
            xlrec.node = rel->rd_node;
            xlrec.targetMaxBlock = targetMaxBlock;

            XLogBeginInsert();
            XLogRegisterData((char *)&xlrec, SizeOfUBTree2UrqPurge);
            (void)XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_URQ_PURGE);
        }

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
    TransactionId safeRecycleXmin = TransactionIdIsValid(recycleXmin) ? recycleXmin : oldestXmin;
    if (!TransactionIdIsValid(safeRecycleXmin)) {
        safeRecycleXmin = u_sess->utils_cxt.RecentGlobalDataXmin;
    }

    UBTreeShrinkStats stats;
    UBTreeShrinkCheckInternal(rel, &stats, maxPages, costRatio, safeRecycleXmin);

    index_close(rel, AccessShareLock);

    StringInfoData buf;
    initStringInfo(&buf);
    BlockNumber checkTargetMaxBlock = (stats.migratedBlocks > 0) ? stats.migrateTargetCutoff : stats.targetMaxBlock;
    BlockNumber checkFreedTailBlocks = (stats.migratedBlocks > 0) ? (stats.totalBlocks - stats.migrateTargetCutoff) : stats.freedTailBlocks;
    appendStringInfo(&buf, "TotalBlocks: %u, TargetMaxBlock: %u, FreeTailBlocks: %u, MigratedBlocks: %u",
                     stats.totalBlocks, checkTargetMaxBlock, checkFreedTailBlocks, stats.migratedBlocks);

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}
