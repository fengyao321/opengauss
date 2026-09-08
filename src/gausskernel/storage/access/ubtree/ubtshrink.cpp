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
    stats->lockEscalationSuccess = true;
    stats->success = true;

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

        bool isDead = (P_ISDELETED(opaque) || PageIsEmpty(page) || PageIsNew(page));

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
 * Primary entry point for UBTree Index Shrink (Phase 3 Online / Phase 1 Offline).
 */
bool UBTreeShrink(Relation rel, UBTreeShrinkStats *stats, bool isOnline)
{
    if (rel == NULL) {
        return false;
    }

    UBTreeShrinkCheckInternal(rel, stats);
    if (stats->totalBlocks <= FirstNormalBlockNumber + 1 || stats->freedTailBlocks == 0) {
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

    UBTreeShrinkStats stats;
    UBTreeShrinkCheckInternal(rel, &stats);

    index_close(rel, AccessShareLock);

    StringInfoData buf;
    initStringInfo(&buf);
    appendStringInfo(&buf, "TotalBlocks: %u, TargetMaxBlock: %u, FreeTailBlocks: %u, MigratedBlocks: %u",
                     stats.totalBlocks, stats.targetMaxBlock, stats.freedTailBlocks, stats.migratedBlocks);

    PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}
