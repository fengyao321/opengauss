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

#define BRIDGE_ROUTER_MAX_LEVELS 8

/*
 * Initialize physical page 0 (Metapage) and page 1 (Initial leaf page)
 * for a new Bridge Router relation.
 */
void BridgeRouterInit(Relation routerRel)
{
    /* 1. Allocate Metapage (Block 0) */
    Buffer metaBuf = ReadBuffer(routerRel, P_NEW);
    LockBuffer(metaBuf, BUFFER_LOCK_EXCLUSIVE);
    Page metaPage = BufferGetPage(metaBuf);
    errno_t rc = memset_s(metaPage, BLCKSZ, 0, BLCKSZ);
    securec_check(rc, "\0", "\0");

    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)metaPage;
    meta->magic = BRIDGE_ROUTER_MAGIC;
    meta->version = BRIDGE_ROUTER_VERSION;
    meta->root_blkno = BRIDGE_ROUTER_FIRST_LEAF_BLKNO;
    meta->leftmost_leaf_blkno = BRIDGE_ROUTER_FIRST_LEAF_BLKNO;
    meta->rightmost_leaf_blkno = BRIDGE_ROUTER_FIRST_LEAF_BLKNO;
    meta->tree_height = 1;
    meta->reserved = 0;
    meta->total_entries = 0;
    meta->max_seq = 0;

    MarkBufferDirty(metaBuf);

    /* 2. Allocate First Leaf Page (Block 1) */
    Buffer leafBuf = ReadBuffer(routerRel, P_NEW);
    LockBuffer(leafBuf, BUFFER_LOCK_EXCLUSIVE);
    Page leafPage = BufferGetPage(leafBuf);
    rc = memset_s(leafPage, BLCKSZ, 0, BLCKSZ);
    securec_check(rc, "\0", "\0");

    BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)leafPage;
    hdr->pd_flags = BRIDGE_PAGE_LEAF | BRIDGE_PAGE_RIGHTMOST;
    hdr->pd_level = 0;
    hdr->pd_prev_blk = InvalidBlockNumber;
    hdr->pd_next_blk = InvalidBlockNumber;
    hdr->pd_item_count = 0;
    hdr->pd_high_seq = 0;

    MarkBufferDirty(leafBuf);

    LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(leafBuf);

    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);
}

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
    
    if (meta->magic != BRIDGE_ROUTER_MAGIC || meta->total_entries == 0 || seq > meta->max_seq) {
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

        if (childBlk == InvalidBlockNumber || childBlk >= nblocks) {
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
 * Insert a child routing pointer into the internal node hierarchy of the Bridge Router B+ Tree.
 * Called when a leaf page has split. Handles right splits of internal pages and root growth.
 */
static void BridgeRouterInsertInternal(Relation routerRel, BridgeRouterMetaPage meta,
                                       BlockNumber leftChildBlk, BlockNumber rightChildBlk,
                                       uint64 childMinSeq)
{
    /* Case 1: Tree height was 1 (root was a leaf). Allocate new internal root (level 1). */
    if (meta->tree_height == 1) {
        Buffer newRootBuf = ReadBuffer(routerRel, P_NEW);
        LockBuffer(newRootBuf, BUFFER_LOCK_EXCLUSIVE);
        Page newRootPage = BufferGetPage(newRootBuf);
        BlockNumber newRootBlk = BufferGetBlockNumber(newRootBuf);

        errno_t rc = memset_s(newRootPage, BLCKSZ, 0, BLCKSZ);
        securec_check(rc, "\0", "\0");

        BridgeRouterPageHeader rootHdr = (BridgeRouterPageHeader)newRootPage;
        rootHdr->pd_flags = BRIDGE_PAGE_INTERNAL | BRIDGE_PAGE_RIGHTMOST;
        rootHdr->pd_level = 1;
        rootHdr->pd_prev_blk = InvalidBlockNumber;
        rootHdr->pd_next_blk = InvalidBlockNumber;
        rootHdr->pd_item_count = 2;
        rootHdr->pd_high_seq = childMinSeq;

        BridgeInternalEntry *entries = (BridgeInternalEntry *)((char *)newRootPage + SizeOfBridgeRouterPageHeaderData);
        entries[0].child_min_seq = 1;
        entries[0].child_blkno = leftChildBlk;
        entries[1].child_min_seq = childMinSeq;
        entries[1].child_blkno = rightChildBlk;

        MarkBufferDirty(newRootBuf);
        LockBuffer(newRootBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(newRootBuf);

        meta->root_blkno = newRootBlk;
        meta->tree_height = 2;
        return;
    }

    /*
     * Case 2: Tree height >= 2. Root is already an internal page.
     * Traverse down to find the rightmost internal node at each level.
     */
    BlockNumber rightmostPath[BRIDGE_ROUTER_MAX_LEVELS];
    uint16 height = meta->tree_height;
    BlockNumber currBlk = meta->root_blkno;

    for (uint16 level = height; level > 1; level--) {
        rightmostPath[level - 1] = currBlk;
        if (level > 2) {
            Buffer intBuf = ReadBuffer(routerRel, currBlk);
            LockBuffer(intBuf, BUFFER_LOCK_SHARE);
            Page page = BufferGetPage(intBuf);
            BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;
            BridgeInternalEntry *entries = (BridgeInternalEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
            BlockNumber lastChild = entries[hdr->pd_item_count - 1].child_blkno;
            LockBuffer(intBuf, BUFFER_LOCK_UNLOCK);
            ReleaseBuffer(intBuf);
            currBlk = lastChild;
        }
    }

    /* Insert (targetMinSeq, targetChildBlk) into level 1, propagating upward if splits occur */
    BlockNumber targetChildBlk = rightChildBlk;
    uint64 targetMinSeq = childMinSeq;

    for (uint16 curLevel = 1; curLevel < height; curLevel++) {
        BlockNumber parentBlk = rightmostPath[curLevel];
        Buffer parentBuf = ReadBuffer(routerRel, parentBlk);
        LockBuffer(parentBuf, BUFFER_LOCK_EXCLUSIVE);
        Page parentPage = BufferGetPage(parentBuf);
        BridgeRouterPageHeader parentHdr = (BridgeRouterPageHeader)parentPage;
        BridgeInternalEntry *entries = (BridgeInternalEntry *)((char *)parentPage + SizeOfBridgeRouterPageHeaderData);

        if (parentHdr->pd_item_count < BRIDGE_ROUTER_MAX_INTERNAL_ENTRIES) {
            /* Parent has room: append entry */
            entries[parentHdr->pd_item_count].child_min_seq = targetMinSeq;
            entries[parentHdr->pd_item_count].child_blkno = targetChildBlk;
            parentHdr->pd_item_count++;
            parentHdr->pd_high_seq = targetMinSeq;

            MarkBufferDirty(parentBuf);
            LockBuffer(parentBuf, BUFFER_LOCK_UNLOCK);
            ReleaseBuffer(parentBuf);
            return;
        }

        /*
         * Parent is full: right split at this internal level!
         */
        Buffer newIntBuf = ReadBuffer(routerRel, P_NEW);
        LockBuffer(newIntBuf, BUFFER_LOCK_EXCLUSIVE);
        Page newIntPage = BufferGetPage(newIntBuf);
        BlockNumber newIntBlk = BufferGetBlockNumber(newIntBuf);

        errno_t rc = memset_s(newIntPage, BLCKSZ, 0, BLCKSZ);
        securec_check(rc, "\0", "\0");

        BridgeRouterPageHeader newIntHdr = (BridgeRouterPageHeader)newIntPage;
        newIntHdr->pd_flags = BRIDGE_PAGE_INTERNAL | BRIDGE_PAGE_RIGHTMOST;
        newIntHdr->pd_level = curLevel;
        newIntHdr->pd_prev_blk = parentBlk;
        newIntHdr->pd_next_blk = InvalidBlockNumber;
        newIntHdr->pd_item_count = 1;
        newIntHdr->pd_high_seq = targetMinSeq;

        BridgeInternalEntry *newEntries = (BridgeInternalEntry *)((char *)newIntPage + SizeOfBridgeRouterPageHeaderData);
        newEntries[0].child_min_seq = targetMinSeq;
        newEntries[0].child_blkno = targetChildBlk;

        parentHdr->pd_flags &= ~BRIDGE_PAGE_RIGHTMOST;
        parentHdr->pd_next_blk = newIntBlk;

        MarkBufferDirty(parentBuf);
        LockBuffer(parentBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(parentBuf);

        MarkBufferDirty(newIntBuf);
        LockBuffer(newIntBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(newIntBuf);

        targetChildBlk = newIntBlk;
    }

    /* All internal levels up to root were split! Allocate new root */
    Buffer newRootBuf = ReadBuffer(routerRel, P_NEW);
    LockBuffer(newRootBuf, BUFFER_LOCK_EXCLUSIVE);
    Page newRootPage = BufferGetPage(newRootBuf);
    BlockNumber newRootBlk = BufferGetBlockNumber(newRootBuf);

    errno_t rc = memset_s(newRootPage, BLCKSZ, 0, BLCKSZ);
    securec_check(rc, "\0", "\0");

    BridgeRouterPageHeader rootHdr = (BridgeRouterPageHeader)newRootPage;
    rootHdr->pd_flags = BRIDGE_PAGE_INTERNAL | BRIDGE_PAGE_RIGHTMOST;
    rootHdr->pd_level = height;
    rootHdr->pd_prev_blk = InvalidBlockNumber;
    rootHdr->pd_next_blk = InvalidBlockNumber;
    rootHdr->pd_item_count = 2;
    rootHdr->pd_high_seq = targetMinSeq;

    BridgeInternalEntry *rootEntries = (BridgeInternalEntry *)((char *)newRootPage + SizeOfBridgeRouterPageHeaderData);
    rootEntries[0].child_min_seq = 1;
    rootEntries[0].child_blkno = meta->root_blkno;
    rootEntries[1].child_min_seq = targetMinSeq;
    rootEntries[1].child_blkno = targetChildBlk;

    MarkBufferDirty(newRootBuf);
    LockBuffer(newRootBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(newRootBuf);

    meta->root_blkno = newRootBlk;
    meta->tree_height++;
}

/*
 * Append an entry (seq -> physicalTid) to the rightmost leaf of the Bridge Router
 */
bool BridgeRouterAppend(Relation routerRel, BridgeSeqNo seq, ItemPointer physicalTid)
{
    if (routerRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }

    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks == 0) {
        BridgeRouterInit(routerRel);
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
        BlockNumber newLeafBlk = BufferGetBlockNumber(newLeafBuf);

        BridgeRouterPageHeader newHdr = (BridgeRouterPageHeader)newPage;
        errno_t rc = memset_s(newHdr, BLCKSZ, 0, BLCKSZ);
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
        hdr->pd_next_blk = newLeafBlk;
        MarkBufferDirty(leafBuf);
        LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(leafBuf);

        /* Update metapage */
        meta->rightmost_leaf_blkno = newLeafBlk;
        meta->total_entries++;
        meta->max_seq = seq;

        MarkBufferDirty(newLeafBuf);
        LockBuffer(newLeafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(newLeafBuf);

        /* Insert routing entry into internal tree */
        BridgeRouterInsertInternal(routerRel, meta, rightmostBlk, newLeafBlk, seq);

        MarkBufferDirty(metaBuf);
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);
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
