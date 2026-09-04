/* -------------------------------------------------------------------------
 *
 * ubtshrink.cpp
 *    UBTree Index Physical Shrink and Tail Block Migration Implementation.
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
#include "funcapi.h"
#include "storage/buf/bufmgr.h"
#include "storage/lmgr.h"
#include "storage/smgr/smgr.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/rel_gs.h"

/* Struct for Shrink statistics */
typedef struct UBTreeShrinkStats {
    BlockNumber totalBlocks;
    BlockNumber targetMaxBlock;
    BlockNumber freedTailBlocks;
    BlockNumber migratedBlocks;
    bool success;
} UBTreeShrinkStats;

/*
 * Scan trailing blocks of UBTree index to evaluate shrink feasibility.
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
    stats->success = true;

    if (stats->totalBlocks <= FirstNormalBlockNumber) {
        return;
    }

    /* Target scan down to 50% or first normal block */
    BlockNumber scanLimit = stats->totalBlocks / 2;
    if (scanLimit < FirstNormalBlockNumber) {
        scanLimit = FirstNormalBlockNumber;
    }

    BlockNumber currentBlk = stats->totalBlocks - 1;
    while (currentBlk >= scanLimit) {
        Buffer buf = ReadBuffer(rel, currentBlk);
        LockBuffer(buf, BT_READ);
        Page page = BufferGetPage(buf);
        BTPageOpaque opaque = (BTPageOpaque)PageGetSpecialPointer(page);

        if (P_ISDELETED(opaque) || PageIsEmpty(page)) {
            stats->freedTailBlocks++;
        } else {
            stats->migratedBlocks++;
        }

        LockBuffer(buf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(buf);

        if (currentBlk == 0) {
            break;
        }
        currentBlk--;
    }

    stats->targetMaxBlock = stats->totalBlocks - stats->freedTailBlocks;
}

/*
 * Internal implementation for migrating active tail block to a free head block.
 */
static bool UBTreeMigrateOnePage(Relation rel, BlockNumber oldBlkno, BlockNumber targetMaxBlock)
{
    Buffer oldBuf = ReadBuffer(rel, oldBlkno);
    LockBuffer(oldBuf, BT_WRITE);
    Page oldPage = BufferGetPage(oldBuf);
    BTPageOpaque oldOpaque = (BTPageOpaque)PageGetSpecialPointer(oldPage);

    if (P_ISDELETED(oldOpaque) || PageIsEmpty(oldPage)) {
        LockBuffer(oldBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(oldBuf);
        return true;
    }

    /* Allocate new page from head region (via Recycle Queue) */
    UBTRecycleQueueAddress addr;
    Buffer newBuf = UBTreeGetNewPage(rel, &addr);
    if (!BufferIsValid(newBuf)) {
        LockBuffer(oldBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(oldBuf);
        return false;
    }

    BlockNumber newBlkno = BufferGetBlockNumber(newBuf);
    if (newBlkno >= targetMaxBlock) {
        /* Failed to obtain a page below target max block */
        LockBuffer(newBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(newBuf);
        LockBuffer(oldBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(oldBuf);
        return false;
    }

    Page newPage = BufferGetPage(newBuf);

    /* Copy page content from oldPage to newPage */
    Size pageHeaderSize = SizeOfPageHeaderData;
    Size specialSize = PageGetSpecialSize(oldPage);
    Size copyDataSize = BLCKSZ - pageHeaderSize;
    
    errno_t rc = memcpy_s((char *)newPage + pageHeaderSize, copyDataSize,
                          (char *)oldPage + pageHeaderSize, copyDataSize);
    securec_check(rc, "\0", "\0");

    /* Mark new page valid and old page as deleted */
    MarkBufferDirty(newBuf);
    
    oldOpaque->btpo_flags |= BTP_DELETED;
    MarkBufferDirty(oldBuf);

    /* Write WAL for page migration */
    if (RelationNeedsWAL(rel)) {
        XLogBeginInsert();
        XLogRegisterBuffer(0, newBuf, REGBUF_WILL_INIT);
        XLogRegisterBuffer(1, oldBuf, REGBUF_STANDARD);
        (void)XLogInsert(RM_UBTREE_ID, XLOG_UBTREE_RECYCLE_QUEUE_MODIFY);
    }

    LockBuffer(newBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(newBuf);
    LockBuffer(oldBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(oldBuf);

    return true;
}

/*
 * Primary entry point for UBTree Index Shrink.
 */
bool UBTreeShrink(Relation rel, UBTreeShrinkStats *stats)
{
    if (rel == NULL) {
        return false;
    }

    UBTreeShrinkCheckInternal(rel, stats);
    if (stats->totalBlocks <= FirstNormalBlockNumber || stats->freedTailBlocks == 0) {
        return true;
    }

    BlockNumber targetMaxBlock = stats->targetMaxBlock;

    /* Phase 2: Migrate active tail blocks to head free blocks */
    for (BlockNumber blk = stats->totalBlocks - 1; blk >= targetMaxBlock; blk--) {
        if (!UBTreeMigrateOnePage(rel, blk, targetMaxBlock)) {
            stats->success = false;
            break;
        }
    }

    if (!stats->success) {
        return false;
    }

    /* Phase 3: Physical Truncate under relation extension lock */
    LockRelationForExtension(rel, ExclusiveLock);
    
    BlockNumber currentTotal = RelationGetNumberOfBlocks(rel);
    if (currentTotal > targetMaxBlock) {
        RelationTruncate(rel, targetMaxBlock);
    }

    UnlockRelationForExtension(rel, ExclusiveLock);

    return true;
}

/*
 * SQL callable system function: gs_ubtree_shrink(relname text)
 */
extern "C" Datum gs_ubtree_shrink(PG_FUNCTION_ARGS)
{
    text *relnameText = PG_GETARG_TEXT_P(0);
    RangeVar *relvar = makeRangeVarFromNameList(textToQualifiedNameList(relnameText));
    Oid relid = RangeVarGetRelid(relvar, RowExclusiveLock, false);

    Relation rel = index_open(relid, RowExclusiveLock);

    if (rel->rd_rel->relam != UBTREE_AM_OID) {
        index_close(rel, RowExclusiveLock);
        ereport(ERROR, (errcode(ERRCODE_WRONG_OBJECT_TYPE),
                        errmsg("\"%s\" is not a UBTree index", RelationGetRelationName(rel))));
    }

    UBTreeShrinkStats stats;
    bool result = UBTreeShrink(rel, &stats);

    index_close(rel, RowExclusiveLock);

    PG_RETURN_BOOL(result);
}

/*
 * SQL callable system function: gs_ubtree_shrink_check(relname text)
 */
extern "C" Datum gs_ubtree_shrink_check(PG_FUNCTION_ARGS)
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
