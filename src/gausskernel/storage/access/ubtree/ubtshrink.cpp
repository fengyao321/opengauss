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

/*
 * Scan backwards from trailing blocks of UBTree index to evaluate shrink feasibility.
 */
void UBTreeShrinkCheckInternal(Relation rel, UBTreeShrinkStats *stats)
{
    if (stats == NULL || rel == NULL) {
        return;
    }

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

        LockBuffer(buf, BUFFER_LOCK_UNLOCK);
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
     * isolated active leaf pages from high-watermark blocks to free slots in low-watermark blocks.
     * We use a two-pointer compaction strategy:
     * - highScan starts at targetMaxBlock - 1 moving backward, identifying active leaf victim pages.
     * - lowScan starts at FirstNormalBlockNumber + 1 moving forward, identifying dead/empty slots.
     * When highScan encounters dead pages or lowScan finds free slots, we track the compaction cutoff
     * point where all victims above cutoff can be accommodated by free slots below cutoff.
     */
    if (stats->targetMaxBlock > FirstNormalBlockNumber + 2) {
        BlockNumber highScan = stats->targetMaxBlock - 1;
        BlockNumber lowScan = FirstNormalBlockNumber + 1;
        BlockNumber victimsCount = 0;
        BlockNumber freeSlotsCount = 0;

        BlockNumber bestCutoff = stats->targetMaxBlock;
        BlockNumber bestVictims = 0;
        BlockNumber bestFreed = stats->freedTailBlocks;

        while (highScan > lowScan && victimsCount < UBTREE_SHRINK_MAX_MIGRATE_DEFAULT) {
            Buffer hBuf = ReadBuffer(rel, highScan);
            LockBuffer(hBuf, BT_READ);
            Page hPage = BufferGetPage(hBuf);
            UBTPageOpaqueInternal hOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(hPage);

            bool hDead = (PageIsNew(hPage) || P_ISDELETED(hOpaque));
            bool hLeaf = P_ISLEAF(hOpaque);
            bool hRoot = P_ISROOT(hOpaque);

            LockBuffer(hBuf, BUFFER_LOCK_UNLOCK);
            ReleaseBuffer(hBuf);

            if (hDead) {
                /*
                 * High pointer found a dead page.
                 * If we have victims and enough free slots, consider highScan as part of the truncation area.
                 */
                if (victimsCount > 0 && freeSlotsCount >= victimsCount) {
                    BlockNumber tentativeCutoff = highScan;
                    if (tentativeCutoff >= lowScan) {
                        BlockNumber tentativeFreed = stats->totalBlocks - tentativeCutoff;
                        if (tentativeFreed > bestFreed) {
                            double ratio = (double)victimsCount / (double)tentativeFreed;
                            if (ratio <= UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT) {
                                bestVictims = victimsCount;
                                bestCutoff = tentativeCutoff;
                                bestFreed = tentativeFreed;
                            }
                        }
                    }
                }
            } else if (hLeaf && !hRoot) {
                victimsCount++;

                /* Advance lowScan to find at least victimsCount free slots */
                while (lowScan < highScan && freeSlotsCount < victimsCount) {
                    Buffer lBuf = ReadBuffer(rel, lowScan);
                    LockBuffer(lBuf, BT_READ);
                    Page lPage = BufferGetPage(lBuf);
                    UBTPageOpaqueInternal lOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(lPage);

                    bool lDead = (PageIsNew(lPage) || P_ISDELETED(lOpaque));

                    LockBuffer(lBuf, BUFFER_LOCK_UNLOCK);
                    ReleaseBuffer(lBuf);

                    if (lDead) {
                        freeSlotsCount++;
                    }
                    lowScan++;
                }

                /* If we found enough free slots below highScan, evaluate shrink ratio */
                if (freeSlotsCount >= victimsCount) {
                    BlockNumber tentativeCutoff = highScan;
                    if (tentativeCutoff >= lowScan) {
                        BlockNumber tentativeFreed = stats->totalBlocks - tentativeCutoff;
                        if (tentativeFreed > bestFreed) {
                            double ratio = (double)victimsCount / (double)tentativeFreed;
                            if (ratio <= UBTREE_SHRINK_RATIO_THRESHOLD_DEFAULT) {
                                bestVictims = victimsCount;
                                bestCutoff = tentativeCutoff;
                                bestFreed = tentativeFreed;
                            }
                        }
                    }
                } else {
                    /* Not enough free slots available below highScan */
                    break;
                }
            } else {
                /* Non-leaf internal page or root page encountered, cannot migrate across it */
                break;
            }

            highScan--;
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
 * Migrate one active leaf page from victimBlk to a newly allocated free page below targetMaxBlock.
 * Locks coupling:
 * 1. victimBuf (BT_WRITE)
 * 2. leftBuf (BT_WRITE)
 * 3. rightBuf (BT_WRITE)
 * 4. parentBuf (BT_WRITE via UBTreeSearch/UBTreeGetStackBuf)
 */
static bool UBTreeMigrateOneLeafPage(Relation rel, BlockNumber victimBlk, BlockNumber targetMaxBlock)
{
    /* Refresh transaction horizon for URQ page recycling */
    TransactionId recycleXmin = InvalidTransactionId;
    TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
    if (TransactionIdIsValid(recycleXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = recycleXmin;
    } else if (TransactionIdIsValid(oldestXmin)) {
        u_sess->utils_cxt.RecentGlobalDataXmin = oldestXmin;
    }

    Buffer victimBuf = _bt_getbuf(rel, victimBlk, BT_WRITE);
    Page victimPage = BufferGetPage(victimBuf);
    UBTPageOpaqueInternal victimOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(victimPage);

    /* Verify victim page is still an active, non-root leaf page */
    if (!P_ISLEAF(victimOpaque) || P_ISROOT(victimOpaque) ||
        P_ISDELETED(victimOpaque) || P_ISHALFDEAD(victimOpaque) || P_INCOMPLETE_SPLIT(victimOpaque)) {
        _bt_relbuf(rel, victimBuf);
        return false;
    }

    bool isRightMost = P_RIGHTMOST(victimOpaque);
    BlockNumber leftBlk = victimOpaque->btpo_prev;
    BlockNumber rightBlk = victimOpaque->btpo_next;

    /* Lock left sibling if exists */
    Buffer leftBuf = InvalidBuffer;
    if (leftBlk != P_NONE) {
        leftBuf = ReadBuffer(rel, leftBlk);
        if (!ConditionalLockBuffer(leftBuf)) {
            ReleaseBuffer(leftBuf);
            leftBuf = InvalidBuffer;
            _bt_relbuf(rel, victimBuf);
            return false;
        }
        Page leftPage = BufferGetPage(leftBuf);
        UBTPageOpaqueInternal leftOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(leftPage);
        if (leftOpaque->btpo_next != victimBlk || P_ISDELETED(leftOpaque)) {
            _bt_relbuf(rel, leftBuf);
            _bt_relbuf(rel, victimBuf);
            return false;
        }
    }

    /* Lock right sibling if exists (non-rightmost) */
    Buffer rightBuf = InvalidBuffer;
    if (!isRightMost && rightBlk != P_NONE) {
        rightBuf = ReadBuffer(rel, rightBlk);
        if (!ConditionalLockBuffer(rightBuf)) {
            ReleaseBuffer(rightBuf);
            rightBuf = InvalidBuffer;
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, victimBuf);
            return false;
        }
        Page rightPage = BufferGetPage(rightBuf);
        UBTPageOpaqueInternal rightOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(rightPage);
        if (rightOpaque->btpo_prev != victimBlk || P_ISDELETED(rightOpaque)) {
            _bt_relbuf(rel, rightBuf);
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, victimBuf);
            return false;
        }
    }

    /* Allocate free page below targetMaxBlock: first check URQ, then scan for dead pages below targetMaxBlock */
    Buffer newBuf = InvalidBuffer;
    BlockNumber newBlk = InvalidBlockNumber;
    UBTRecycleQueueAddress newAddr;
    newAddr.queueBuf = InvalidBuffer;

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
        /* Above target watermark, release and try next */
        if (addr.queueBuf != InvalidBuffer) {
            ReleaseBuffer(addr.queueBuf);
        }
        _bt_relbuf(rel, newBuf);
        newBuf = InvalidBuffer;
    }

    /*
     * If URQ did not return a page below targetMaxBlock, directly find a recyclable dead/empty
     * page below targetMaxBlock.
     */
    if (newBuf == InvalidBuffer || newBlk >= targetMaxBlock) {
        for (BlockNumber blk = FirstNormalBlockNumber + 1; blk < targetMaxBlock; blk++) {
            if (blk == leftBlk || blk == rightBlk || blk == victimBlk) {
                continue;
            }
            Buffer testBuf = ReadBuffer(rel, blk);
            if (ConditionalLockBuffer(testBuf)) {
                Page testPage = BufferGetPage(testBuf);
                UBTPageOpaqueInternal testOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(testPage);
                if (PageIsNew(testPage) || (P_ISDELETED(testOpaque) && UBTreePageRecyclable(testPage))) {
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
        return false;
    }

    /* Find parent downlink */
    IndexTuple targetKey = NULL;
    BTScanInsert itupKey = NULL;

    if (!isRightMost) {
        ItemId hikeyItem = PageGetItemId(victimPage, P_HIKEY);
        targetKey = CopyIndexTuple((IndexTuple)PageGetItem(victimPage, hikeyItem));
        itupKey = UBTreeMakeScanKey(rel, targetKey);
        itupKey->pivotsearch = true;
    } else {
        OffsetNumber maxoff = PageGetMaxOffsetNumber(victimPage);
        if (maxoff >= 1) {
            ItemId item = PageGetItemId(victimPage, 1);
            targetKey = CopyIndexTuple((IndexTuple)PageGetItem(victimPage, item));
            itupKey = UBTreeMakeScanKey(rel, targetKey);
            itupKey->pivotsearch = false;
        } else if (BufferIsValid(leftBuf) && PageGetMaxOffsetNumber(BufferGetPage(leftBuf)) >= P_HIKEY) {
            Page leftPage = BufferGetPage(leftBuf);
            ItemId leftHiKeyItem = PageGetItemId(leftPage, P_HIKEY);
            targetKey = CopyIndexTuple((IndexTuple)PageGetItem(leftPage, leftHiKeyItem));
            itupKey = UBTreeMakeScanKey(rel, targetKey);
            itupKey->pivotsearch = true;
        } else {
            /* Cannot construct search key for rightmost empty page with no left sibling */
            if (newAddr.queueBuf != InvalidBuffer) {
                ReleaseBuffer(newAddr.queueBuf);
            }
            if (BufferIsValid(rightBuf)) {
                _bt_relbuf(rel, rightBuf);
            }
            if (BufferIsValid(leftBuf)) {
                _bt_relbuf(rel, leftBuf);
            }
            _bt_relbuf(rel, newBuf);
            _bt_relbuf(rel, victimBuf);
            return false;
        }
    }

    Buffer leafSearchBuf = InvalidBuffer;
    BTStack stack = UBTreeSearch(rel, itupKey, &leafSearchBuf, BT_READ);
    if (BufferIsValid(leafSearchBuf)) {
        _bt_relbuf(rel, leafSearchBuf);
    }

    Buffer parentBuf = InvalidBuffer;
    OffsetNumber parentOff = InvalidOffsetNumber;
    if (stack != NULL) {
        stack->bts_btentry = victimBlk;
        parentBuf = UBTreeGetStackBuf(rel, stack);
        if (BufferIsValid(parentBuf)) {
            parentOff = stack->bts_offset;
        }
    }

    if (stack != NULL) {
        _bt_freestack(stack);
        stack = NULL;
    }
    if (itupKey != NULL) {
        pfree(itupKey);
        itupKey = NULL;
    }
    if (targetKey != NULL) {
        pfree(targetKey);
        targetKey = NULL;
    }

    if (!BufferIsValid(parentBuf) || parentOff == InvalidOffsetNumber) {
        /* Could not re-find parent buffer cleanly; abort migration of this block */
        if (newAddr.queueBuf != InvalidBuffer) {
            ReleaseBuffer(newAddr.queueBuf);
        }
        if (BufferIsValid(parentBuf)) {
            _bt_relbuf(rel, parentBuf);
        }
        _bt_relbuf(rel, newBuf);
        if (BufferIsValid(rightBuf)) {
            _bt_relbuf(rel, rightBuf);
        }
        if (BufferIsValid(leftBuf)) {
            _bt_relbuf(rel, leftBuf);
        }
        _bt_relbuf(rel, victimBuf);
        return false;
    }

    /*
     * Begin atomic migration critical section:
     * 1. Copy page data from victimPage to newPage, updating links
     * 2. Point leftBuf->btpo_next = newBlk
     * 3. Point rightBuf->btpo_prev = newBlk (if exists)
     * 4. Point parent downlink to newBlk
     * 5. Mark victimPage as BTP_DELETED
     * 6. Atomic WAL insertion under RM_UBTREE2_ID
     */
    START_CRIT_SECTION();

    Page newPage = BufferGetPage(newBuf);
    errno_t rc = memcpy_s(newPage, BLCKSZ, victimPage, BLCKSZ);
    securec_check(rc, "", "");
    UBTPageOpaqueInternal newOpaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(newPage);
    newOpaque->btpo_prev = leftBlk;
    newOpaque->btpo_next = rightBlk;

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
    Page parentPage = BufferGetPage(parentBuf);
    ItemId pItem = PageGetItemId(parentPage, parentOff);
    IndexTuple pItup = (IndexTuple)PageGetItem(parentPage, pItem);
    UBTreeTupleSetDownLink(pItup, newBlk);
    MarkBufferDirty(parentBuf);

    /* Mark victimPage deleted */
    victimOpaque->btpo_flags &= ~BTP_HALF_DEAD;
    victimOpaque->btpo_flags |= BTP_DELETED;
    ((UBTPageOpaque)victimOpaque)->xact = ReadNewTransactionId();

    MarkBufferDirty(newBuf);
    MarkBufferDirty(victimBuf);

    /* Emit atomic WAL for moving leaf page */
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
        XLogRegisterBuffer(0, newBuf, REGBUF_WILL_INIT);
        XLogRegisterBufData(0, (char *)newPage, BLCKSZ);
        XLogRegisterBuffer(1, victimBuf, REGBUF_STANDARD);
        if (BufferIsValid(leftBuf)) {
            XLogRegisterBuffer(2, leftBuf, REGBUF_STANDARD);
        }
        if (BufferIsValid(rightBuf)) {
            XLogRegisterBuffer(3, rightBuf, REGBUF_STANDARD);
        }
        XLogRegisterBuffer(4, parentBuf, REGBUF_STANDARD);

        recptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_MOVE_LEAF);

        PageSetLSN(victimPage, recptr);
        PageSetLSN(newPage, recptr);
        if (BufferIsValid(leftBuf)) {
            PageSetLSN(BufferGetPage(leftBuf), recptr);
        }
        if (BufferIsValid(rightBuf)) {
            PageSetLSN(BufferGetPage(rightBuf), recptr);
        }
        PageSetLSN(parentPage, recptr);
    }

    END_CRIT_SECTION();

    /* Discard allocated slot from Recycle Queue */
    if (newAddr.queueBuf != InvalidBuffer) {
        UBTreeRecordUsedPage(rel, newAddr);
    }

    /* Release acquired buffers */
    _bt_relbuf(rel, parentBuf);
    _bt_relbuf(rel, newBuf);
    if (BufferIsValid(rightBuf)) {
        _bt_relbuf(rel, rightBuf);
    }
    if (BufferIsValid(leftBuf)) {
        _bt_relbuf(rel, leftBuf);
    }
    _bt_relbuf(rel, victimBuf);

    return true;
}

/*
 * Iterate through high-watermark blocks (between migrateTargetCutoff and totalBlocks)
 * and migrate active leaf pages down into URQ free slots below migrateTargetCutoff.
 */
static void UBTreeMigratePages(Relation rel, UBTreeShrinkStats *stats)
{
    if (stats->migratedBlocks == 0 || stats->migrateTargetCutoff >= stats->totalBlocks) {
        return;
    }

    BlockNumber currentBlk = stats->totalBlocks - 1;
    BlockNumber migratedCount = 0;

    while (currentBlk >= stats->migrateTargetCutoff && migratedCount < stats->migratedBlocks) {
        Buffer buf = ReadBuffer(rel, currentBlk);
        LockBuffer(buf, BT_READ);
        Page page = BufferGetPage(buf);
        UBTPageOpaqueInternal opaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(page);

        bool isDead = (PageIsNew(page) || P_ISDELETED(opaque));
        bool isLeaf = P_ISLEAF(opaque);
        bool isRoot = P_ISROOT(opaque);

        LockBuffer(buf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(buf);

        if (!isDead && isLeaf && !isRoot) {
            if (UBTreeMigrateOneLeafPage(rel, currentBlk, stats->migrateTargetCutoff)) {
                migratedCount++;
            }
        }

        if (currentBlk == 0) {
            break;
        }
        currentBlk--;
    }

    stats->migratedBlocks = migratedCount;
}

/*
 * Primary entry point for UBTree Index Shrink (Phase 3 Online / Phase 1 Offline).
 */
bool UBTreeShrink(Relation rel, UBTreeShrinkStats *stats, bool isOnline)
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

    UBTreeShrinkCheckInternal(rel, stats);
    if (stats->totalBlocks <= FirstNormalBlockNumber + 1) {
        return true;
    }

    /* Execute targeted migration if eligible victim blocks were identified */
    if (stats->migratedBlocks > 0) {
        UBTreeMigratePages(rel, stats);
        /* Re-evaluate shrink boundaries after migration */
        UBTreeShrinkCheckInternal(rel, stats);
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
    if (PG_NARGS() > 1 && !PG_ARGISNULL(1)) {
        isOnline = PG_GETARG_BOOL(1);
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
    bool result = UBTreeShrink(rel, &stats, isOnline);

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



    UBTreeShrinkStats stats;
    UBTreeShrinkCheckInternal(rel, &stats);

    index_close(rel, AccessShareLock);

    StringInfoData buf;
    initStringInfo(&buf);
    BlockNumber checkTargetMaxBlock = (stats.migratedBlocks > 0) ? stats.migrateTargetCutoff : stats.targetMaxBlock;
    BlockNumber checkFreedTailBlocks = (stats.migratedBlocks > 0) ? (stats.totalBlocks - stats.migrateTargetCutoff) : stats.freedTailBlocks;
    appendStringInfo(&buf, "TotalBlocks: %u, TargetMaxBlock: %u, FreeTailBlocks: %u, MigratedBlocks: %u",
                     stats.totalBlocks, checkTargetMaxBlock, checkFreedTailBlocks, stats.migratedBlocks);

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}
