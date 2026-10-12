/* -------------------------------------------------------------------------
 *
 * bridge_router.cpp
 *    openGauss Bridge Router core physical storage engine implementation.
 *
 * Portions Copyright (c) 2026, openGauss Contributors
 *
 * IDENTIFICATION
 *    src/gausskernel/storage/access/index/bridge_router.cpp
 *
 * -------------------------------------------------------------------------
 */

#include "postgres.h"
#include "knl/knl_variable.h"

#include "access/bridge.h"
#include "access/bridge_router_page.h"
#include "access/ustore/knl_utuple.h"
#include "access/ustore/knl_uheap.h"
#include "storage/buf/bufmgr.h"
#include "storage/lmgr.h"
#include "storage/smgr/smgr.h"
#include "utils/rel.h"

/*
 * Binary search within a leaf page for the matching BridgeSeqNo
 */
static int BridgeRouterSearchLeaf(BridgeLeafEntry *entries, uint16 count, BridgeSeqNo seq)
{
    int low = 0;
    int high = (int)count - 1;

    while (low <= high) {
        int mid = low + ((high - low) / 2);
        if (entries[mid].seq == seq) {
            return mid;
        } else if (entries[mid].seq < seq) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return -1;
}

/*
 * Binary search within an internal page for the child block pointer
 */
static BlockNumber BridgeRouterSearchInternal(BridgeInternalEntry *entries, uint16 count, BridgeSeqNo seq)
{
    if (count == 0) {
        return InvalidBlockNumber;
    }

    int low = 0;
    int high = (int)count - 1;
    int bestMid = 0;

    while (low <= high) {
        int mid = low + ((high - low) / 2);
        if (entries[mid].child_min_seq <= seq) {
            bestMid = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    return entries[bestMid].child_blkno;
}

/*
 * Lookup a virtual BridgeSeqNo in the Bridge Router B+ Tree
 */
bool BridgeRouterLookup(Relation routerRel, BridgeSeqNo seq, ItemPointer physicalTid)
{
    if (routerRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }

    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks <= BRIDGE_ROUTER_METAPAGE_BLKNO) {
        return false;
    }

    /* 1. Read Metapage */
    Buffer metaBuf = ReadBuffer(routerRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
    LockBuffer(metaBuf, BUFFER_LOCK_SHARE);
    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);
    
    if (meta->magic != BRIDGE_ROUTER_MAGIC || meta->total_entries == 0) {
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);
        return false;
    }

    BlockNumber currBlk = meta->root_blkno;
    uint16 height = meta->tree_height;
    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);

    if (currBlk == InvalidBlockNumber || currBlk >= nblocks) {
        return false;
    }

    /* 2. Traverse internal levels down to leaf */
    for (uint16 level = height; level > 1; level--) {
        Buffer intBuf = ReadBuffer(routerRel, currBlk);
        LockBuffer(intBuf, BUFFER_LOCK_SHARE);
        Page page = BufferGetPage(intBuf);
        BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

        BridgeInternalEntry *entries = (BridgeInternalEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
        BlockNumber childBlk = BridgeRouterSearchInternal(entries, hdr->pd_item_count, seq);

        LockBuffer(intBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(intBuf);

        if (childBlk == InvalidBlockNumber) {
            return false;
        }
        currBlk = childBlk;
    }

    /* 3. Search target leaf page */
    Buffer leafBuf = ReadBuffer(routerRel, currBlk);
    LockBuffer(leafBuf, BUFFER_LOCK_SHARE);
    Page page = BufferGetPage(leafBuf);
    BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

    BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
    int idx = BridgeRouterSearchLeaf(entries, hdr->pd_item_count, seq);

    bool found = false;
    if (idx >= 0) {
        *physicalTid = entries[idx].tid;
        found = true;
    }

    LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(leafBuf);
    return found;
}

/*
 * Append an entry (seq -> physicalTid) to the rightmost leaf of the Bridge Router
 */
bool BridgeRouterAppend(Relation routerRel, BridgeSeqNo seq, ItemPointer physicalTid)
{
    if (routerRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }

    /* Read Metapage */
    Buffer metaBuf = ReadBuffer(routerRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
    LockBuffer(metaBuf, BUFFER_LOCK_EXCLUSIVE);
    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);

    BlockNumber rightmostBlk = meta->rightmost_leaf_blkno;
    Buffer leafBuf = ReadBuffer(routerRel, rightmostBlk);
    LockBuffer(leafBuf, BUFFER_LOCK_EXCLUSIVE);
    Page page = BufferGetPage(leafBuf);
    BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

    /* Check if rightmost leaf page is full */
    if (hdr->pd_item_count >= BRIDGE_ROUTER_MAX_LEAF_ENTRIES) {
        /* 100% compact right split: allocate new leaf page */
        Buffer newLeafBuf = ReadBuffer(routerRel, P_NEW);
        LockBuffer(newLeafBuf, BUFFER_LOCK_EXCLUSIVE);
        Page newPage = BufferGetPage(newLeafBuf);

        BridgeRouterPageHeader newHdr = (BridgeRouterPageHeader)newPage;
        errno_t rc = memset_s(newHdr, BLCKSZ, 0, SizeOfBridgeRouterPageHeaderData);
        securec_check(rc, "\0", "\0");
        newHdr->pd_flags = BRIDGE_PAGE_LEAF | BRIDGE_PAGE_RIGHTMOST;
        newHdr->pd_level = 0;
        newHdr->pd_prev_blk = rightmostBlk;
        newHdr->pd_next_blk = InvalidBlockNumber;
        newHdr->pd_item_count = 1;
        newHdr->pd_high_seq = seq;

        BridgeLeafEntry *newEntries = (BridgeLeafEntry *)((char *)newPage + SizeOfBridgeRouterPageHeaderData);
        newEntries[0].seq = seq;
        newEntries[0].tid = *physicalTid;

        /* Update old leaf page link */
        hdr->pd_flags &= ~BRIDGE_PAGE_RIGHTMOST;
        hdr->pd_next_blk = BufferGetBlockNumber(newLeafBuf);
        MarkBufferDirty(leafBuf);
        LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(leafBuf);

        /* Update metapage */
        meta->rightmost_leaf_blkno = BufferGetBlockNumber(newLeafBuf);
        meta->total_entries++;
        meta->max_seq = seq;
        MarkBufferDirty(metaBuf);
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);

        MarkBufferDirty(newLeafBuf);
        LockBuffer(newLeafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(newLeafBuf);
        return true;
    }

    /* Append directly to current rightmost leaf */
    BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
    entries[hdr->pd_item_count].seq = seq;
    entries[hdr->pd_item_count].tid = *physicalTid;
    hdr->pd_item_count++;
    hdr->pd_high_seq = seq;

    meta->total_entries++;
    meta->max_seq = seq;
    MarkBufferDirty(metaBuf);
    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);

    MarkBufferDirty(leafBuf);
    LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(leafBuf);
    return true;
}

/*
 * Anti-phantom verification gate:
 * Validates that the tuple retrieved from UHeap matches the exact birth sequence of the query.
 * If the physical slot was rapidly reused for an unrelated row, the tag check detects the discrepancy
 * and discards the ghost match immediately.
 */
bool BridgeVerifyTupleTag(void* tuple, BridgeSeqNo querySeq)
{
    if (tuple == NULL || querySeq == BRIDGE_INVALID_SEQ) {
        return false;
    }

    UHeapTuple utup = (UHeapTuple)tuple;
    if (utup->disk_tuple == NULL) {
        return false;
    }

    if (UHeapDiskTupleHasBridgeTag(utup->disk_tuple)) {
        uint64 tag = UHeapDiskTupleGetBridgeTag(utup->disk_tuple);
        return (tag == querySeq);
    }

    /* If row does not have tag, accept by default */
    return true;
}
