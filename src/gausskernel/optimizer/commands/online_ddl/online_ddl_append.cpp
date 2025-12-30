/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 *
 * openGauss is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 * ---------------------------------------------------------------------------------------
 *
 * online_ddl_append.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/optimizer/commands/online_ddl/online_ddl_append.cpp
 *
 * ---------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "fmgr.h"
#include "access/tableam.h"
#include "access/relscan.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"
#include "storage/item/itemptr.h"
#include "catalog/pg_type.h"
#include "utils/builtins.h"
#include "storage/procarray.h"
#include "commands/tablecmds.h"

#include "commands/online_ddl_deltalog.h"
#include "commands/online_ddl_ctid_map.h"
#include "commands/online_ddl_util.h"
#include "commands/online_ddl_append.h"

#define DatumGetItemPointer(X) ((ItemPointer)DatumGetPointer(X))

const int ONLINE_DDL_APPENDER_MAX_SCAN_TIME = 5;
const int ONLINE_DDL_APPENDER_MAX_FINISH_PAGES = 8;

static EState* create_estate_for_relation(Relation rel);
static inline void CleanupEstate(EState* estate, EPQState* epqstate);

#define ITEM_POINTER_FIRST_OFFSET (1)
/* return true if a and b differ by exactly one tuple, else return false */
inline bool AreItemPointersAdjacent(ItemPointer a, ItemPointer b)
{
    /* skip first block */
    if (ItemPointerGetBlockNumber(a) == 0 && ItemPointerGetOffsetNumber(a) == 1) {
        return true;
    } else if (ItemPointerGetBlockNumber(a) == ItemPointerGetBlockNumber(b)) {
        int offsetDiff = ItemPointerGetOffsetNumber(b) - ItemPointerGetOffsetNumber(a);
        return offsetDiff == 1;
    } else if (ItemPointerGetBlockNumber(b) - ItemPointerGetBlockNumber(a) == 1) {
        return ItemPointerGetOffsetNumber(b) == ITEM_POINTER_FIRST_OFFSET;
    }
    return false;
}

// Initialize the hash table mapping old partitions to temporary tables
static HTAB* InitPartitionOidMap()
{
    HASHCTL ctl;
    errno_t rc = memset_s(&ctl, sizeof(ctl), 0, sizeof(ctl));
    securec_check(rc, "\0", "\0");

    ctl.keysize = sizeof(Oid);
    ctl.entrysize = sizeof(PartitionOidMapEntry);
    ctl.hcxt = CurrentMemoryContext;

    HTAB* hash = hash_create("Partition Oid Map", 32, &ctl, HASH_ELEM | HASH_CONTEXT | HASH_BLOBS);
    return hash;
}

// Add mapping from old partition to temporary table in the hash table
void AddPartitionOidMapping(OnlineDDLAppender* appender, Oid oldPartOid, Oid tempTableOid)
{
    bool found = false;
    PartitionOidMapEntry* entry =
        (PartitionOidMapEntry*)hash_search(appender->PartitionOidMap, &oldPartOid, HASH_ENTER, &found);
    entry->oldPartOid = oldPartOid;
    entry->tempTableOid = tempTableOid;
}

// Find the corresponding temporary table OID based on the old partition OID
Oid GetTempTableFromOldPartition(OnlineDDLAppender* appender, Oid oldPartOid)
{
    bool found = false;
    PartitionOidMapEntry* entry =
        (PartitionOidMapEntry*)hash_search(appender->PartitionOidMap, &oldPartOid, HASH_FIND, &found);
    if (found) {
        return entry->tempTableOid;
    }
    return InvalidOid;
}

// for none-partition table, we init appender with oldRelation and newRelation
OnlineDDLAppender* OnlineDDLInitAppender(Relation oldRelation, Relation newRelation, Relation deltaRelation,
                                         Relation ctidMapRelation, Relation ctidMapIndex, ItemPointerData endCtid,
                                         AlteredTableInfo* alterTableInfo)
{
    OnlineDDLAppender* appender = NULL;
    appender = (OnlineDDLAppender*)palloc0(sizeof(OnlineDDLAppender));
    appender->inAppendMode = true;
    appender->deltaLogScanTimes = 0;
    appender->oldTableScanTimes = 0;

    ItemPointerSet(&appender->deltaLogScanIdx, 0, 1);
    appender->oldTableScanIdx = endCtid;
    appender->partitionAppendMap = NULL;

    appender->oldRelation = oldRelation;
    appender->newRelation = newRelation;
    appender->oldPartitionList = NIL;
    appender->newOidList = NIL;
    appender->deltaRelation = deltaRelation;
    appender->ctidMapRelation = ctidMapRelation;
    appender->ctidMapIndex = ctidMapIndex;
    appender->alterTableInfo = alterTableInfo;

    appender->PartitionOidMap = NULL;

    ereport(DEBUG5, (errmsg("[Online-DDL] OnlineDDLInitAppender: oldRelation = %u, toastoid = %u, newRelation = %u, "
                            "toastoid = %u, deltaRelation = %u, ctidMapRelation = %u, ctidMapIndex = %u",
                            oldRelation->rd_id, oldRelation->rd_rel->reltoastrelid, newRelation->rd_id,
                            newRelation->rd_rel->reltoastrelid, deltaRelation->rd_id, ctidMapRelation->rd_id,
                            ctidMapIndex->rd_id)));
    return appender;
}

// for partition table, we init appender with old partition list and new oid list
OnlineDDLAppender* OnlineDDLInitAppender(List* oldPartitionList, List* newOidList, Relation deltaRelation,
                                         Relation ctidMapRelation, Relation ctidMapIndex, HTAB* partitionAppendMap,
                                         AlteredTableInfo* alterTableInfo)
{
    OnlineDDLAppender* appender = NULL;
    appender = (OnlineDDLAppender*)palloc0(sizeof(OnlineDDLAppender));
    appender->inAppendMode = true;
    appender->deltaLogScanTimes = 0;
    appender->oldTableScanTimes = 0;

    ItemPointerSet(&appender->deltaLogScanIdx, 0, 1);

    ItemPointerSetInvalid(&appender->oldTableScanIdx);
    appender->partitionAppendMap = partitionAppendMap;

    appender->oldRelation = NULL;
    appender->newRelation = NULL;
    appender->oldPartitionList = oldPartitionList;
    appender->newOidList = newOidList;
    appender->deltaRelation = deltaRelation;
    appender->ctidMapRelation = ctidMapRelation;
    appender->ctidMapIndex = ctidMapIndex;
    appender->alterTableInfo = alterTableInfo;

    appender->PartitionOidMap = InitPartitionOidMap();

    return appender;
}

static void GetRemainPages(OnlineDDLAppender* appender, int* deltaLogRemainPages, int* oldTableRemainPages)
{
    if (deltaLogRemainPages == NULL || oldTableRemainPages == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] GetDeltaLogDetail error: operation or oldTupCtid is null.")));
    }
    BlockNumber deltaLogBlockNum = RelationGetNumberOfBlocks(appender->deltaRelation);
    BlockNumber oldTableBlockNum = RelationGetNumberOfBlocks(appender->oldRelation);
    /* appender->oldTableScanIdx maybe start from (0, 0). */
    if (ItemPointerGetBlockNumber(&appender->deltaLogScanIdx) > deltaLogBlockNum ||
        ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx) > oldTableBlockNum) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] GetRemainPages error: delta log scan idx or old table scan idx is invalid, delta "
                        "log block num: %u, old table block num: %u, delta log scan idx block num: %u, old table scan "
                        "idx block num: %u.",
                        deltaLogBlockNum, oldTableBlockNum, ItemPointerGetBlockNumber(&appender->deltaLogScanIdx),
                        ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx))));
    }
    *deltaLogRemainPages = Max(deltaLogBlockNum - ItemPointerGetBlockNumber(&appender->deltaLogScanIdx), 0);
    *oldTableRemainPages = Max(oldTableBlockNum - ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx), 0);
}

/* Check if deltal log tuple committed, if not, wait until it end */
static bool CheckTupleVisibile(HeapTuple tuple, Buffer buffer)
{
    /* check tuple has been committed */
    TransactionId xmin = HeapTupleHeaderGetXmin(BufferGetPage(buffer), tuple->t_data);
    ItemPointer deltaLogCtid = &tuple->t_self;
    if (TransactionIdIsCurrentTransactionId(xmin) || TransactionIdIsValid(xmin) == false) {
        /* The tuple is part of the current transaction, not yet committed */
        LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
        Assert(0);
        ereport(
            ERROR,
            (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
             errmsg("[Online-DDL] CheckDeltaLogCommit error: invalid xmin:%lu tuple with ctid (%u, %u) in delta log.",
                    xmin, ItemPointerGetBlockNumber(deltaLogCtid), ItemPointerGetOffsetNumber(deltaLogCtid))));
    } else if (TransactionIdIsInProgress(xmin)) {
        ereport(ONLINE_DDL_LOG_LEVEL,
                (errmsg("[Online-DDL] CheckDeltaLogCommit notice: tuple with ctid (%u, %u) in delta log is not "
                        "committed, wait until it commits.",
                        ItemPointerGetBlockNumber(deltaLogCtid), ItemPointerGetOffsetNumber(deltaLogCtid))));
        LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
        /* The transaction is still in progress, wait until it commits */
        XactLockTableWait(xmin);
        LockBuffer(buffer, BUFFER_LOCK_SHARE);
    }
    TransactionId xmax = HeapTupleHeaderGetXmax(BufferGetPage(buffer), tuple->t_data);
    if (TransactionIdIsCurrentTransactionId(xmax)) {
        Assert(0);
        ereport(
            ERROR,
            (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
             errmsg("[Online-DDL] CheckDeltaLogCommit error: invalid xmax:%lu tuple with ctid (%u, %u) in delta log.",
                    xmax, ItemPointerGetBlockNumber(deltaLogCtid), ItemPointerGetOffsetNumber(deltaLogCtid))));
    }
    if (TransactionIdIsValid(xmax) && TransactionIdIsInProgress(xmax)) {
        LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
        /* The transaction is still in progress, wait until it commits */
        XactLockTableWait(xmax);
        LockBuffer(buffer, BUFFER_LOCK_SHARE);
    }

    return HeapTupleSatisfiesVisibility(tuple, SnapshotNow, buffer);
}

// for non-partition table, get operation type and old tuple ctid from delta log tuple
bool GetDeltaLogDetail(OnlineDDLAppender* appender, HeapTuple tuple, uint8* operation, ItemPointer oldTupCtid)
{
    if (operation == NULL || oldTupCtid == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] GetDeltaLogDetail error: operation or oldTupCtid is null.")));
    }

    Datum values[ONLINE_DDL_DELTALOG_ATTR_NUM];
    bool isnull[ONLINE_DDL_DELTALOG_ATTR_NUM];
    errno_t rc;
    rc = memset_s(values, sizeof(values), 0, sizeof(values));
    securec_check(rc, "\0", "\0");
    rc = memset_s(isnull, sizeof(isnull), false, sizeof(isnull));
    securec_check(rc, "\0", "\0");
    TupleDesc tupleDesc = RelationGetDescr(appender->deltaRelation);
    heap_deform_tuple(tuple, tupleDesc, values, isnull);

    if (isnull[DELTALOG_OPERATION_TYPE_IDX] || isnull[DELTALOG_TUP_CTDI_IDX]) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] GetDeltaLogDetail error: null value found in delta log tuple with ctid (%u, %u).",
                        ItemPointerGetBlockNumber(&tuple->t_self), ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    *operation = DatumGetUInt8(values[DELTALOG_OPERATION_TYPE_IDX]);
    ItemPointer oldCtid = DatumGetItemPointer(values[DELTALOG_TUP_CTDI_IDX]);
    if (*operation >= ONLINE_DDL_OPERATEION_TYPE_NUM) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("[Online-DDL] GetDeltaLogDetail error: invalid operation type %u in delta log tuple "
                               "with ctid (%u, %u).",
                               *operation, ItemPointerGetBlockNumber(&tuple->t_self),
                               ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    if (!ItemPointerIsValid(oldCtid)) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] GetDeltaLogDetail error: invalid old ctid in delta log tuple with ctid (%u, %u).",
                        ItemPointerGetBlockNumber(&tuple->t_self), ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    ItemPointerSet(oldTupCtid, ItemPointerGetBlockNumber(oldCtid), ItemPointerGetOffsetNumber(oldCtid));
    return true;
}

// for partition table, get operation type, old tuple ctid and old partition oid from delta log tuple
bool GetDeltaLogDetail(OnlineDDLAppender* appender, HeapTuple tuple, uint8* operation, ItemPointer oldTupCtid,
                       Oid* oldPartOid)
{
    if (operation == NULL || oldTupCtid == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] GetDeltaLogDetail error: operation or oldTupCtid is null.")));
    }

    Datum values[3];
    bool isnull[3];
    errno_t rc;
    rc = memset_s(values, sizeof(values), 0, sizeof(values));
    securec_check(rc, "\0", "\0");
    rc = memset_s(isnull, sizeof(isnull), false, sizeof(isnull));
    securec_check(rc, "\0", "\0");
    TupleDesc tupleDesc = RelationGetDescr(appender->deltaRelation);
    heap_deform_tuple(tuple, tupleDesc, values, isnull);

    if (isnull[DELTALOG_OPERATION_TYPE_IDX] || isnull[DELTALOG_TUP_CTDI_IDX] || isnull[ONLINE_DDL_DELTALOG_ATTR_NUM]) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] GetDeltaLogDetail error: null value found in delta log tuple with ctid (%u, %u).",
                        ItemPointerGetBlockNumber(&tuple->t_self), ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    *operation = DatumGetUInt8(values[DELTALOG_OPERATION_TYPE_IDX]);
    ItemPointer oldCtid = DatumGetItemPointer(values[DELTALOG_TUP_CTDI_IDX]);
    *oldPartOid = DatumGetObjectId(values[ONLINE_DDL_DELTALOG_ATTR_NUM]);
    if (*operation >= ONLINE_DDL_OPERATEION_TYPE_NUM) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("[Online-DDL] GetDeltaLogDetail error: invalid operation type %u in delta log tuple "
                               "with ctid (%u, %u).",
                               *operation, ItemPointerGetBlockNumber(&tuple->t_self),
                               ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    if (!ItemPointerIsValid(oldCtid)) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] GetDeltaLogDetail error: invalid old ctid in delta log tuple with ctid (%u, %u).",
                        ItemPointerGetBlockNumber(&tuple->t_self), ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    if (!OidIsValid(*oldPartOid)) {
        ereport(
            ERROR,
            (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
             errmsg(
                 "[Online-DDL] GetDeltaLogDetail error: invalid partition oid in delta log tuple with ctid (%u, %u).",
                 ItemPointerGetBlockNumber(&tuple->t_self), ItemPointerGetOffsetNumber(&tuple->t_self))));
    }
    ItemPointerSet(oldTupCtid, ItemPointerGetBlockNumber(oldCtid), ItemPointerGetOffsetNumber(oldCtid));
    return true;
}

static HeapTuple OnlineDDLGetTupleByCtid(Relation relation, ItemPointer tupCtid, Snapshot snapshot, Buffer* buffer)
{
    if (relation == NULL || !RelationIsValid(relation)) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("OnlineDDLGetTupleByCtid error: relation is not valid.")));
    }
    if (tupCtid == NULL || !ItemPointerIsValid(tupCtid)) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("OnlineDDLGetTupleByCtid error: tupCtid is null or invalid.")));
    }
    HeapTuple tuple = NULL;
    tuple = (HeapTupleData*)heaptup_alloc(BLCKSZ);
    tuple->t_data = (HeapTupleHeader)((char*)tuple + HEAPTUPLESIZE);
    tuple->t_self = *tupCtid;
    bool fetched = tableam_tuple_fetch(relation, snapshot, tuple, buffer, true, NULL);
    return fetched ? tuple : NULL;
}

/**
 * @brief Insert tuples from old table into new table, handling data migration in online DDL operations
 *
 * This function is responsible for converting tuples from the old table according to online DDL operation requirements
 * and inserting them into the new table. It handles the impact of various DDL operations (such as adding columns,
 * modifying columns, adding constraints, etc.) on tuples, and ensures that new tuples satisfy all constraint
 * conditions.
 *
 * @param appender Pointer to online DDL appender structure, containing relation information such as old table, new
 * table, delta log, etc. if appender->newRelatoin == NULL, only check constraint, not insert tuple into new table.
 * @param oldTuple Tuple from the old table
 * @param hiOptions Heap insert options
 * @return bool Returns true on success, throws an error on failure
 */
static bool OnlineDDLInsertIntoNewRelation(OnlineDDLAppender* appender, HeapTuple oldTuple, uint32 hiOptions)
{
    TupleDesc oldTupDesc;
    TupleDesc newTupDesc;
    bool needscan = false;
    List* notnullAttrs = NIL;
    ListCell* l = NULL;
    EState* estate = NULL;

    AlteredTableInfo* tab = appender->alterTableInfo;

    Relation oldRelation = appender->oldRelation;
    Relation newRelation = appender->newRelation;
    oldTupDesc = tab->oldDesc;
    newTupDesc = RelationGetDescr(oldRelation);

    CommandId mycid = newRelation ? GetCurrentCommandId(true) : 0;
    BulkInsertState bistate = newRelation ? GetBulkInsertState() : NULL;

    bool replModify = false;
    bool needDmlChangeCol = false;

    estate = CreateExecutorState();

    /* Build the needed expression execution states */
    foreach (l, tab->constraints) {
        NewConstraint* con = (NewConstraint*)lfirst(l);
        if (con->isdisable)
            continue;

        switch (con->contype) {
            case CONSTR_CHECK:
                needscan = true;
                if (estate->es_is_flt_frame) {
                    con->qualstate = (List*)ExecPrepareExprList((List*)con->qual, estate);
                } else {
                    con->qualstate = (List*)ExecPrepareExpr((Expr*)con->qual, estate);
                }
                break;
            case CONSTR_FOREIGN:
                /* Nothing to do here */
                break;
            default: {
                ereport(ERROR, (errcode(ERRCODE_UNRECOGNIZED_NODE_TYPE),
                                errmsg("unrecognized constraint type: %d", (int)con->contype)));
            }
        }
    }

    foreach (l, tab->newvals) {
        NewColumnValue* ex = (NewColumnValue*)lfirst(l);

        /* expr already planned */
        ex->exprstate = ExecInitExpr((Expr*)ex->expr, NULL);

        if (ex->is_generated || ex->is_alter_using) {
            replModify = false;
        }

        if (ex->make_dml_change) {
            needDmlChangeCol = true;
        }
    }

    if (newRelation || tab->new_notnull) {
        /*
         * If we are rebuilding the tuples OR if we added any new NOT NULL
         * constraints, check all not-null constraints.  This is a bit of
         * overkill but it minimizes risk of bugs, and heap_attisnull is a
         * pretty cheap test anyway.
         */
        for (int i = 0; i < newTupDesc->natts; i++) {
            if (newTupDesc->attrs[i].attnotnull && !newTupDesc->attrs[i].attisdropped)
                notnullAttrs = lappend_int(notnullAttrs, i);
        }
        if (notnullAttrs != NULL) {
            needscan = true;
        }
    }

    if (newRelation || needscan) {
        ExprContext* econtext = NULL;
        Datum* values = NULL;
        bool* isnull = NULL;
        TupleTableSlot* oldslot = NULL;
        TupleTableSlot* newslot = NULL;
        List* droppedAttrs = NIL;
        errno_t rc = EOK;
        int128 autoinc = 0;
        bool needAutoinc = false;
        bool hasGenerated = false;
        AttrNumber autoinc_attnum =
            (newTupDesc->constr && newTupDesc->constr->cons_autoinc) ? newTupDesc->constr->cons_autoinc->attnum : 0;

        econtext = GetPerTupleExprContext(estate);

        /*
         * Make tuple slots for old and new tuples.  Note that even when the
         * tuples are the same, the tupDescs might not be (consider ADD COLUMN
         * without a default).
         */
        oldslot = MakeSingleTupleTableSlot(oldTupDesc, false, oldRelation->rd_tam_ops);
        newslot = MakeSingleTupleTableSlot(newTupDesc, false, oldRelation->rd_tam_ops);

        /* Preallocate values/isnull arrays */
        int n = Max(newTupDesc->natts, oldTupDesc->natts);
        values = (Datum*)palloc(n * sizeof(Datum));
        isnull = (bool*)palloc(n * sizeof(bool));
        rc = memset_s(values, n * sizeof(Datum), 0, n * sizeof(Datum));
        securec_check(rc, "\0", "\0");
        rc = memset_s(isnull, n * sizeof(bool), true, n * sizeof(bool));
        securec_check(rc, "\0", "\0");

        /*
         * Any attributes that are dropped according to the new tuple
         * descriptor can be set to NULL. We precompute the list of dropped
         * attributes to avoid needing to do so in the per-tuple loop.
         */
        for (int i = 0; i < newTupDesc->natts; i++) {
            if (newTupDesc->attrs[i].attisdropped)
                droppedAttrs = lappend_int(droppedAttrs, i);
        }

        /*
         * here we don't care oldTupDesc->initdefvals, because it's
         * handled during deforming old tuple. new values for added
         * colums maybe is from *tab->newvals* list, or newTupDesc'
         * initdefvals list.
         */
        if (newTupDesc->initdefvals) {
            TupInitDefVal* defvals = newTupDesc->initdefvals;

            /* skip all the existing columns within this relation */
            for (int i = oldTupDesc->natts; i < newTupDesc->natts; ++i) {
                if (!defvals[i].isNull) {
                    /* we assign both *isnull* and *values* here instead of
                     * scaning loop, because all these are constant and not
                     * dependent on each tuple.
                     */
                    isnull[i] = false;
                    values[i] = fetchatt(&newTupDesc->attrs[i], defvals[i].datum);
                }
            }
        }

        if (RelationIsUstoreFormat(oldRelation)) {
            // not support ustore table append operation for now
            ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                            errmsg("[Online-DDL] Append operation is not supported for ustore table.")));
        } else {
            /* append or check oldTuple */
            HeapTuple tuple = oldTuple;
            /* newTuple is the same as oldTuple if only check */
            HeapTuple newTuple = tuple;
            ItemPointer oldCtid = &tuple->t_self;
            if (tab->check_pass_with_relempty == AT_FASN_FAIL_PRECISION) {
                ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                                errmsg("column to be modified must be empty to decrease precision or scale")));
            } else if (tab->check_pass_with_relempty == AT_FASN_FAIL_TYPE) {
                ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                                errmsg("column to be modified must be empty to change datatype")));
            }
            if (tab->rewrite > 0) {
                Oid tupOid = InvalidOid;
                int newvalsNum = 0;
                ListCell* lc = NULL;
                tableam_tops_deform_tuple(tuple, oldTupDesc, values, isnull);
                if (oldTupDesc->tdhasoid) {
                    tupOid = HeapTupleGetOid(tuple);
                }
                (void)ExecStoreTuple(tuple, oldslot, InvalidBuffer, false);
                econtext->ecxt_scantuple = oldslot;

                foreach (l, tab->newvals) {
                    NewColumnValue* ex = (NewColumnValue*)lfirst(l);

                    if (ex->is_addloc) {
                        for (int i = oldTupDesc->natts + newvalsNum - 1; i >= ex->attnum - 1; i--) {
                            values[i + 1] = values[i];
                            isnull[i + 1] = isnull[i];
                        }
                        newvalsNum++;
                    }

                    if (ex->is_generated) {
                        if (tab->is_first_after) {
                            UpdateValueModifyFirstAfter(ex, values, isnull);
                            hasGenerated = true;
                        } else {
                            isnull[ex->attnum - 1] = true;
                        }
                        continue;
                    }

                    values[ex->attnum - 1] = ExecEvalExpr(ex->exprstate, econtext, &isnull[ex->attnum - 1]);

                    if (ex->is_autoinc) {
                        needAutoinc = (autoinc_attnum > 0);
                    }

                    if (tab->is_first_after) {
                        UpdateValueModifyFirstAfter(ex, values, isnull);
                    }
                }
                /* generated column */
                UpdateGeneratedColumnIsnull(tab, isnull, hasGenerated);

                /* auto_increment */
                if (needAutoinc) {
                    autoinc = EvaluateAutoIncrement(oldRelation, newTupDesc, autoinc_attnum,
                                                    &values[autoinc_attnum - 1], &isnull[autoinc_attnum - 1]);
                }

                /* Set dropped attributes to null in new tuple */
                foreach (lc, droppedAttrs) {
                    isnull[lfirst_int(lc)] = true;
                }
                /*
                 * Form the new tuple. Note that we don't explicitly pfree it,
                 * since the per-tuple memory context will be reset shortly.
                 */
                newTuple = (HeapTuple)heap_form_tuple(newTupDesc, values, isnull);

                /* Preserve OID, if any */
                if (newTupDesc->tdhasoid) {
                    HeapTupleSetOid(newTuple, tupOid);
                }
            }

            /* Now check any constraints on the possibly-changed tuple */
            (void)ExecStoreTuple(newTuple, newslot, InvalidBuffer, false);
            econtext->ecxt_scantuple = newslot;

            /*
             * Now, evaluate any expressions whose inputs come from the
             * new tuple.  We assume these columns won't reference each
             * other, so that there's no ordering dependency.
             */
            newTuple = EvaluateGenExpr<HeapTuple, TAM_HEAP>(tab, newTuple, newTupDesc, econtext, values, isnull);
            foreach (l, notnullAttrs) {
                int attn = lfirst_int(l);
                /* replace heap_attisnull with relationAttIsNull due to altering table instantly */
                if (relationAttIsNull(newTuple, attn + 1, newTupDesc))
                    ereport(ERROR,
                            (errcode(ERRCODE_NOT_NULL_VIOLATION),
                             errmsg("column \"%s\" contains null values", NameStr(newTupDesc->attrs[attn].attname))));
            }

            foreach (l, tab->constraints) {
                NewConstraint* con = (NewConstraint*)lfirst(l);
                ListCell* lc = NULL;

                switch (con->contype) {
                    case CONSTR_CHECK: {
                        if (estate->es_is_flt_frame) {
                            foreach (lc, con->qualstate) {
                                ExprState* exprState = (ExprState*)lfirst(lc);

                                if (!ExecCheckByFlatten(exprState, econtext))
                                    ereport(ERROR,
                                            (errcode(ERRCODE_CHECK_VIOLATION),
                                             errmsg("check constraint \"%s\" is violated by some row", con->name)));
                            }
                        } else {
                            if (!ExecQualByRecursion(con->qualstate, econtext, true)) {
                                ereport(ERROR, (errcode(ERRCODE_CHECK_VIOLATION),
                                                errmsg("check constraint \"%s\" is violated by some row", con->name)));
                            }
                        }
                        break;
                    }
                    case CONSTR_FOREIGN:
                        /* Nothing to do here */
                        break;
                    default: {
                        ereport(ERROR, (errcode(ERRCODE_UNRECOGNIZED_NODE_TYPE),
                                        errmsg("unrecognized constraint type: %d", (int)con->contype)));
                    }
                }
            }

            if (newRelation) {
                (void)tableam_tuple_insert(newRelation, newTuple, mycid, hiOptions, bistate);
                if (autoinc > 0) {
                    SetRelAutoIncrement(oldRelation, newTupDesc, autoinc);
                }
                /* Init ResultRelInfo */
                ResultRelInfo* resultRelInfo = makeNode(ResultRelInfo);
                InitResultRelInfo(resultRelInfo, newRelation, 1, 0);
                ExecOpenIndices(resultRelInfo, false);
                estate->es_result_relations = resultRelInfo;
                estate->es_num_result_relations = 1;
                estate->es_result_relation_info = resultRelInfo;
                /* append index of new tuple */
                if (resultRelInfo->ri_NumIndices > 0) {
                    List* recheckIndexes = NIL;
                    ItemPointer pTself = tableam_tops_get_t_self(newRelation, newTuple);
                    recheckIndexes =
                        ExecInsertIndexTuples(newslot, pTself, estate, newRelation, NULL, InvalidBktId, NULL, NULL);
                    list_free_ext(recheckIndexes);
                }
                ExecCloseIndices(resultRelInfo);
                /*
                 * For partitioned tables, use hash table to get the corresponding temporary table OID and establish
                 * mapping relationship
                 */
                if (appender->PartitionOidMap != NULL) {
                    /*
                     * If it's a partitioned table scenario, establish mapping relationship between old partition tuple
                     * and new partition tuple
                     */
                    Oid oldPartOid = RelationGetRelid(oldRelation);
                    Oid tempTableOid = GetTempTableFromOldPartition(appender, oldPartOid);
                    if (OidIsValid(tempTableOid)) {
                        // Insert mapping relationship with partition OID
                        OnlineDDLInsertCtidMap(&((HeapTuple)oldTuple)->t_self, tempTableOid,
                                               &((HeapTuple)newTuple)->t_self, appender->ctidMapRelation);
                    }
                } else {
                    // Non-partitioned table case, use ordinary mapping relationship
                    OnlineDDLInsertCtidMap(&((HeapTuple)oldTuple)->t_self, &((HeapTuple)newTuple)->t_self,
                                           appender->ctidMapRelation);
                }
            }
            ResetExprContext(econtext);
            CHECK_FOR_INTERRUPTS();
            if (tab->is_first_after) {
                rc = memset_s(values, n * sizeof(Datum), 0, n * sizeof(Datum));
                securec_check(rc, "\0", "\0");
                rc = memset_s(isnull, n * sizeof(bool), true, n * sizeof(bool));
                securec_check(rc, "\0", "\0");
            }
        }

        ExecDropSingleTupleTableSlot(oldslot);
        ExecDropSingleTupleTableSlot(newslot);
    }

    FreeExecutorState(estate);
    if (newRelation) {
        FreeBulkInsertState(bistate);
    }
    return true;
}

static bool OnlineDDLDeleteFromNewRelation(OnlineDDLAppender* appender, ItemPointer tupCtid)
{
    if (appender == NULL) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("OnlineDDLDeleteFromNewRelation error: appender is null")));
    }

    Relation newRelation = appender->newRelation;
    if (newRelation == NULL || !RelationIsValid(newRelation)) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("OnlineDDLDeleteFromNewRelation error: new relation is not valid.")));
    }

    if (tupCtid == NULL || !ItemPointerIsValid(tupCtid)) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("OnlineDDLDeleteFromNewRelation error: tupCtid is null or invalid.")));
    }
    /* Init estate. */
    EState* estate;
    EPQState epqstate;

    estate = create_estate_for_relation(newRelation);
    PushActiveSnapshot(GetTransactionSnapshot());
    ExecOpenIndices(estate->es_result_relations, false);
    EvalPlanQualInit(&epqstate, estate, NULL, NIL, -1);

    TupleTableSlot* oldslot = NULL;
    TM_FailureData tmfd;
    TM_Result res = tableam_tuple_delete(newRelation, tupCtid, GetCurrentCommandId(true), InvalidSnapshot, SnapshotNow,
                                         true, &oldslot, &tmfd);

    Bitmapset* modifiedIdxAttrs = NULL;
    ExecIndexTuplesState exec_index_tuples_state;
    exec_index_tuples_state.estate = estate;
    exec_index_tuples_state.targetPartRel = NULL;
    exec_index_tuples_state.p = NULL;
    exec_index_tuples_state.conflict = NULL;
    exec_index_tuples_state.rollbackIndex = false;

    tableam_tops_exec_delete_index_tuples(oldslot, newRelation, NULL, tupCtid, exec_index_tuples_state,
                                          modifiedIdxAttrs);
    if (oldslot) {
        ExecDropSingleTupleTableSlot(oldslot);
    }

    CleanupEstate(estate, &epqstate);
    return true;
}

static bool OnlineDDLAppendScanDeltaLog(OnlineDDLAppender* appender, TableScanDesc deltaLogScan)
{
    if ((HeapScanDesc)deltaLogScan == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog error: deltaLogScan is null.")));
    }
    if (((HeapScanDesc)deltaLogScan)->rs_base.rs_nblocks == 0) {
        ereport(ONLINE_DDL_LOG_LEVEL,
                (errcode(MOD_ONLINE_DDL), errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog notice: delta log relation "
                                                 "is empty, no delta log to process.")));
        return true;
    }
    HeapTuple deltaLogTuple = NULL;
    bool scanFinished = false;
    ItemPointerData tmpCtid;
    ItemPointerSet(&tmpCtid, 0, 1);
    while ((deltaLogTuple = (HeapTuple)tableam_scan_getnexttuple(deltaLogScan, ForwardScanDirection)) != NULL) {
        ItemPointer deltaLogCtid = &deltaLogTuple->t_self;
        ereport(ONLINE_DDL_LOG_LEVEL,
                (errmsg("Scan delta log tuple:  (%u, %u)", ItemPointerGetBlockNumber(deltaLogCtid),
                        ItemPointerGetOffsetNumber(deltaLogCtid))));
        bool committed;
        BlockNumber block;
        Buffer buffer;
        uint8 operation;
        ItemPointerData oldTupCtid = {{0, 0}, 1};
        Oid oldPartOid = InvalidOid;

        /* check ctid if has been scaned */
        if (!CompareItemPointer(&appender->deltaLogScanIdx, deltaLogCtid)) {
            continue;
        }

#ifdef USE_ASSERT_CHECKING
        Assert(CompareItemPointer(&tmpCtid, deltaLogCtid) && AreItemPointersAdjacent(&tmpCtid, deltaLogCtid));
        tmpCtid = *deltaLogCtid;
#endif

        block = ItemPointerGetBlockNumber(deltaLogCtid);
        buffer = ReadBuffer(appender->deltaRelation, block);
        LockBuffer(buffer, BUFFER_LOCK_SHARE);
        committed = CheckTupleVisibile(deltaLogTuple, buffer);
        if (!committed) {
            LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
            ItemPointerSet(&appender->deltaLogScanIdx, ItemPointerGetBlockNumber(deltaLogCtid),
                           ItemPointerGetOffsetNumber(deltaLogCtid));
            ReleaseBuffer(buffer);
            continue;
        }
        OnlineDDLRelOperators* operators = ((OnlineDDLRelOperators*)u_sess->online_ddl_operators);
        bool isPartitioned = operators != NULL && operators->getPartitionAppendMap() != NULL;
        if (isPartitioned) {
            (void)GetDeltaLogDetail(appender, deltaLogTuple, &operation, &oldTupCtid, &oldPartOid);
        } else {
            (void)GetDeltaLogDetail(appender, deltaLogTuple, &operation, &oldTupCtid);
        }

        LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(buffer);
        /* check the type of delta log */

        switch (operation) {
            case ONLINE_DDL_OPERATION_EMPTY: {
                ereport(LOG, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                              errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog empty operation, continue.")));
                continue;
            }
            case ONLINE_DDL_OPERATION_INSERT: {
                ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog insert operation, abort.")));
                continue;
            }
            case ONLINE_DDL_OPERATION_DELETE: {
#ifdef USE_ASSERT_CHECKING
                if (!isPartitioned) {
                    Buffer oldTableBuffer;
                    HeapTuple oldTuple =
                        OnlineDDLGetTupleByCtid(appender->oldRelation, &oldTupCtid, SnapshotAny, &oldTableBuffer);
                    if (!HeapTupleIsValid(oldTuple)) {
                        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                        errmsg("OnlineDDLAppendScanDeltaLog error: failed to get "
                                               "tuple with ctid (%u, %u) from old relation.",
                                               ItemPointerGetBlockNumber(&oldTupCtid),
                                               ItemPointerGetOffsetNumber(&oldTupCtid))));
                    }
                    LockBuffer(oldTableBuffer, BUFFER_LOCK_SHARE);
                    bool valid = HeapTupleSatisfiesVisibility(oldTuple, SnapshotNow, oldTableBuffer);
                    if (valid) {
                        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                        errmsg("OnlineDDLAppendScanDeltaLog error: tuple "
                                               "with ctid (%u, %u) in old relation is "
                                               "still visible when deleting.",
                                               ItemPointerGetBlockNumber(&oldTupCtid),
                                               ItemPointerGetOffsetNumber(&oldTupCtid))));
                    }
                    LockBuffer(oldTableBuffer, BUFFER_LOCK_UNLOCK);
                    ReleaseBuffer(oldTableBuffer);
                    heap_freetuple(oldTuple);
                }
#endif
                /* delete old tuple from new relation */
                if (isPartitioned) {
                    ereport(ONLINE_DDL_LOG_LEVEL,
                            (errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog processing delete operation on "
                                    "partitioned table for tuple (%u, %u).",
                                    ItemPointerGetBlockNumber(&oldTupCtid), ItemPointerGetOffsetNumber(&oldTupCtid))));

                    // Step 1: Use the hash table to find the corresponding new partition OID.
                    Oid newPartOid = GetTempTableFromOldPartition(appender, oldPartOid);
                    if (!OidIsValid(newPartOid)) {
                        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                        errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog cannot find mapping for old "
                                               "partition %u in the hash table.",
                                               oldPartOid)));
                    }

                    // Step 2: Temporarily switch the newRelation in appender to point to the correct partition
                    Relation savedNewRelation = appender->newRelation;
                    appender->newRelation = heap_open(newPartOid, AccessShareLock);

                    // Add check to ensure opening succeeds
                    if (appender->newRelation == NULL) {
                        appender->newRelation = savedNewRelation;  // Restore original relation
                        ereport(WARNING,
                                (errmsg("[Online-DDL] Failed to open new partition relation with OID %u", newPartOid)));
                        continue;
                    }

                    // Step 3: Now perform the final lookup to get the target ctid in the NEW partition.
                    // The 'newPartOid' is passed as an inout parameter, potentially updated by the function.
                    ItemPointerData newTupCtid = OnlineDDLGetTargetCtid(
                        &oldTupCtid, &oldPartOid, appender->ctidMapRelation, appender->ctidMapIndex);

                    // Only attempt deletion if we have a valid target ctid
                    if (ItemPointerIsValid(&newTupCtid)) {
                        // Perform the deletion on the correct partition
                        bool deleted = OnlineDDLDeleteFromNewRelation(appender, &newTupCtid);
                        if (!deleted) {
                            ereport(WARNING, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                              errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog warning: failed to "
                                                     "delete tuple with ctid (%u, %u) from new partition relation %u.",
                                                     ItemPointerGetBlockNumber(&newTupCtid),
                                                     ItemPointerGetOffsetNumber(&newTupCtid), newPartOid)));
                        }
                    } else {
                        ereport(
                            ONLINE_DDL_LOG_LEVEL,
                            (errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog target ctid is invalid for old tuple "
                                    "(%u, %u), may not have been inserted yet.",
                                    ItemPointerGetBlockNumber(&oldTupCtid), ItemPointerGetOffsetNumber(&oldTupCtid))));
                    }
                    // Step 4: Restore the original newRelation in appender
                    heap_close(appender->newRelation, AccessShareLock);
                    appender->newRelation = savedNewRelation;
                } else {
                    ItemPointerData newTupCtid =
                        OnlineDDLGetTargetCtid(&oldTupCtid, appender->ctidMapRelation, appender->ctidMapIndex);
                    // Only attempt deletion if we have a valid target ctid
                    if (ItemPointerIsValid(&newTupCtid)) {
                        bool deleted = OnlineDDLDeleteFromNewRelation(appender, &newTupCtid);
                        if (!deleted) {
                            ereport(WARNING, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                              errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog warning: failed to "
                                                     "delete tuple with ctid (%u, %u) from new relation.",
                                                     ItemPointerGetBlockNumber(&newTupCtid),
                                                     ItemPointerGetOffsetNumber(&newTupCtid))));
                        }
                    } else {
                        ereport(DEBUG1, (errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog target ctid is invalid for "
                                                "old tuple (%u, %u), may not have been inserted yet.",
                                                ItemPointerGetBlockNumber(&oldTupCtid),
                                                ItemPointerGetOffsetNumber(&oldTupCtid))));
                    }
                }
                break;
            }
            default: {
                Assert(0);
                ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                                errmsg("[Online-DDL] OnlineDDLAppendScanDeltaLog error: invalid operation type %u in "
                                       "delta log tuple with ctid (%u, %u).",
                                       operation, ItemPointerGetBlockNumber(deltaLogCtid),
                                       ItemPointerGetOffsetNumber(deltaLogCtid))));
            }
        }
        /* step to next tuple */
        if (CompareItemPointer(&appender->deltaLogScanIdx, deltaLogCtid)) {
            ItemPointerSet(&appender->deltaLogScanIdx, ItemPointerGetBlockNumber(deltaLogCtid),
                           ItemPointerGetOffsetNumber(deltaLogCtid));
        }
        CHECK_FOR_INTERRUPTS();
    }
    /* finish this scan */
    scanFinished = (deltaLogTuple == NULL);
    return scanFinished;
}

static bool OnlineDDLAppendScanOldTable(OnlineDDLAppender* appender, TableScanDesc oldTableScan)
{
    if ((HeapScanDesc)oldTableScan == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLAppendScanOldTable error: oldTableScan is null.")));
    }
    if (((HeapScanDesc)oldTableScan)->rs_base.rs_nblocks == 0) {
        ereport(ONLINE_DDL_LOG_LEVEL,
                (errcode(MOD_ONLINE_DDL), errmsg("[Online-DDL] OnlineDDLAppendScanOldTable notice: old relation "
                                                 "relation is empty, no tuple to process.")));
        return true;
    }
    HeapTuple tuple = NULL;
    bool scanFinished = false;
    uint32 hiOptions = (!XLogIsNeeded()) ? TABLE_INSERT_SKIP_FSM : (TABLE_INSERT_SKIP_FSM | TABLE_INSERT_SKIP_WAL);
    ItemPointerData tmpCtid;
    ItemPointerSet(&tmpCtid, 0, 1);
    while ((tuple = (HeapTuple)tableam_scan_getnexttuple(oldTableScan, ForwardScanDirection)) != NULL) {
        ItemPointer oldTableCtid = &tuple->t_self;
        ereport(ONLINE_DDL_LOG_LEVEL,
                (errmsg("Scan old table tuple:  (%u, %u)", ItemPointerGetBlockNumber(oldTableCtid),
                        ItemPointerGetOffsetNumber(oldTableCtid))));
        bool committed;
        BlockNumber block;
        Buffer buffer;
        HeapTuple copyedTuple = NULL;

        /* check ctid if has been scaned */
        if (!CompareItemPointer(&appender->oldTableScanIdx, oldTableCtid)) {
            ereport(
                ONLINE_DDL_LOG_LEVEL,
                (errcode(MOD_ONLINE_DDL),
                 errmsg(
                     "[Online-DDL] OnlineDDLAppendScanOldTable notice: tuple with ctid (%u, %u) has been scaned, skip.",
                     ItemPointerGetBlockNumber(oldTableCtid), ItemPointerGetOffsetNumber(oldTableCtid))));
            continue;
        }

#ifdef USE_ASSERT_CHECKING
        Assert(CompareItemPointer(&tmpCtid, oldTableCtid) || AreItemPointersAdjacent(&tmpCtid, oldTableCtid));
        tmpCtid = *oldTableCtid;
#endif

        block = ItemPointerGetBlockNumber(oldTableCtid);
        buffer = ReadBuffer(appender->oldRelation, block);
        LockBuffer(buffer, BUFFER_LOCK_SHARE);
        committed = CheckTupleVisibile(tuple, buffer);
        /* If the tuple is aborted, skip it. */
        if (!committed) {
            LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
            ereport(ONLINE_DDL_LOG_LEVEL,
                    (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                     errmsg("[Online-DDL] OnlineDDLAppendScanOldTable tuple with ctid (%u, %u) in old relation is not "
                            "committed, skip.",
                            ItemPointerGetBlockNumber(oldTableCtid), ItemPointerGetOffsetNumber(oldTableCtid))));
            ItemPointerSet(&appender->oldTableScanIdx, ItemPointerGetBlockNumber(oldTableCtid),
                           ItemPointerGetOffsetNumber(oldTableCtid));
            ReleaseBuffer(buffer);
            continue;
        }

        /* If the tuple is visible, insert it into the new relation. */
        copyedTuple = heapCopyTuple(tuple, appender->oldRelation->rd_att, NULL);
        LockBuffer(buffer, BUFFER_LOCK_UNLOCK);
        ReleaseBuffer(buffer);

        OnlineDDLInsertIntoNewRelation(appender, copyedTuple, hiOptions);

        if (CompareItemPointer(&appender->oldTableScanIdx, oldTableCtid)) {
            ItemPointerSet(&appender->oldTableScanIdx, ItemPointerGetBlockNumber(oldTableCtid),
                           ItemPointerGetOffsetNumber(oldTableCtid));
        }
        CHECK_FOR_INTERRUPTS();
    }

    if (appender->newRelation) {
        /* If we skipped writing WAL, then we need to sync the heap. */
        if (((hiOptions & TABLE_INSERT_SKIP_WAL) || enable_heap_bcm_data_replication()) &&
            !RelationIsSegmentTable(appender->newRelation)) {
            heap_sync(appender->newRelation);
        }
        /*
         * After the temporary table is rewritten, the relfilenode changes.
         * We need to find new TmptableCacheEntry with new relfilenode.
         * Then set new auto_increment counter value in new TmptableCacheEntry.
         */
        CopyTempAutoIncrement(appender->oldRelation, appender->newRelation);
    }

    /* finish this scan */
    scanFinished = (tuple == NULL);
    return scanFinished;
}

bool OnlineDDLAppendForNormalTable(OnlineDDLAppender* appender)
{
    Relation oldRelation = appender->oldRelation;
    Relation newRelation = appender->newRelation;

    /* init scan desc */
    TableScanDesc deltaLogScan;
    deltaLogScan = tableam_scan_begin(appender->deltaRelation, SnapshotAny, 0, NULL);
    TableScanDesc oldTableScan;
    oldTableScan = tableam_scan_begin(oldRelation, SnapshotAny, 0, NULL);

    bool firstScan = true;
    bool deltaLogScanFinished = true;
    bool oldTableScanFinished = true;

    /* scan delta log and old table */
    while (true) {
        int deltaLogRemainPages = 0;
        int oldTableRemainPages = 0;
        GetRemainPages(appender, &deltaLogRemainPages, &oldTableRemainPages);
        if (deltaLogRemainPages <= ONLINE_DDL_APPENDER_MAX_FINISH_PAGES - oldTableRemainPages && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] relation %s finish data catchup by reach max finish pages: %d, "
                                 "delta log remain pages: %d, old table remain pages: %d.",
                                 oldRelation->rd_rel->relname.data, ONLINE_DDL_APPENDER_MAX_FINISH_PAGES,
                                 deltaLogRemainPages, oldTableRemainPages)));
            break;
        }
        if (appender->deltaLogScanTimes >= ONLINE_DDL_APPENDER_MAX_SCAN_TIME &&
            appender->oldTableScanTimes >= ONLINE_DDL_APPENDER_MAX_SCAN_TIME && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] relation %s finish catchup by reach max scan times: %d, "
                                 "delta log remain pages: %d, old table remain pages: %d.",
                                 oldRelation->rd_rel->relname.data, ONLINE_DDL_APPENDER_MAX_SCAN_TIME,
                                 deltaLogRemainPages, oldTableRemainPages)));
            break;
        }
        if (appender->deltaLogScanTimes > 0 && deltaLogScanFinished) {
            HeapScanDesc heapScan = (HeapScanDesc)deltaLogScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumber(&appender->deltaLogScanIdx);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(appender->deltaRelation);
            if (heapScan->rs_base.rs_nblocks != 0) {
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            }
            heapScan->rs_base.rs_inited = true;
        }
        if (appender->oldTableScanTimes > 0 && oldTableScanFinished) {
            HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldRelation);
            if (heapScan->rs_base.rs_nblocks != 0) {
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            }
            heapScan->rs_base.rs_inited = true;
        }
        CHECK_FOR_INTERRUPTS();
        deltaLogScanFinished = OnlineDDLAppendScanDeltaLog(appender, deltaLogScan);
        appender->deltaLogScanTimes += (deltaLogScanFinished ? 1 : 0);
        oldTableScanFinished = OnlineDDLAppendScanOldTable(appender, oldTableScan);
        appender->oldTableScanTimes += (oldTableScanFinished ? 1 : 0);
        firstScan = false;
    }

    ereport(NOTICE, (errmsg("Online DDL get AccessExclusiveLock for relation %s before commit, "
                            "append data for the last time.",
                            oldRelation->rd_rel->relname.data)));

    /* Get AccessExclusiveLock before commit. */
    LockRelation(oldRelation, AccessExclusiveLock);
    UnlockRelation(oldRelation, ShareUpdateExclusiveLock);

    /* reinit scanDesc */
    {
        HeapScanDesc heapScan = (HeapScanDesc)deltaLogScan;
        Assert(!heapScan->rs_base.rs_inited);
        heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumber(&appender->deltaLogScanIdx);
        heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(appender->deltaRelation);
        if (heapScan->rs_base.rs_nblocks != 0) {
            heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
        }
        heapScan->rs_base.rs_inited = true;
    }
    {
        HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
        Assert(!heapScan->rs_base.rs_inited);
        heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
        heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldRelation);
        if (heapScan->rs_base.rs_nblocks != 0) {
            heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
        }
        heapScan->rs_base.rs_inited = true;
    }

    /* Append for the last time. */
    OnlineDDLAppendScanDeltaLog(appender, deltaLogScan);
    OnlineDDLAppendScanOldTable(appender, oldTableScan);

    tableam_scan_end(deltaLogScan);
    tableam_scan_end(oldTableScan);

    return true;
}

bool OnlineDDLAppendForPartitionedTable(OnlineDDLAppender* appender)
{
    // For partitioned tables, process delta log and all partitions together
    TableScanDesc deltaLogScan = tableam_scan_begin(appender->deltaRelation, SnapshotAny, 0, NULL);
    List* oldTableScanList = NIL;
    ListCell* oldCell = NULL;
    ListCell* newCell = NULL;
    ListCell* cell = NULL;
    List* oldPartRelationList = NIL;
    List* newPartRelationList = NIL;

    // Open all partition relations
    forboth(oldCell, appender->oldPartitionList, newCell, appender->newOidList)
    {
        Relation oldPartRelation = (Relation)lfirst(oldCell);
        Oid newPartOid = lfirst_oid(newCell);
        // Attempt to open new partition table
        Relation newPartRelation = heap_open(newPartOid, NoLock);
        // Check if opening new partition table was successful
        if (newPartRelation == NULL) {
            // If opening fails, log a warning and skip this partition
            ereport(WARNING, (errmsg("[Online-DDL] Failed to open new partition with OID %u", newPartOid),
                              errhint("The partition may have been dropped or renamed during Online DDL process")));
            continue;
        }
        oldPartRelationList = lappend(oldPartRelationList, oldPartRelation);
        newPartRelationList = lappend(newPartRelationList, newPartRelation);
        // Store the mapping between old and new partition in the hash table
        AddPartitionOidMapping(appender, RelationGetRelid(oldPartRelation), newPartOid);
    }

    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        TableScanDesc oldTableScan = tableam_scan_begin(oldPartRelation, SnapshotAny, 0, NULL);
        oldTableScanList = lappend(oldTableScanList, oldTableScan);
    }

    bool deltaLogScanFinished = true;
    bool firstScan = true;
    // Maintain separate scan counter for each partition
    List* oldTableScanTimesList = NIL;
    foreach (cell, oldPartRelationList) {
        int* scanTimes = (int*)palloc(sizeof(int));
        *scanTimes = 0;
        oldTableScanTimesList = lappend(oldTableScanTimesList, scanTimes);
    }

    // Unified while loop to handle delta log and all partitions
    while (true) {
        int deltaLogRemainPages = 0;
        int totalOldTableRemainPages = 0;

        if (deltaLogRemainPages <= ONLINE_DDL_APPENDER_MAX_FINISH_PAGES - totalOldTableRemainPages && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] partitioned table finish data catchup by reach max finish pages: "
                                 "delta log %d, old tables %d",
                                 deltaLogRemainPages, totalOldTableRemainPages)));
            break;
        }

        if (appender->deltaLogScanTimes >= ONLINE_DDL_APPENDER_MAX_SCAN_TIME && !firstScan) {
            ereport(LOG,
                    (errmsg("[Online-DDL] partitioned table finish catchup by reach max scan times for delta log: %d",
                            ONLINE_DDL_APPENDER_MAX_SCAN_TIME)));
            break;
        }

        // Scan delta log
        if (appender->deltaLogScanTimes > 0 && deltaLogScanFinished) {
            HeapScanDesc heapScan = (HeapScanDesc)deltaLogScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumber(&appender->deltaLogScanIdx);
            heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(appender->deltaRelation);
            heapScan->rs_base.rs_inited = true;
        }

        deltaLogScanFinished = OnlineDDLAppendScanDeltaLog(appender, deltaLogScan);
        appender->deltaLogScanTimes += (deltaLogScanFinished ? 1 : 0);

        // Iterate through all partitions and scan data for each partition
        ListCell* oldPartRelCell = NULL;
        ListCell* newPartRelCell = NULL;
        ListCell* oldPartScanCell = NULL;
        ListCell* oldPartScanTimesCell = NULL;
        forfour(oldPartRelCell, oldPartRelationList,          // old partition
                newPartRelCell, newPartRelationList,          // temp relation
                oldPartScanCell, oldTableScanList,            // old table scan
                oldPartScanTimesCell, oldTableScanTimesList)  // scan times for each partition
        {
            Relation oldPartRelation = (Relation)lfirst(oldPartRelCell);
            Relation newPartRelation = (Relation)lfirst(newPartRelCell);
            TableScanDesc oldTableScan = (TableScanDesc)lfirst(oldPartScanCell);
            int* oldTableScanTimes = (int*)lfirst(oldPartScanTimesCell);

            // Get the starting scan position for this partition from partitionAppendMap
            OnlineDDLRelOperators* operators = ((OnlineDDLRelOperators*)u_sess->online_ddl_operators);
            ItemPointerData partitionScanIdx = {{0, 0}, 0};
            if (operators != NULL) {
                partitionScanIdx = operators->getEndCtidForPartition(oldPartRelation->rd_id);
            } else {
                ItemPointerSet(&partitionScanIdx, 0, 1);
            }

            // Temporarily save and replace the relation and scan index in appender
            Relation savedOldRelation = appender->oldRelation;
            Relation savedNewRelation = appender->newRelation;
            ItemPointerData savedOldTableScanIdx = appender->oldTableScanIdx;

            appender->oldRelation = oldPartRelation;
            appender->newRelation = newPartRelation;
            appender->oldTableScanIdx = partitionScanIdx;

            bool oldTableScanFinished = true;

            if (*oldTableScanTimes > 0 && oldTableScanFinished) {
                HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
                Assert(!heapScan->rs_base.rs_inited);
                heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumber(&appender->oldTableScanIdx);
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
                heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldPartRelation);
                heapScan->rs_base.rs_inited = true;
            }

            oldTableScanFinished = OnlineDDLAppendScanOldTable(appender, oldTableScan);
            *oldTableScanTimes += (oldTableScanFinished ? 1 : 0);

            // Restore the relation and scan index in appender
            appender->oldRelation = savedOldRelation;
            appender->newRelation = savedNewRelation;
            appender->oldTableScanIdx = savedOldTableScanIdx;
        }

        firstScan = false;
    }

    ereport(NOTICE, (errmsg("Online DDL get AccessExclusiveLock for partitioned table before commit, "
                            "append data for the last time.")));

    // Get AccessExclusiveLock before commit for all partitions
    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        LockRelation(oldPartRelation, AccessExclusiveLock);
    }

    // Append for the last time for delta log
    {
        HeapScanDesc heapScan = (HeapScanDesc)deltaLogScan;
        Assert(!heapScan->rs_base.rs_inited);
        heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumber(&appender->deltaLogScanIdx);
        heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(appender->deltaRelation);
        if (heapScan->rs_base.rs_nblocks != 0) {
            heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
        }
        heapScan->rs_base.rs_inited = true;
    }
    OnlineDDLAppendScanDeltaLog(appender, deltaLogScan);

    // Append for the last time for each partition - using same structure as main loop
    ListCell* oldPartRelCell = NULL;
    ListCell* newPartRelCell = NULL;
    ListCell* oldPartScanCell = NULL;
    forthree(oldPartRelCell, oldPartRelationList,  // old partition
             newPartRelCell, newPartRelationList,  // temp relation
             oldPartScanCell, oldTableScanList)    // old table scan
    {
        Relation oldPartRelation = (Relation)lfirst(oldPartRelCell);
        Relation newPartRelation = (Relation)lfirst(newPartRelCell);
        TableScanDesc oldTableScan = (TableScanDesc)lfirst(oldPartScanCell);

        // Get the starting scan position for this partition from partitionAppendMap
        OnlineDDLRelOperators* operators = ((OnlineDDLRelOperators*)u_sess->online_ddl_operators);
        ItemPointerData partitionScanIdx = {{0, 0}, 0};
        if (operators != NULL) {
            partitionScanIdx = operators->getEndCtidForPartition(oldPartRelation->rd_id);
        } else {
            ItemPointerSet(&partitionScanIdx, 0, 1);
        }

        // Temporarily save and replace the relation and scan index in appender
        Relation savedOldRelation = appender->oldRelation;
        Relation savedNewRelation = appender->newRelation;
        ItemPointerData savedOldTableScanIdx = appender->oldTableScanIdx;

        appender->oldRelation = oldPartRelation;
        appender->newRelation = newPartRelation;
        appender->oldTableScanIdx = partitionScanIdx;

        // Reinit scanDesc for final scan
        {
            HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldPartRelation);
            if (heapScan->rs_base.rs_nblocks != 0) {
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            }
            heapScan->rs_base.rs_inited = true;
        }

        // Append for the last time for this partition
        OnlineDDLAppendScanOldTable(appender, oldTableScan);

        // Restore the relation and scan index in appender
        appender->oldRelation = savedOldRelation;
        appender->newRelation = savedNewRelation;
        appender->oldTableScanIdx = savedOldTableScanIdx;
    }

    // Clean up log scanner
    tableam_scan_end(deltaLogScan);
    foreach (cell, oldTableScanList) {
        TableScanDesc oldTableScan = (TableScanDesc)lfirst(cell);
        tableam_scan_end(oldTableScan);
    }

    // Free scan counter
    foreach (cell, oldTableScanTimesList) {
        int* scanTimes = (int*)lfirst(cell);
        pfree(scanTimes);
    }
    list_free(oldTableScanTimesList);

    // Close partition relations
    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        heap_close(oldPartRelation, NoLock);
    }
    foreach (cell, newPartRelationList) {
        Relation newPartRelation = (Relation)lfirst(cell);
        heap_close(newPartRelation, NoLock);
    }

    return true;
}

bool OnlineDDLAppend(OnlineDDLAppender* appender)
{
    bool isPartitioned = appender->oldRelation == NULL && appender->newRelation == NULL &&
                         appender->oldPartitionList != NIL && appender->newOidList != NIL;
    if (isPartitioned) {
        Assert(appender->oldRelation == NULL && appender->oldPartitionList != NIL);
        Assert(appender->newRelation == NULL && appender->newOidList != NIL);
        return OnlineDDLAppendForPartitionedTable(appender);
    } else {
        Assert(appender->oldRelation != NULL && appender->newRelation != NULL);
        Assert(appender->oldPartitionList == NIL && appender->newOidList == NIL);
        return OnlineDDLAppendForNormalTable(appender);
    }
}

bool OnlineDDLOnlyCheckForNormalTable(OnlineDDLAppender* appender)
{
    Relation oldRelation = appender->oldRelation;
    Relation newRelation = NULL;

    /* init scan desc */
    TableScanDesc oldTableScan;
    oldTableScan = tableam_scan_begin(oldRelation, SnapshotAny, 0, NULL);

    bool firstScan = true;
    bool oldTableScanFinished = true;

    /* scan delta log and old table */
    while (true) {
        int deltaLogRemainPages = 0;
        int oldTableRemainPages = 0;
        GetRemainPages(appender, &deltaLogRemainPages, &oldTableRemainPages);
        if (deltaLogRemainPages <= ONLINE_DDL_APPENDER_MAX_FINISH_PAGES - oldTableRemainPages && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] relation %s finish data catchup by reach max finish pages: %d, "
                                 "old table remain pages: %d.",
                                 oldRelation->rd_rel->relname.data, ONLINE_DDL_APPENDER_MAX_FINISH_PAGES,
                                 oldTableRemainPages)));
            break;
        }
        if (appender->oldTableScanTimes >= ONLINE_DDL_APPENDER_MAX_SCAN_TIME && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] relation %s finish catchup by reach max scan times: %d, "
                                 "delta log remain pages: %d, old table remain pages: %d.",
                                 oldRelation->rd_rel->relname.data, ONLINE_DDL_APPENDER_MAX_SCAN_TIME,
                                 deltaLogRemainPages, oldTableRemainPages)));
            break;
        }

        /* reinit scanDesc */
        if (appender->oldTableScanTimes > 0 && oldTableScanFinished) {
            HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldRelation);
            if (heapScan->rs_base.rs_nblocks != 0) {
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            }
            heapScan->rs_base.rs_inited = true;
        }
        oldTableScanFinished = OnlineDDLAppendScanOldTable(appender, oldTableScan);
        appender->oldTableScanTimes += (oldTableScanFinished ? 1 : 0);
        firstScan = false;
    }
    ereport(NOTICE, (errmsg("Online DDL relation %s get AccessExclusiveLock before commit, "
                            "start to append for the last time.",
                            oldRelation->rd_rel->relname.data)));

    /* Get AccessExclusiveLock before commit. */
    LockRelation(oldRelation, AccessExclusiveLock);
    UnlockRelation(oldRelation, ShareUpdateExclusiveLock);

    /* reinit scanDesc */
    {
        HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
        Assert(!heapScan->rs_base.rs_inited);
        heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
        heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldRelation);
        if (heapScan->rs_base.rs_nblocks != 0) {
            heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
        }
        heapScan->rs_base.rs_inited = true;
    }

    /* Append for the last time. */
    OnlineDDLAppendScanOldTable(appender, oldTableScan);
    tableam_scan_end(oldTableScan);

    return true;
}

bool OnlineDDLOnlyCheckForPartitionedTable(OnlineDDLAppender* appender)
{
    // For partitioned tables, process all partitions together
    List* oldTableScanList = NIL;
    ListCell* oldCell = NULL;
    ListCell* newCell = NULL;
    ListCell* cell = NULL;
    List* oldPartRelationList = NIL;
    List* newPartRelationList = NIL;

    // Open all partition relations
    forboth(oldCell, appender->oldPartitionList, newCell, appender->newOidList)
    {
        Relation oldPartRelation = (Relation)lfirst(oldCell);
        Oid newPartOid = lfirst_oid(newCell);
        // Attempt to open new partition table
        Relation newPartRelation = heap_open(newPartOid, NoLock);
        // Check if opening new partition table was successful
        if (newPartRelation == NULL) {
            // If opening fails, log a warning and skip this partition
            ereport(WARNING, (errmsg("[Online-DDL] Failed to open new partition with OID %u", newPartOid),
                              errhint("The partition may have been dropped or renamed during Online DDL process")));
            continue;
        }
        oldPartRelationList = lappend(oldPartRelationList, oldPartRelation);
        newPartRelationList = lappend(newPartRelationList, newPartRelation);
        // Store the mapping between old and new partition in the hash table
        AddPartitionOidMapping(appender, RelationGetRelid(oldPartRelation), newPartOid);
    }

    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        TableScanDesc oldTableScan = tableam_scan_begin(oldPartRelation, SnapshotAny, 0, NULL);
        oldTableScanList = lappend(oldTableScanList, oldTableScan);
    }

    bool firstScan = true;

    /* scan old tables for all partitions */
    while (true) {
        // Calculate total remaining pages across all partitions
        int totalOldTableRemainPages = 0;
        foreach (cell, oldPartRelationList) {
            Relation oldPartRelation = (Relation)lfirst(cell);
            int remainPages = 0;
            // Since GetRemainPages is designed for single relation, we'll calculate based on blocks
            remainPages = RelationGetNumberOfBlocks(oldPartRelation);
            totalOldTableRemainPages += remainPages;
        }

        // Check if we should finish based on remaining pages
        if (totalOldTableRemainPages <= ONLINE_DDL_APPENDER_MAX_FINISH_PAGES && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] partitioned table finish data catchup by reach max finish pages: "
                                 "old tables total remain pages: %d.",
                                 totalOldTableRemainPages)));
            break;
        }

        // Check if we should finish based on scan times
        if (appender->oldTableScanTimes >= ONLINE_DDL_APPENDER_MAX_SCAN_TIME && !firstScan) {
            ereport(LOG, (errmsg("[Online-DDL] partitioned table finish catchup by reach max scan times: %d, "
                                 "old table remain pages: %d.",
                                 ONLINE_DDL_APPENDER_MAX_SCAN_TIME, totalOldTableRemainPages)));
            break;
        }

        // Iterate through all partitions and scan data for each partition
        ListCell* oldPartRelCell = NULL;
        ListCell* newPartRelCell = NULL;
        ListCell* oldPartScanCell = NULL;

        forthree(oldPartRelCell, oldPartRelationList,  // old partition
                 newPartRelCell, newPartRelationList,  // temp relation
                 oldPartScanCell, oldTableScanList)    // old table scan
        {
            Relation oldPartRelation = (Relation)lfirst(oldPartRelCell);
            Relation newPartRelation = (Relation)lfirst(newPartRelCell);
            TableScanDesc oldTableScan = (TableScanDesc)lfirst(oldPartScanCell);

            // Get the starting scan position for this partition from partitionAppendMap
            OnlineDDLRelOperators* operators = ((OnlineDDLRelOperators*)u_sess->online_ddl_operators);
            ItemPointerData partitionScanIdx = {{0, 0}, 0};
            if (operators != NULL) {
                partitionScanIdx = operators->getEndCtidForPartition(oldPartRelation->rd_id);
            } else {
                ItemPointerSet(&partitionScanIdx, 0, 1);
            }

            // Temporarily save and replace the relation and scan index in appender
            Relation savedOldRelation = appender->oldRelation;
            Relation savedNewRelation = appender->newRelation;
            ItemPointerData savedOldTableScanIdx = appender->oldTableScanIdx;

            appender->oldRelation = oldPartRelation;
            appender->newRelation = newPartRelation;
            appender->oldTableScanIdx = partitionScanIdx;

            bool oldTableScanFinished = true;

            if (appender->oldTableScanTimes > 0 && oldTableScanFinished) {
                HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
                Assert(!heapScan->rs_base.rs_inited);
                heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
                heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldPartRelation);
                if (heapScan->rs_base.rs_nblocks != 0) {
                    heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
                }
                heapScan->rs_base.rs_inited = true;
            }

            oldTableScanFinished = OnlineDDLAppendScanOldTable(appender, oldTableScan);
            appender->oldTableScanTimes += (oldTableScanFinished ? 1 : 0);

            // Restore the relation and scan index in appender
            appender->oldRelation = savedOldRelation;
            appender->newRelation = savedNewRelation;
            appender->oldTableScanIdx = savedOldTableScanIdx;
        }

        firstScan = false;
    }

    ereport(NOTICE, (errmsg("Online DDL get AccessExclusiveLock for partitioned table before commit, start to append "
                            "for the last time.")));

    // Get AccessExclusiveLock before commit for all partitions
    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        LockRelation(oldPartRelation, AccessExclusiveLock);
    }

    // Append for the last time for each partition - using same structure as main loop
    ListCell* oldPartRelCell = NULL;
    ListCell* newPartRelCell = NULL;
    ListCell* oldPartScanCell = NULL;
    forthree(oldPartRelCell, oldPartRelationList,  // old partition
             newPartRelCell, newPartRelationList,  // temp relation
             oldPartScanCell, oldTableScanList)    // old table scan
    {
        Relation oldPartRelation = (Relation)lfirst(oldPartRelCell);
        Relation newPartRelation = (Relation)lfirst(newPartRelCell);
        TableScanDesc oldTableScan = (TableScanDesc)lfirst(oldPartScanCell);

        // Get the starting scan position for this partition from partitionAppendMap
        OnlineDDLRelOperators* operators = ((OnlineDDLRelOperators*)u_sess->online_ddl_operators);
        ItemPointerData partitionScanIdx = {{0, 0}, 0};
        if (operators != NULL) {
            partitionScanIdx = operators->getEndCtidForPartition(oldPartRelation->rd_id);
        } else {
            ItemPointerSet(&partitionScanIdx, 0, 1);
        }

        // Temporarily save and replace the relation and scan index in appender
        Relation savedOldRelation = appender->oldRelation;
        Relation savedNewRelation = appender->newRelation;
        ItemPointerData savedOldTableScanIdx = appender->oldTableScanIdx;

        appender->oldRelation = oldPartRelation;
        appender->newRelation = newPartRelation;
        appender->oldTableScanIdx = partitionScanIdx;

        // Reinit scanDesc for final scan
        {
            HeapScanDesc heapScan = (HeapScanDesc)oldTableScan;
            Assert(!heapScan->rs_base.rs_inited);
            heapScan->rs_base.rs_cblock = ItemPointerGetBlockNumberNoCheck(&appender->oldTableScanIdx);
            heapScan->rs_base.rs_nblocks = RelationGetNumberOfBlocks(oldPartRelation);
            if (heapScan->rs_base.rs_nblocks != 0) {
                heapgetpage((TableScanDesc)heapScan, heapScan->rs_base.rs_cblock);
            }
            heapScan->rs_base.rs_inited = true;
        }

        // Append for the last time for this partition
        OnlineDDLAppendScanOldTable(appender, oldTableScan);

        // Restore the relation and scan index in appender
        appender->oldRelation = savedOldRelation;
        appender->newRelation = savedNewRelation;
        appender->oldTableScanIdx = savedOldTableScanIdx;
    }

    // Clean up old table scanners
    foreach (cell, oldTableScanList) {
        TableScanDesc oldTableScan = (TableScanDesc)lfirst(cell);
        tableam_scan_end(oldTableScan);
    }

    // Close partition relations
    foreach (cell, oldPartRelationList) {
        Relation oldPartRelation = (Relation)lfirst(cell);
        heap_close(oldPartRelation, NoLock);
    }
    foreach (cell, newPartRelationList) {
        Relation newPartRelation = (Relation)lfirst(cell);
        heap_close(newPartRelation, NoLock);
    }

    return true;
}

bool OnlineDDLOnlyCheck(OnlineDDLAppender* appender)
{
    bool isPartitioned = appender->oldRelation == NULL && appender->newRelation == NULL &&
                         appender->oldPartitionList != NIL && appender->newOidList != NIL;
    if (isPartitioned) {
        Assert(appender->oldRelation == NULL && appender->oldPartitionList != NIL);
        Assert(appender->newRelation == NULL && appender->newOidList != NIL);
        return OnlineDDLOnlyCheckForPartitionedTable(appender);
    } else {
        Assert(appender->oldRelation != NULL && appender->newRelation != NULL);
        Assert(appender->oldPartitionList == NIL && appender->newOidList == NIL);
        return OnlineDDLOnlyCheckForNormalTable(appender);
    }
}

/*
 * Executor state preparation for evaluation of constraint expressions,
 * indexes and triggers.
 *
 * This is based on similar code in copy.c
 */
static EState* create_estate_for_relation(Relation rel)
{
    EState* estate;
    ResultRelInfo* resultRelInfo;
    RangeTblEntry* rte;

    estate = CreateExecutorState();

    rte = makeNode(RangeTblEntry);
    rte->rtekind = RTE_RELATION;
    rte->relid = RelationGetRelid(rel);
    rte->relkind = rel->rd_rel->relkind;
    estate->es_range_table = list_make1(rte);

    resultRelInfo = makeNode(ResultRelInfo);
    InitResultRelInfo(resultRelInfo, rel, 1, 0);

    estate->es_result_relations = resultRelInfo;
    estate->es_num_result_relations = 1;
    estate->es_result_relation_info = resultRelInfo;
    estate->es_output_cid = GetCurrentCommandId(true);

    /* Triggers might need a slot */
    if (resultRelInfo->ri_TrigDesc)
        estate->es_trig_tuple_slot = ExecInitExtraTupleSlot(estate, rel->rd_tam_ops);

    /* Prepare to catch AFTER triggers. */
    AfterTriggerBeginQuery();

    return estate;
}

/**
 * @brief Clean up the executor state and related resources
 *
 * @param estate Pointer to the executor state (EState) to be cleaned up
 * @param epqstate Pointer to the EvalPlanQual state to be cleaned up
 *
 */
static inline void CleanupEstate(EState* estate, EPQState* epqstate)
{
    ExecCloseIndices(estate->es_result_relation_info);
    /* free the fakeRelationCache */
    if (estate->esfRelations != NULL) {
        FakeRelationCacheDestroy(estate->esfRelations);
    }
    PopActiveSnapshot();

    /* Handle queued AFTER triggers. */
    AfterTriggerEndQuery(estate);

    EvalPlanQualEnd(epqstate);
    ExecResetTupleTable(estate->es_tupleTable, false);
    FreeExecutorState(estate);

    CommandCounterIncrement();
}
