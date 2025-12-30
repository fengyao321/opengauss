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
 * online_ddl.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/optimizer/commands/online_ddl/online_ddl.cpp
 *
 * ---------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"
#include "catalog/pg_class.h"
#include "catalog/namespace.h"
#include "commands/tablecmds.h"
#include "nodes/parsenodes_common.h"
#include "utils/mem_snapshot.h"
#include "utils/palloc.h"
#include "utils/rel.h"

#include "commands/online_ddl_ctid_map.h"
#include "commands/online_ddl_globalhash.h"
#include "commands/online_ddl_util.h"
#include "commands/online_ddl.h"

static constexpr int ONLINE_DDL_ALTER_TABLE_TYPE_COUNT = 2;

AlterTableType online_ddl_alter_table_types[ONLINE_DDL_ALTER_TABLE_TYPE_COUNT] = {
    AT_AlterColumnType, /* alter column type */
    AT_SetRelOptions    /* set reloptions */
};

static constexpr int ONLINE_DDL_RELATION_COUNT = 1;

char online_ddl_relations[ONLINE_DDL_RELATION_COUNT] = {
    RELKIND_RELATION /* temp schema for online ddl */
};

void OnlineDDLinit()
{
    if (g_instance.online_ddl_cxt.isInited) {
        return;
    }
    if (g_instance.online_ddl_cxt.context == NULL) {
        g_instance.online_ddl_cxt.context =
            AllocSetContextCreate(g_instance.instance_context, "Online DDL Context", ALLOCSET_DEFAULT_MINSIZE,
                                  ALLOCSET_DEFAULT_INITSIZE, ALLOCSET_DEFAULT_MAXSIZE, SHARED_CONTEXT);
    }
    MemoryContext oldCxt = MemoryContextSwitchTo(g_instance.online_ddl_cxt.context);
    initDDLGlobalHash(g_instance.online_ddl_cxt.context);
    MemoryContextSwitchTo(oldCxt);
    g_instance.online_ddl_cxt.isInited = true;
}

void OnlineDDLDestroy()
{
    if (g_instance.online_ddl_cxt.isInited) {
        g_instance.online_ddl_cxt.isInited = false;
        MemoryContextDelete(g_instance.online_ddl_cxt.context);
    }
}

/**
 * Check if the online DDL operation is feasible.
 *
 * @param wqueue The work queue for online DDL operations.
 * @param relation The relation on which the operation is to be performed.
 * @param cmds The list of commands to be executed.
 * @param lockmode The lock mode required for the operation.
 * @return true if the operation is feasible, false otherwise.
 */
OnlineDDLType OnlineDDLCheckFeasible(List** wqueue, Relation relation, List* cmds, LOCKMODE lockmode)
{
    /* check need rewrite */
    ListCell* ltab = NULL;
    bool rewriteOpt = false;
    bool checkOpt = false;
    bool unsupportOpt = false;
    AlterTableType errorType = (AlterTableType)0;
    foreach (ltab, *wqueue) {
        AlteredTableInfo* tab = (AlteredTableInfo*)lfirst(ltab);
        rewriteOpt |= tab->rewrite;
        checkOpt |= (tab->constraints != NIL || tab->new_notnull);
    }

    bool allowed = false;
    for (int pass = 0; pass < AT_NUM_PASSES; pass++) {
        ltab = NULL;
        foreach (ltab, *wqueue) {
            AlteredTableInfo* tab = (AlteredTableInfo*)lfirst(ltab);
            List* subcmds = tab->subcmds[pass];
            Relation rel;
            ListCell* lcmd = NULL;
            if (subcmds == NIL) {
                continue;
            }

            /*
             * Appropriate lock was obtained by phase 1, needn't get it again
             */
            rel = relation_open(tab->relid, NoLock);
            foreach (lcmd, subcmds) {
                AlterTableCmd* cmd = (AlterTableCmd*)lfirst(lcmd);
                switch (cmd->subtype) {
                    case AT_AlterColumnType: {
                        allowed = true;
                        break;
                    }
                    case AT_AddConstraint:
                    case AT_AddConstraintRecurse:
                    case AT_ReAddConstraint: {
                        allowed = true;
                        checkOpt |= allowed;
                        break;
                    }
                    case AT_ResetRelOptions:   /* RESET (...) */
                    case AT_ReplaceRelOptions: /* replace entire option list */
                    case AT_SetRelOptions: {   /* SET (...) */
                        /* check set reloptions feasible */
                        bool feasible =
                            OnlineDDLCheckSetCompressOptFeasible(rel, (List*)cmd->def, cmd->subtype, lockmode, tab);
                        allowed |= feasible;
                        rewriteOpt |= allowed;
                        break;
                    }
                    case AT_SetNotNull: { /* ALTER COLUMN SET NOT NULL */
                        bool feasible = OnlineDDLCheckSetNotNullFeasible(rel, cmd->name, lockmode);
                        allowed |= feasible;
                        checkOpt |= allowed;
                        break;
                    }
                    case AT_ModifyColumn: { /* MODIFY column NOT NULL */
                        bool feasible = OnlineDDLCheckAlterModifyColumnFeasible(tab, rel, cmd);
                        allowed |= feasible;
                        checkOpt |= allowed;
                        break;
                    }
                    case AT_UnusableIndex:
                    case AT_AddIndex:
                    case AT_ReAddIndex:
                    case AT_AddIndexConstraint: {
                        unsupportOpt = true;
                        errorType = cmd->subtype;
                        break;
                    }
                    default: {
                        break;
                    }
                }
                if (unsupportOpt) {
                    break;
                }
            }
            relation_close(rel, NoLock);
        }
    }

    if (unsupportOpt) {
        ereport(NOTICE, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                         errmsg("Online DDL operation is not supported for command types, type: %d, "
                                "do it without online ddl.",
                                errorType)));
        return ONLINE_DDL_INVALID;
    }

    if (!rewriteOpt && !checkOpt) {
        ereport(NOTICE, (errcode(MOD_ONLINE_DDL), errmsg("Current command doestn't need to rewrite table.")));
        return ONLINE_DDL_INVALID;
    }

    if (!allowed) {
        ereport(NOTICE, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                         errmsg("Online DDL operation is not supported for this command type, type: %d, "
                                "do it without online ddl.",
                                cmds->type)));
        return ONLINE_DDL_INVALID;
    }

    /* check relation type */
    allowed = false;
    for (int i = 0; i < ONLINE_DDL_RELATION_COUNT; i++) {
        if (relation->rd_rel->relkind == online_ddl_relations[i]) {
            allowed = true;
            break;
        }
    }
    if (!allowed) {
        ereport(NOTICE, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                         errmsg("Online DDL operation is not supported for this relind, type: %c, "
                                "do it without online ddl.",
                                relation->rd_rel->relkind)));
        return ONLINE_DDL_INVALID;
    }
    return rewriteOpt ? ONLINE_DDL_REWRITE : ONLINE_DDL_CHECK;
}
void OnlineDDLCreateTempSchema(Relation relation)
{
    OnlineDDLRelOperators* operators = RelationGetOnlineDDLOperators(relation);
    TransactionId xid = operators->getStartXid();
    RelFileNode relFileNode = relation->rd_node;
    Oid spcNode = relFileNode.spcNode;
    Oid dbNode = relFileNode.dbNode;
    Oid relId = relation->rd_id;
    uint2 bucketNode = relFileNode.bucketNode;

    char tempSchemaName[NAMEDATALEN] = {0};
    errno_t rc = snprintf_s(tempSchemaName, NAMEDATALEN, NAMEDATALEN - 1, "online_ddl_temp_schema_%lu_%lu_%lu_%lu_%u",
                            xid, spcNode, dbNode, relId, bucketNode);

    securec_check_ss(rc, "\0", "\0");
    operators->setStringInfoTempSchemaName(tempSchemaName);
    StringInfo query = makeStringInfo();
    appendStringInfo(query, "CREATE SCHEMA %s", tempSchemaName);
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);
}

void OnlineDDLCreateTempDelta(Relation relation)
{
    OnlineDDLRelOperators* operators = RelationGetOnlineDDLOperators(relation);
    StringInfo tempSchemaName = operators->getStringInfoTempSchemaName();

    operators->setStringInfoDeltaRelname(ONLINE_DDL_DELTA_RELNAME);
    Oid deltaRelOid = InvalidOid;

    StringInfo query = makeStringInfo();
    appendStringInfo(query, "CREATE UNLOGGED TABLE %s.%s", tempSchemaName->data, ONLINE_DDL_DELTA_RELNAME);
    if (RELATION_IS_PARTITIONED(relation)) {
        appendStringInfo(query, "("
                                "operation TINYINT NOT NULL, "
                                "old_tup_ctid TID NOT NULL, "
                                "partion_no OID NOT NULL"
                                ")");
    } else {
        appendStringInfo(query, "("
                                "operation TINYINT NOT NULL, "
                                "old_tup_ctid TID NOT NULL"
                                ")");
    }
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);

    /* Build the qualified name for the delta table */
    List* qualifiedName =
        list_make2(makeString(pstrdup(tempSchemaName->data)), makeString(pstrdup(ONLINE_DDL_DELTA_RELNAME)));
    deltaRelOid = RangeVarGetRelid(makeRangeVarFromNameList(qualifiedName), AccessShareLock, false);
    operators->setDeltaRelid(deltaRelOid);
    list_free_deep(qualifiedName);
}

void OnlineDDLInitTempObject(Relation relation)
{
    OnlineDDLCreateTempSchema(relation);
    OnlineDDLCreateTempDelta(relation);
}

void OnlineDDLDropTempSchema(Relation relation)
{
    if (relation == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLDropTempSchema failed, relation is null.")));
    }
    OnlineDDLRelOperators* operators = RelationGetOnlineDDLOperators(relation);
    if (operators == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLDropTempSchema failed, can't get operators from relation.")));
    }
    StringInfo tempSchemaName = operators->getStringInfoTempSchemaName();
    StringInfo query = makeStringInfo();
    appendStringInfo(query, "DROP SCHEMA IF EXISTS %s CASCADE", tempSchemaName->data);
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);
}

void OnlineDDLDropTempSchema(OnlineDDLRelOperators* operators)
{
    if (operators == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLDropTempSchema failed can't get operators from relation.")));
    }
    StringInfo tempSchemaName = operators->getStringInfoTempSchemaName();
    StringInfo query = makeStringInfo();
    appendStringInfo(query, "DROP SCHEMA IF EXISTS %s CASCADE", tempSchemaName->data);
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);
}

void OnlineDDLResetAppendMode(Relation* relation)
{
    /*  Close relation, but don't release AccessExclusiveLock. */
    Oid relId = (*relation)->rd_id;
    char* relname = (*relation)->rd_rel->relname.data;
    char* namespacename = get_namespace_name((*relation)->rd_rel->relnamespace);
    relation_close(*relation, NoLock);

    StringInfo query = makeStringInfo();
    appendStringInfo(query, "ALTER TABLE %s.%s RESET (append_mode)", namespacename, relname);
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);

    *relation = relation_open(relId, AccessExclusiveLock);
    if (*relation == NULL) {
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("[Online-DDL] OnlineDDLResetAppendMode reopen relation failed.")));
    }
}

/**
 * Initialize the online DDL instance.
 *
 * @param wqueue The work queue for online DDL operations.
 * @param relation The relation on which the operation is to be performed.
 * @param cmds The list of commands to be executed.
 * @param lockmode The lock mode required for the operation.
 * @return true if the initialization is successful, false otherwise.
 */
bool OnlineDDLInstanceInit(List* wqueue, Relation* relation, List* cmds, LOCKMODE lockmode, OnlineDDLType onlineDDLType)
{
#ifdef USE_ASSERTS
    Assert(OnlineDDLCheckFeasible(&wqueue, *relation, cmds, lockmode) != ONLINE_DDL_INVALID);
#endif
    /* init online ddl hash entry */
    DDLGlobalHashEntry* hashEntry = onlineDDLInitHashEntry(*relation, true, onlineDDLType);
    OnlineDDLRegisterGlobalHashEntry(hashEntry);
    u_sess->online_ddl_operators = hashEntry->operators;
    (*relation)->rd_online_ddl_operators = (void*)hashEntry->operators;
    OnlineDDLRelOperators* operators = (OnlineDDLRelOperators*)(*relation)->rd_online_ddl_operators;

    /* Set relation enable append mode. */
    OnlineDDLEnableRelationAppendMode(*relation);
    OnlineDDLInitTempObject(*relation);
    pfree(hashEntry);

    /* Get session AccessExclusiveLock lock, before finish xact. */
    LockRelId relLockRelId = (*relation)->rd_lockInfo.lockRelId;
    LockRelationIdForSession(&relLockRelId, AccessExclusiveLock);
    operators->openDeltaRelation(AccessExclusiveLock);
    LockRelId deltaRelLockRelId = operators->getDeltaRelation()->rd_lockInfo.lockRelId;
    LockRelationIdForSession(&deltaRelLockRelId, ShareUpdateExclusiveLock);

    Snapshot snapshot = GetTransactionSnapshot();
    operators->setBaselineSnapshot(snapshot);

    /* Close relation before finish xact. */
    relation_close(*relation, AccessExclusiveLock);

    /* Relation has been closed, add append_mode, exec ddl with no pin of target table. */
    StringInfo query = makeStringInfo();
    appendStringInfo(query, "ALTER TABLE %s.%s SET (append_mode = online_ddl)",
                     get_namespace_name((*relation)->rd_rel->relnamespace), (*relation)->rd_rel->relname.data);
    OnlineDDLExecuteCommand(query->data);
    DestroyStringInfo(query);

    /* Close delta log relation before finish xact. */
    operators->closeDeltaRelation(AccessExclusiveLock);

    /* restart another transaction, close relation */
    CommandCounterIncrement();
    PopActiveSnapshot();
    finish_xact_command();
    start_xact_command();
    PushActiveSnapshot(snapshot);

    /* reopen and lock relation */
    *relation = relation_open(operators->getRelId(), ShareUpdateExclusiveLock);
    relLockRelId = (*relation)->rd_lockInfo.lockRelId;
    UnlockRelationIdForSession(&relLockRelId, AccessExclusiveLock);
    operators->openDeltaRelation(ShareUpdateExclusiveLock);
    // ctid start from (0, 2)
    operators->recordTupleEmpty();

    /* init ctid map */
    operators->initCtidMapRelation();

    ereport(NOTICE, (errmsg("Online DDL instance init finish, start to copy baseline data.")));
    return true;
}

bool OnlineDDLInstanceFinish(Relation relation)
{
    OnlineDDLRelOperators* operators = RelationGetOnlineDDLOperators(relation);
    operators->setStatus(ONLINE_DDL_END);
    operators->closeDeltaRelation(ShareUpdateExclusiveLock);
    operators->closeCtidMapRelation(AccessShareLock);
    OnlineDDLResetAppendMode(&relation);
    OnlineDDLDropTempSchema(operators);
    OnlineDDLReleaseHashEntry(GetDDLGlobalHashKey(relation->rd_node, relation->rd_id), operators->getStartXid());
    relation->rd_online_ddl_operators = NULL;
    u_sess->online_ddl_operators = NULL;
    relation_close(relation, ShareUpdateExclusiveLock);
    return true;
}

void OnlineDDLCleanup()
{
    if (u_sess->online_ddl_operators == NULL) {
        return;
    }
    OnlineDDLRelOperators* operators = (OnlineDDLRelOperators*)u_sess->online_ddl_operators;
    operators->setStatus(ONLINE_DDL_END);
    operators->closeDeltaRelation(ShareUpdateExclusiveLock);
    operators->closeCtidMapRelation(AccessShareLock);
    u_sess->online_ddl_operators = NULL;
}