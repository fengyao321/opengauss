/* -------------------------------------------------------------------------
 *
 * bridge_index.cpp
 *    openGauss Ustore Bridge Index core implementation.
 *
 * Portions Copyright (c) 2026, openGauss Contributors
 *
 * IDENTIFICATION
 *    src/gausskernel/storage/access/index/bridge_index.cpp
 *
 * -------------------------------------------------------------------------
 */

#include "postgres.h"
#include "knl/knl_variable.h"

#include "access/bridge.h"
#include "access/bridge_router_page.h"
#include "access/genam.h"
#include "access/heapam.h"
#include "access/relscan.h"
#include "access/skey.h"
#include "access/tableam.h"
#include "access/ustore/knl_uheap.h"
#include "catalog/catalog.h"
#include "catalog/dependency.h"
#include "catalog/heap.h"
#include "catalog/index.h"
#include "catalog/indexing.h"
#include "catalog/namespace.h"
#include "catalog/pg_am.h"
#include "catalog/pg_type.h"
#include "commands/defrem.h"
#include "executor/executor.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "storage/buf/bufmgr.h"
#include "storage/lmgr.h"
#include "utils/builtins.h"
#include "utils/fmgroids.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/rel_gs.h"
#include "utils/snapmgr.h"
#include "utils/syscache.h"

/* Atomic sequence generator for bridge_seq */
static pg_atomic_uint64 g_bridge_seq;

BridgeSeqNo BridgeGetNextSeq(Oid heapRelId)
{
    uint64 seq = pg_atomic_fetch_add_u64(&g_bridge_seq, 1);
    if (seq == 0) {
        pg_atomic_write_u64(&g_bridge_seq, 2);
        return 1;
    }
    return (BridgeSeqNo)seq;
}

Oid BridgeGetRelationOid(Relation heapRel)
{
    char bridgeRelName[NAMEDATALEN];
    errno_t rc = snprintf_s(bridgeRelName, sizeof(bridgeRelName), sizeof(bridgeRelName) - 1,
                            "pg_bridge_%u", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");
    return get_relname_relid(bridgeRelName, PG_TOAST_NAMESPACE);
}

Relation BridgeGetRelation(Relation heapRel, LOCKMODE lockmode)
{
    Oid bridgeOid = BridgeGetRelationOid(heapRel);
    if (!OidIsValid(bridgeOid)) {
        return NULL;
    }
    return heap_open(bridgeOid, lockmode);
}

Relation BridgeGetSeqIndexRelation(Relation heapRel, LOCKMODE lockmode)
{
    return NULL;
}

Relation BridgeGetTidIndexRelation(Relation heapRel, LOCKMODE lockmode)
{
    return NULL;
}

Relation BridgeGetOrCreateRelation(Relation heapRel, LOCKMODE lockmode)
{
    Oid bridgeRelId = BridgeGetRelationOid(heapRel);
    if (OidIsValid(bridgeRelId)) {
        Relation bridgeRel = heap_open(bridgeRelId, lockmode);
        /* Synchronize in-memory sequence counter with persisted max_seq on disk */
        if (RelationGetNumberOfBlocks(bridgeRel) > BRIDGE_ROUTER_METAPAGE_BLKNO) {
            Buffer metaBuf = ReadBuffer(bridgeRel, BRIDGE_ROUTER_METAPAGE_BLKNO);
            LockBuffer(metaBuf, BUFFER_LOCK_SHARE);
            BridgeRouterMetaPage meta = (BridgeRouterMetaPage)BufferGetPage(metaBuf);
            if (meta->magic == BRIDGE_ROUTER_MAGIC && meta->max_seq > 0) {
                uint64 cur = pg_atomic_read_u64(&g_bridge_seq);
                while (cur <= meta->max_seq) {
                    if (pg_atomic_compare_exchange_u64(&g_bridge_seq, &cur, meta->max_seq + 1)) {
                        break;
                    }
                }
            }
            LockBuffer(metaBuf, BUFFER_LOCK_UNLOCK);
            ReleaseBuffer(metaBuf);
        }
        return bridgeRel;
    }

    char bridgeRelName[NAMEDATALEN];
    errno_t rc;

    rc = snprintf_s(bridgeRelName, sizeof(bridgeRelName), sizeof(bridgeRelName) - 1,
                    "pg_bridge_%u", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");

    /* Minimal tuple descriptor for the catalog entry */
    TupleDesc tupdesc = CreateTemplateTupleDesc(2, false);
    TupleDescInitEntry(tupdesc, (AttrNumber)1, "bridge_seq", INT8OID, -1, 0);
    TupleDescInitEntry(tupdesc, (AttrNumber)2, "physical_tid", TIDOID, -1, 0);
    tupdesc->attrs[0].attstorage = 'p';
    tupdesc->attrs[1].attstorage = 'p';

    bridgeRelId = heap_create_with_catalog(
        bridgeRelName,
        PG_TOAST_NAMESPACE,
        heapRel->rd_rel->reltablespace,
        InvalidOid,
        InvalidOid,
        InvalidOid,
        heapRel->rd_rel->relowner,
        tupdesc,
        NIL,
        RELKIND_RELATION,
        heapRel->rd_rel->relpersistence,
        heapRel->rd_rel->relisshared,
        RelationIsMapped(heapRel),
        true,
        0,
        ONCOMMIT_NOOP,
        (Datum)0,
        false,
        true,
        NULL,
        REL_CMPRS_NOT_SUPPORT,
        NULL,
        true,
        NULL,
        HEAP_DISK);

    CommandCounterIncrement();

    Relation bridgeRel = heap_open(bridgeRelId, ShareLock);

    /* Record dependency on base heap relation */
    ObjectAddress baseobject, bridgeobject;
    bridgeobject.classId = RelationRelationId;
    bridgeobject.objectId = bridgeRelId;
    bridgeobject.objectSubId = 0;

    baseobject.classId = RelationRelationId;
    baseobject.objectId = RelationGetRelid(heapRel);
    baseobject.objectSubId = 0;

    recordDependencyOn(&bridgeobject, &baseobject, DEPENDENCY_INTERNAL);

    /* Initialize the dedicated Bridge Router physical pages (Block 0 & Block 1) */
    BridgeRouterInit(bridgeRel);

    CommandCounterIncrement();

    heap_close(bridgeRel, NoLock);

    return heap_open(bridgeRelId, lockmode);
}

bool BridgeInsertEntryFast(Relation routerRel, Buffer *leafBuf, BlockNumber *leafBlkno, ItemPointer physicalTid, ItemPointer bridgeTidOut)
{
    if (routerRel == NULL || physicalTid == NULL) {
        return false;
    }

    BridgeSeqNo seq = BridgeRouterAppendFast(routerRel, leafBuf, leafBlkno, physicalTid);
    if (seq == BRIDGE_INVALID_SEQ) {
        return false;
    }

    if (bridgeTidOut != NULL) {
        *bridgeTidOut = BridgeSeqToItemPointer(seq);
    }

    return true;
}

bool BridgeInsertEntry(Relation heapRel, Relation indexRel, ItemPointer physicalTid, ItemPointer bridgeTidOut)
{
    Relation routerRel = BridgeGetOrCreateRelation(heapRel, RowExclusiveLock);
    if (routerRel == NULL) {
        ereport(ERROR, (errmsg("Failed to open bridge router relation for relation %u", RelationGetRelid(heapRel))));
    }

    Buffer leafBuf = InvalidBuffer;
    BlockNumber leafBlkno = InvalidBlockNumber;
    bool ok = BridgeInsertEntryFast(routerRel, &leafBuf, &leafBlkno, physicalTid, bridgeTidOut);
    if (BufferIsValid(leafBuf)) {
        BridgeRouterFlushLeafCache(routerRel, leafBuf);
        ReleaseBuffer(leafBuf);
    }

    heap_close(routerRel, RowExclusiveLock);
    return ok;
}

bool BridgeDeleteEntry(Relation indexRel, Datum* values, const bool* isnull, ItemPointer physicalTid, bool isRollback)
{
    /*
     * Ultimate Architecture: Zero-Cost Retail DELETE!
     * The bridge router does not write during DELETE or ROLLBACK.
     * Ghost mappings are naturally filtered by MVCC visibility on the main table
     * and anti-phantom bridge_tag verification.
     */
    return true;
}

bool BridgeLookupAndVerifyVisibility(Relation bridgeRel, Relation bridgeIdx, BridgeSeqNo seq, Snapshot snapshot, ItemPointer physicalTid)
{
    if (bridgeRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }
    return BridgeRouterLookup(bridgeRel, seq, physicalTid);
}

bool BridgeLookupAndVerifyVisibilityCached(Relation bridgeRel, BridgeScanCache *cache, BridgeSeqNo seq, Snapshot snapshot, ItemPointer physicalTid)
{
    if (bridgeRel == NULL || seq == BRIDGE_INVALID_SEQ || physicalTid == NULL) {
        return false;
    }
    return BridgeRouterLookupCached(bridgeRel, cache, seq, physicalTid);
}


#include "bridge_router.cpp"
