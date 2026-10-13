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
    meta->pd_lsn = 0;
    meta->pd_checksum = 0;
    meta->pd_flags = BRIDGE_PAGE_META;
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
    hdr->pd_lsn = 0;
    hdr->pd_checksum = 0;
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
 * Flush and persist in-memory leaf cache state to Metapage (Block 0) if needed.
 */
void BridgeRouterFlushLeafCache(Relation routerRel, Buffer leafBuf)
{
    if (routerRel == NULL || !BufferIsValid(leafBuf)) {
        return;
    }

    LockBuffer(leafBuf, BUFFER_LOCK_SHARE);
    Page page = BufferGetPage(leafBuf);
    BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;
    BridgeSeqNo leafHighSeq = hdr->pd_high_seq;
    LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);

    if (leafHighSeq == 0) {
        return;
    }

    Buffer metaBuf = ReadBuffer(routerRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
    LockBuffer(metaBuf, BUFFER_LOCK_EXCLUSIVE);
    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);

    if (meta->magic == BRIDGE_ROUTER_MAGIC && meta->max_seq < leafHighSeq) {
        meta->max_seq = leafHighSeq;
        MarkBufferDirty(metaBuf);
    }

    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);
}

/*
 * High-throughput append to the rightmost leaf of the Bridge Router.
 * Supports leaf buffer caching to avoid per-tuple Metapage and leaf Buffer reads.
 */
BridgeSeqNo BridgeRouterAppendFast(Relation routerRel, Buffer *leafBuf, BlockNumber *leafBlkno, ItemPointer physicalTid)
{
    if (routerRel == NULL || physicalTid == NULL) {
        return BRIDGE_INVALID_SEQ;
    }

    /* 1. Fastpath: Check if the caller's cached leaf buffer is valid and has free space */
    if (leafBuf != NULL && BufferIsValid(*leafBuf)) {
        LockBuffer(*leafBuf, BUFFER_LOCK_EXCLUSIVE);
        Page page = BufferGetPage(*leafBuf);
        BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

        if ((hdr->pd_flags & BRIDGE_PAGE_RIGHTMOST) && (hdr->pd_item_count < BRIDGE_ROUTER_MAX_LEAF_ENTRIES)) {
            BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
            BridgeSeqNo seq = hdr->pd_high_seq + 1;
            entries[hdr->pd_item_count].seq = seq;
            entries[hdr->pd_item_count].tid = *physicalTid;
            hdr->pd_item_count++;
            hdr->pd_high_seq = seq;

            MarkBufferDirty(*leafBuf);
            LockBuffer(*leafBuf, BUFFER_LOCK_UNLOCK);
            return seq;
        }

        /* Cached page is full or no longer rightmost: release lock and buffer pin */
        LockBuffer(*leafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(*leafBuf);
        *leafBuf = InvalidBuffer;
        if (leafBlkno != NULL) {
            *leafBlkno = InvalidBlockNumber;
        }
    }

    /* 2. Slowpath: Metapage read, rightmost leaf resolution, and page split handling */
    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks == 0) {
        BridgeRouterInit(routerRel);
    }

    Buffer metaBuf = ReadBuffer(routerRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
    LockBuffer(metaBuf, BUFFER_LOCK_EXCLUSIVE);
    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);

    BlockNumber rightmostBlk = meta->rightmost_leaf_blkno;
    Buffer curLeafBuf = ReadBuffer(routerRel, rightmostBlk);
    LockBuffer(curLeafBuf, BUFFER_LOCK_EXCLUSIVE);
    Page curPage = BufferGetPage(curLeafBuf);
    BridgeRouterPageHeader curHdr = (BridgeRouterPageHeader)curPage;

    BridgeSeqNo seq;

    /* Check if current rightmost leaf page is full */
    if (curHdr->pd_item_count >= BRIDGE_ROUTER_MAX_LEAF_ENTRIES) {
        /* Allocate new leaf page (100% fill-factor right split) */
        Buffer newLeafBuf = ReadBuffer(routerRel, P_NEW);
        LockBuffer(newLeafBuf, BUFFER_LOCK_EXCLUSIVE);
        Page newPage = BufferGetPage(newLeafBuf);
        BlockNumber newLeafBlk = BufferGetBlockNumber(newLeafBuf);

        BridgeRouterPageHeader newHdr = (BridgeRouterPageHeader)newPage;
        errno_t rc = memset_s(newHdr, BLCKSZ, 0, BLCKSZ);
        securec_check(rc, "\0", "\0");
        newHdr->pd_lsn = 0;
        newHdr->pd_checksum = 0;
        newHdr->pd_flags = BRIDGE_PAGE_LEAF | BRIDGE_PAGE_RIGHTMOST;
        newHdr->pd_level = 0;
        newHdr->pd_prev_blk = rightmostBlk;
        newHdr->pd_next_blk = InvalidBlockNumber;
        newHdr->pd_item_count = 1;

        seq = curHdr->pd_high_seq + 1;
        newHdr->pd_high_seq = seq;

        BridgeLeafEntry *newEntries = (BridgeLeafEntry *)((char *)newPage + SizeOfBridgeRouterPageHeaderData);
        newEntries[0].seq = seq;
        newEntries[0].tid = *physicalTid;

        /* Update old leaf page link */
        curHdr->pd_flags &= ~BRIDGE_PAGE_RIGHTMOST;
        curHdr->pd_next_blk = newLeafBlk;
        MarkBufferDirty(curLeafBuf);
        LockBuffer(curLeafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(curLeafBuf);

        /* Update metapage */
        meta->rightmost_leaf_blkno = newLeafBlk;
        meta->total_entries++;
        meta->max_seq = seq;

        MarkBufferDirty(newLeafBuf);
        LockBuffer(newLeafBuf, BUFFER_LOCK_UNLOCK);

        /* Cache the new rightmost leaf buffer */
        if (leafBuf != NULL) {
            *leafBuf = newLeafBuf;
            if (leafBlkno != NULL) {
                *leafBlkno = newLeafBlk;
            }
        } else {
            ReleaseBuffer(newLeafBuf);
        }

        /* Insert routing entry into internal tree */
        BridgeRouterInsertInternal(routerRel, meta, rightmostBlk, newLeafBlk, seq);

        MarkBufferDirty(metaBuf);
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);
        return seq;
    }

    /* Current leaf has space */
    BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)curPage + SizeOfBridgeRouterPageHeaderData);
    if (curHdr->pd_item_count == 0 && curHdr->pd_high_seq == 0) {
        seq = meta->max_seq + 1;
    } else {
        seq = curHdr->pd_high_seq + 1;
    }

    entries[curHdr->pd_item_count].seq = seq;
    entries[curHdr->pd_item_count].tid = *physicalTid;
    curHdr->pd_item_count++;
    curHdr->pd_high_seq = seq;

    meta->total_entries++;
    meta->max_seq = seq;

    MarkBufferDirty(curLeafBuf);
    LockBuffer(curLeafBuf, BUFFER_LOCK_UNLOCK);

    /* Cache current rightmost leaf buffer */
    if (leafBuf != NULL) {
        *leafBuf = curLeafBuf;
        if (leafBlkno != NULL) {
            *leafBlkno = rightmostBlk;
        }
    } else {
        ReleaseBuffer(curLeafBuf);
    }

    MarkBufferDirty(metaBuf);
    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);
    return seq;
}

/*
 * Legacy wrapper: appends single entry and releases buffer pins.
 */
BridgeSeqNo BridgeRouterAppend(Relation routerRel, ItemPointer physicalTid)
{
    Buffer leafBuf = InvalidBuffer;
    BlockNumber leafBlkno = InvalidBlockNumber;
    BridgeSeqNo seq = BridgeRouterAppendFast(routerRel, &leafBuf, &leafBlkno, physicalTid);
    if (BufferIsValid(leafBuf)) {
        BridgeRouterFlushLeafCache(routerRel, leafBuf);
        ReleaseBuffer(leafBuf);
    }
    return seq;
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

/*
 * Reset and unpin the scan cache leaf buffer
 */
void BridgeRouterResetCache(BridgeScanCache *cache)
{
    if (cache != NULL && cache->is_valid) {
        if (BufferIsValid(cache->cached_buf)) {
            ReleaseBuffer(cache->cached_buf);
            cache->cached_buf = InvalidBuffer;
        }
        cache->cached_blkno = InvalidBlockNumber;
        cache->min_seq = 0;
        cache->max_seq = 0;
        cache->last_offset = -1;
        cache->is_valid = false;
    }
}

/*
 * Lookup a virtual BridgeSeqNo using leaf-page pinning cache (Fastpath locality probe)
 */
bool BridgeRouterLookupCached(Relation routerRel, BridgeScanCache *cache, BridgeSeqNo seq, ItemPointer physicalTid)
{
    if (routerRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }

    /* 1. Fastpath Locality Probe: Check cached leaf buffer */
    if (cache != NULL && cache->is_valid && BufferIsValid(cache->cached_buf)) {
        if (seq >= cache->min_seq && seq <= cache->max_seq) {
            LockBuffer(cache->cached_buf, BUFFER_LOCK_SHARE);
            Page page = BufferGetPage(cache->cached_buf);
            BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;
            BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);

            /* Heuristic: probe last_offset + 1 for sequential scans */
            int next_idx = cache->last_offset + 1;
            if (next_idx < hdr->pd_item_count && entries[next_idx].seq == seq) {
                *physicalTid = entries[next_idx].tid;
                cache->last_offset = next_idx;
                LockBuffer(cache->cached_buf, BUFFER_LOCK_UNLOCK);
                return true;
            }

            /* Binary search within cached leaf page */
            int idx = BridgeRouterSearchLeaf(entries, hdr->pd_item_count, seq);
            if (idx >= 0) {
                *physicalTid = entries[idx].tid;
                cache->last_offset = idx;
                LockBuffer(cache->cached_buf, BUFFER_LOCK_UNLOCK);
                return true;
            }

            LockBuffer(cache->cached_buf, BUFFER_LOCK_UNLOCK);
        }

        /* Out of cached range: release cached buffer pin */
        ReleaseBuffer(cache->cached_buf);
        cache->cached_buf = InvalidBuffer;
        cache->is_valid = false;
    }

    /* 2. Slowpath: Traverse tree to target leaf */
    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks <= BRIDGE_ROUTER_METAPAGE_BLKNO) {
        return false;
    }

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

    /* Traverse internal levels */
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

    /* Search target leaf page */
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

    if (cache != NULL && found && hdr->pd_item_count > 0) {
        /* Keep leafBuf pinned in cache across sequential lookups */
        cache->cached_buf = leafBuf;
        cache->cached_blkno = currBlk;
        cache->min_seq = entries[0].seq;
        cache->max_seq = entries[hdr->pd_item_count - 1].seq;
        cache->last_offset = idx;
        cache->is_valid = true;
        LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
    } else {
        LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(leafBuf);
    }

    return found;
}

/*
 * Batch dereferencing of virtual sequences into physical TIDs
 */
int BridgeRouterLookupBatch(Relation routerRel, BridgeScanCache *cache, const BridgeSeqNo *seqs, ItemPointer tids, bool *valids, int count)
{
    if (routerRel == NULL || seqs == NULL || tids == NULL || count <= 0) {
        return 0;
    }

    int successCount = 0;
    for (int i = 0; i < count; i++) {
        ItemPointerData tid;
        bool ok = BridgeRouterLookupCached(routerRel, cache, seqs[i], &tid);
        if (ok) {
            tids[i] = tid;
            if (valids != NULL) {
                valids[i] = true;
            }
            successCount++;
        } else {
            ItemPointerSetInvalid(&tids[i]);
            if (valids != NULL) {
                valids[i] = false;
            }
        }
    }
    return successCount;
}

/*
 * In-place update of physical TID in Bridge Router (Bridged-HOT)
 */
bool BridgeRouterUpdatePhysicalTID(Relation routerRel, BridgeSeqNo seq, ItemPointer newPhysicalTid)
{
    if (routerRel == NULL || seq == BRIDGE_INVALID_SEQ || newPhysicalTid == NULL) {
        return false;
    }

    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks <= BRIDGE_ROUTER_METAPAGE_BLKNO) {
        return false;
    }

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

    Buffer leafBuf = ReadBuffer(routerRel, currBlk);
    LockBuffer(leafBuf, BUFFER_LOCK_EXCLUSIVE);
    Page page = BufferGetPage(leafBuf);
    BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

    BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
    int idx = BridgeRouterSearchLeaf(entries, hdr->pd_item_count, seq);

    bool updated = false;
    if (idx >= 0) {
        entries[idx].tid = *newPhysicalTid;
        MarkBufferDirty(leafBuf);
        updated = true;
    }

    LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(leafBuf);
    return updated;
}

/*
 * Batch append entries into the rightmost leaf of the Bridge Router
 */
int BridgeRouterAppendBatch(Relation routerRel, const ItemPointer physicalTids, int count, BridgeSeqNo *startSeqOut)
{
    if (routerRel == NULL || physicalTids == NULL || count <= 0) {
        return 0;
    }

    BridgeSeqNo firstSeq = BRIDGE_INVALID_SEQ;
    for (int i = 0; i < count; i++) {
        BridgeSeqNo seq = BridgeRouterAppend(routerRel, (ItemPointer)&physicalTids[i]);
        if (seq == BRIDGE_INVALID_SEQ) {
            return i;
        }
        if (i == 0) {
            firstSeq = seq;
        }
    }
    if (startSeqOut != NULL) {
        *startSeqOut = firstSeq;
    }
    return count;
}

/*
 * Range scan the Bridge Router between startSeq and endSeq
 */
int BridgeRouterRangeScan(Relation routerRel, BridgeSeqNo startSeq, BridgeSeqNo endSeq, ItemPointer outTids, int maxTids)
{
    if (routerRel == NULL || startSeq == BRIDGE_INVALID_SEQ || endSeq < startSeq || outTids == NULL || maxTids <= 0) {
        return 0;
    }

    BlockNumber nblocks = RelationGetNumberOfBlocks(routerRel);
    if (nblocks <= BRIDGE_ROUTER_METAPAGE_BLKNO) {
        return 0;
    }

    Buffer metaBuf = ReadBuffer(routerRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
    LockBuffer(metaBuf, BUFFER_LOCK_SHARE);
    BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);

    if (meta->magic != BRIDGE_ROUTER_MAGIC || meta->total_entries == 0) {
        LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(metaBuf);
        return 0;
    }

    BlockNumber currBlk = meta->root_blkno;
    uint16 height = meta->tree_height;
    LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
    ReleaseBuffer(metaBuf);

    /* Traverse to the leaf holding startSeq */
    for (uint16 level = height; level > 1; level--) {
        Buffer intBuf = ReadBuffer(routerRel, currBlk);
        LockBuffer(intBuf, BUFFER_LOCK_SHARE);
        Page page = BufferGetPage(intBuf);
        BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;

        BridgeInternalEntry *entries = (BridgeInternalEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);
        BlockNumber childBlk = BridgeRouterSearchInternal(entries, hdr->pd_item_count, startSeq);

        LockBuffer(intBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(intBuf);

        if (childBlk == InvalidBlockNumber || childBlk >= nblocks) {
            return 0;
        }
        currBlk = childBlk;
    }

    /* Iterate through leaves following pd_next_blk */
    int matchedCount = 0;
    while (currBlk != InvalidBlockNumber && matchedCount < maxTids) {
        Buffer leafBuf = ReadBuffer(routerRel, currBlk);
        LockBuffer(leafBuf, BUFFER_LOCK_SHARE);
        Page page = BufferGetPage(leafBuf);
        BridgeRouterPageHeader hdr = (BridgeRouterPageHeader)page;
        BridgeLeafEntry *entries = (BridgeLeafEntry *)((char *)page + SizeOfBridgeRouterPageHeaderData);

        for (int i = 0; i < hdr->pd_item_count && matchedCount < maxTids; i++) {
            if (entries[i].seq >= startSeq && entries[i].seq <= endSeq) {
                outTids[matchedCount++] = entries[i].tid;
            } else if (entries[i].seq > endSeq) {
                LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
                ReleaseBuffer(leafBuf);
                return matchedCount;
            }
        }

        BlockNumber nextBlk = hdr->pd_next_blk;
        LockBuffer(leafBuf, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(leafBuf);
        currBlk = nextBlk;
    }

    return matchedCount;
}

