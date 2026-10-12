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
#include "access/genam.h"
#include "access/heapam.h"
#include "access/relscan.h"
#include "access/skey.h"
#include "access/tableam.h"
#include "access/ubtree.h"
#include "access/ustore/knl_uheap.h"
#include "catalog/catalog.h"
#include "catalog/dependency.h"
#include "catalog/heap.h"
#include "catalog/index.h"
#include "catalog/indexing.h"
#include "catalog/namespace.h"
#include "catalog/pg_am.h"
#include "catalog/pg_opclass.h"
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
#include "access/reloptions.h"
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
    char idxName[NAMEDATALEN];
    errno_t rc = snprintf_s(idxName, sizeof(idxName), sizeof(idxName) - 1,
                            "pg_bridge_%u_seq_idx", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");
    Oid idxOid = get_relname_relid(idxName, PG_TOAST_NAMESPACE);
    if (!OidIsValid(idxOid)) {
        return NULL;
    }
    return index_open(idxOid, lockmode);
}

Relation BridgeGetTidIndexRelation(Relation heapRel, LOCKMODE lockmode)
{
    char idxName[NAMEDATALEN];
    errno_t rc = snprintf_s(idxName, sizeof(idxName), sizeof(idxName) - 1,
                            "pg_bridge_%u_tid_idx", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");
    Oid idxOid = get_relname_relid(idxName, PG_TOAST_NAMESPACE);
    if (!OidIsValid(idxOid)) {
        return NULL;
    }
    return index_open(idxOid, lockmode);
}

Relation BridgeGetOrCreateRelation(Relation heapRel, LOCKMODE lockmode)
{
    Oid bridgeRelId = BridgeGetRelationOid(heapRel);
    if (OidIsValid(bridgeRelId)) {
        return heap_open(bridgeRelId, lockmode);
    }

    char bridgeRelName[NAMEDATALEN];
    char bridgeSeqIdxName[NAMEDATALEN];
    char bridgeTidIdxName[NAMEDATALEN];
    errno_t rc;

    rc = snprintf_s(bridgeRelName, sizeof(bridgeRelName), sizeof(bridgeRelName) - 1,
                    "pg_bridge_%u", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");

    rc = snprintf_s(bridgeSeqIdxName, sizeof(bridgeSeqIdxName), sizeof(bridgeSeqIdxName) - 1,
                    "pg_bridge_%u_seq_idx", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");

    rc = snprintf_s(bridgeTidIdxName, sizeof(bridgeTidIdxName), sizeof(bridgeTidIdxName) - 1,
                    "pg_bridge_%u_tid_idx", RelationGetRelid(heapRel));
    securec_check_ss(rc, "\0", "\0");

    /* Construct tuple descriptor: (bridge_seq int8, physical_tid tid) */
    TupleDesc tupdesc = CreateTemplateTupleDesc(2, false);
    TupleDescInitEntry(tupdesc, (AttrNumber)1, "bridge_seq", INT8OID, -1, 0);
    TupleDescInitEntry(tupdesc, (AttrNumber)2, "physical_tid", TIDOID, -1, 0);
    tupdesc->attrs[0].attstorage = 'p';
    tupdesc->attrs[1].attstorage = 'p';

    /* Reloptions for Ustore table */
    DefElem* def = makeDefElem("storage_type", (Node*)makeString(TABLE_ACCESS_METHOD_USTORE));
    List* tableOptions = list_make1(def);
    Datum reloptions = transformRelOptions((Datum)0, tableOptions, NULL, NULL, false, false);

    HashBucketInfo bucketinfo;
    bucketinfo.bucketOid = RelationGetBucketOid(heapRel);
    StorageType storage_type = RelationGetStorageType(heapRel);

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
        reloptions,
        false,
        true,
        NULL,
        REL_CMPRS_NOT_SUPPORT,
        RELATION_CREATE_BUCKET(heapRel) ? &bucketinfo : NULL,
        true,
        NULL,
        storage_type);

    CommandCounterIncrement();

    Relation bridgeRel = heap_open(bridgeRelId, ShareLock);

    /* Record dependency on heap relation */
    ObjectAddress baseobject, bridgeobject;
    bridgeobject.classId = RelationRelationId;
    bridgeobject.objectId = bridgeRelId;
    bridgeobject.objectSubId = 0;

    baseobject.classId = RelationRelationId;
    baseobject.objectId = RelationGetRelid(heapRel);
    baseobject.objectSubId = 0;

    recordDependencyOn(&bridgeobject, &baseobject, DEPENDENCY_INTERNAL);

    /* Unique index 1: (bridge_seq) */
    IndexInfo* indexInfo1 = makeNode(IndexInfo);
    indexInfo1->ii_NumIndexAttrs = 1;
    indexInfo1->ii_NumIndexKeyAttrs = 1;
    indexInfo1->ii_KeyAttrNumbers[0] = 1;
    indexInfo1->ii_Expressions = NIL;
    indexInfo1->ii_ExpressionsState = NIL;
    indexInfo1->ii_Predicate = NIL;
    indexInfo1->ii_PredicateState = NIL;
    indexInfo1->ii_ExclusionOps = NULL;
    indexInfo1->ii_ExclusionProcs = NULL;
    indexInfo1->ii_ExclusionStrats = NULL;
    indexInfo1->ii_Unique = true;
    indexInfo1->ii_ReadyForInserts = true;
    indexInfo1->ii_Concurrent = false;
    indexInfo1->ii_BrokenHotChain = false;
    indexInfo1->ii_PgClassAttrId = 0;
    indexInfo1->ii_ParallelWorkers = 0;

    Oid collationObjectId1[1] = {InvalidOid};
    Oid classObjectId1[1] = {GetDefaultOpClass(INT8OID, UBTREE_AM_OID)};
    int16 coloptions1[1] = {0};

    IndexCreateExtraArgs extra1;
    SetIndexCreateExtraArgs(&extra1, InvalidOid, false, false);

    (void)index_create(
        bridgeRel,
        bridgeSeqIdxName,
        InvalidOid,
        InvalidOid,
        indexInfo1,
        list_make1((void*)"bridge_seq"),
        UBTREE_AM_OID,
        heapRel->rd_rel->reltablespace,
        collationObjectId1,
        classObjectId1,
        coloptions1,
        reloptions,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        &extra1);

    /* Unique index 2: (physical_tid) */
    IndexInfo* indexInfo2 = makeNode(IndexInfo);
    indexInfo2->ii_NumIndexAttrs = 1;
    indexInfo2->ii_NumIndexKeyAttrs = 1;
    indexInfo2->ii_KeyAttrNumbers[0] = 2;
    indexInfo2->ii_Expressions = NIL;
    indexInfo2->ii_ExpressionsState = NIL;
    indexInfo2->ii_Predicate = NIL;
    indexInfo2->ii_PredicateState = NIL;
    indexInfo2->ii_ExclusionOps = NULL;
    indexInfo2->ii_ExclusionProcs = NULL;
    indexInfo2->ii_ExclusionStrats = NULL;
    indexInfo2->ii_Unique = false;
    indexInfo2->ii_ReadyForInserts = true;
    indexInfo2->ii_Concurrent = false;
    indexInfo2->ii_BrokenHotChain = false;
    indexInfo2->ii_PgClassAttrId = 0;
    indexInfo2->ii_ParallelWorkers = 0;

    Oid collationObjectId2[1] = {InvalidOid};
    Oid classObjectId2[1] = {GetDefaultOpClass(TIDOID, UBTREE_AM_OID)};
    int16 coloptions2[1] = {0};

    IndexCreateExtraArgs extra2;
    SetIndexCreateExtraArgs(&extra2, InvalidOid, false, false);

    (void)index_create(
        bridgeRel,
        bridgeTidIdxName,
        InvalidOid,
        InvalidOid,
        indexInfo2,
        list_make1((void*)"physical_tid"),
        UBTREE_AM_OID,
        heapRel->rd_rel->reltablespace,
        collationObjectId2,
        classObjectId2,
        coloptions2,
        reloptions,
        false,
        false,
        false,
        false,
        true,
        false,
        false,
        &extra2);

    CommandCounterIncrement();

    heap_close(bridgeRel, NoLock);

    return heap_open(bridgeRelId, lockmode);
}

bool BridgeInsertEntry(Relation heapRel, Relation indexRel, ItemPointer physicalTid, ItemPointer bridgeTidOut)
{
    Relation bridgeRel = BridgeGetOrCreateRelation(heapRel, RowExclusiveLock);
    Relation bridgeSeqIdx = BridgeGetSeqIndexRelation(heapRel, RowExclusiveLock);
    Relation bridgeTidIdx = BridgeGetTidIndexRelation(heapRel, RowExclusiveLock);

    if (bridgeRel == NULL || bridgeSeqIdx == NULL || bridgeTidIdx == NULL) {
        ereport(ERROR, (errmsg("Failed to open bridge relations for relation %u", RelationGetRelid(heapRel))));
    }

    BridgeSeqNo seq = BridgeGetNextSeq(RelationGetRelid(heapRel));
    ItemPointerData bridgeTid = BridgeSeqToItemPointer(seq);
    if (bridgeTidOut != NULL) {
        *bridgeTidOut = bridgeTid;
    }

    Datum values[2];
    bool isnull[2] = {false, false};
    values[0] = Int64GetDatum(seq);
    values[1] = PointerGetDatum(physicalTid);

    UHeapTuple uheaptup = UHeapFormTuple(RelationGetDescr(bridgeRel), values, isnull);
    (void)UHeapInsert(bridgeRel, uheaptup, GetCurrentCommandId(true), NULL, false);

    /* Insert into index 1: (bridge_seq) */
    Datum seqVal[1] = {values[0]};
    bool seqNull[1] = {false};
    (void)index_insert(bridgeSeqIdx, seqVal, seqNull, &(uheaptup->ctid), bridgeRel, UNIQUE_CHECK_YES);

    /* Insert into index 2: (physical_tid) */
    Datum tidVal[1] = {values[1]};
    bool tidNull[1] = {false};
    (void)index_insert(bridgeTidIdx, tidVal, tidNull, &(uheaptup->ctid), bridgeRel, UNIQUE_CHECK_NO);

    pfree(uheaptup);

    index_close(bridgeTidIdx, RowExclusiveLock);
    index_close(bridgeSeqIdx, RowExclusiveLock);
    heap_close(bridgeRel, RowExclusiveLock);

    return true;
}

bool BridgeDeleteEntry(Relation indexRel, Datum* values, const bool* isnull, ItemPointer physicalTid, bool isRollback)
{
    Oid heapRelId = indexRel->rd_index->indrelid;
    char bridgeRelName[NAMEDATALEN];
    errno_t rc = snprintf_s(bridgeRelName, sizeof(bridgeRelName), sizeof(bridgeRelName) - 1,
                            "pg_bridge_%u", heapRelId);
    securec_check_ss(rc, "\0", "\0");
    Oid bridgeOid = get_relname_relid(bridgeRelName, PG_TOAST_NAMESPACE);
    if (!OidIsValid(bridgeOid)) {
        return false;
    }

    Relation bridgeRel = heap_open(bridgeOid, RowExclusiveLock);
    char tidIdxName[NAMEDATALEN];
    rc = snprintf_s(tidIdxName, sizeof(tidIdxName), sizeof(tidIdxName) - 1,
                    "pg_bridge_%u_tid_idx", heapRelId);
    securec_check_ss(rc, "\0", "\0");
    Oid tidIdxOid = get_relname_relid(tidIdxName, PG_TOAST_NAMESPACE);
    if (!OidIsValid(tidIdxOid)) {
        heap_close(bridgeRel, RowExclusiveLock);
        return false;
    }
    Relation bridgeTidIdx = index_open(tidIdxOid, RowExclusiveLock);

    char seqIdxName[NAMEDATALEN];
    rc = snprintf_s(seqIdxName, sizeof(seqIdxName), sizeof(seqIdxName) - 1,
                    "pg_bridge_%u_seq_idx", heapRelId);
    securec_check_ss(rc, "\0", "\0");
    Oid seqIdxOid = get_relname_relid(seqIdxName, PG_TOAST_NAMESPACE);
    Relation bridgeSeqIdx = OidIsValid(seqIdxOid) ? index_open(seqIdxOid, RowExclusiveLock) : NULL;

    ScanKeyData key;
    ScanKeyInit(&key, 2, BTEqualStrategyNumber, F_TIDEQ, PointerGetDatum(physicalTid));

    SysScanDesc sysscan = systable_beginscan_ordered(bridgeRel, bridgeTidIdx, SnapshotNow, 1, &key);
    TupleTableSlot* slot = MakeSingleTupleTableSlot(RelationGetDescr(bridgeRel), false, bridgeRel->rd_tam_ops);
    bool found = false;

    while (UHeapSysIndexGetnextSlot(sysscan, ForwardScanDirection, slot)) {
        UHeapTuple uheaptup = ExecGetUHeapTupleFromSlot(slot);
        ItemPointerData bridgeTupleCid = uheaptup->ctid;

        bool isSeqNull = false;
        Datum seqDatum = UHeapFastGetAttr(uheaptup, 1, RelationGetDescr(bridgeRel), &isSeqNull);

        /* Delete tuple from Ustore bridge table */
        SimpleUHeapDelete(bridgeRel, &bridgeTupleCid, SnapshotNow);

        /* Delete from tid index */
        Datum delTidVal[1] = {PointerGetDatum(physicalTid)};
        bool delTidNull[1] = {false};
        index_delete(bridgeTidIdx, delTidVal, delTidNull, &bridgeTupleCid, isRollback);

        /* Delete from seq index */
        if (bridgeSeqIdx && !isSeqNull) {
            Datum delSeqVal[1] = {seqDatum};
            bool delSeqNull[1] = {false};
            index_delete(bridgeSeqIdx, delSeqVal, delSeqNull, &bridgeTupleCid, isRollback);
        }
        found = true;
        ExecClearTuple(slot);
    }

    ExecDropSingleTupleTableSlot(slot);
    systable_endscan_ordered(sysscan);

    if (bridgeSeqIdx) {
        index_close(bridgeSeqIdx, RowExclusiveLock);
    }
    index_close(bridgeTidIdx, RowExclusiveLock);
    heap_close(bridgeRel, RowExclusiveLock);

    return found;
}

bool BridgeLookupAndVerifyVisibility(Relation bridgeRel, Relation bridgeIdx, BridgeSeqNo seq, Snapshot snapshot, ItemPointer physicalTid)
{
    if (bridgeRel == NULL || bridgeIdx == NULL || seq == BRIDGE_INVALID_SEQ) {
        return false;
    }

    ScanKeyData key;
    ScanKeyInit(&key, 1, BTEqualStrategyNumber, F_INT8EQ, Int64GetDatum(seq));

    SysScanDesc sysscan = systable_beginscan_ordered(bridgeRel, bridgeIdx, snapshot, 1, &key);
    TupleTableSlot* slot = MakeSingleTupleTableSlot(RelationGetDescr(bridgeRel), false, bridgeRel->rd_tam_ops);
    bool found = false;

    if (UHeapSysIndexGetnextSlot(sysscan, ForwardScanDirection, slot)) {
        UHeapTuple ttup = ExecGetUHeapTupleFromSlot(slot);
        bool isNull = false;
        Datum tidDatum = UHeapFastGetAttr(ttup, 2, RelationGetDescr(bridgeRel), &isNull);
        if (!isNull) {
            ItemPointer storedTid = (ItemPointer)DatumGetPointer(tidDatum);
            *physicalTid = *storedTid;
            found = true;
        }
    }

    ExecDropSingleTupleTableSlot(slot);
    systable_endscan_ordered(sysscan);

    return found;
}

#include "bridge_router.cpp"
