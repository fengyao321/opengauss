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
 * online_ddl_util.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/optimizer/commands/online_ddl/online_ddl_util.cpp
 *
 * ---------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"
#include "access/heapam.h"
#include "access/xact.h"
#include "access/tableam.h"
#include "catalog/namespace.h"
#include "parser/parser.h"
#include "parser/parse_utilcmd.h"
#include "utils/relcache.h"

#include "commands/online_ddl_util.h"

void OnlineDDLExecuteCommand(char* query)
{
    List* parsetreeList = NULL;
    ListCell* parsetreeItem = NULL;
    List* query_string_locationlist = NULL;

    parsetreeList = pg_parse_query(query, &query_string_locationlist);
    if (parsetreeList == NULL) {
        ereport(ERROR, (errcode(ERRCODE_SYNTAX_ERROR),
                        errmsg("unexpected null parsetree list, during online ddl, sql: %s", query)));
    }
    foreach (parsetreeItem, parsetreeList) {
        instr_unique_sql_handle_multi_sql(parsetreeItem == list_head(parsetreeList));
        Node* parsetree = (Node*)lfirst(parsetreeItem);
        List* querytreeList = NULL;
        List* plantreeList = NULL;
        ListCell* statementlistItem = NULL;

        Node* statement = NULL;
        querytreeList = pg_analyze_and_rewrite(parsetree, query, NULL, 0);
        plantreeList = pg_plan_queries(querytreeList, 0, NULL);
        foreach (statementlistItem, plantreeList) {
            statement = (Node*)lfirst(statementlistItem);
            processutility_context proutility_cxt;
            proutility_cxt.parse_tree = statement;
            proutility_cxt.query_string = query;
            proutility_cxt.readOnlyTree = false;
            proutility_cxt.params = NULL;
            proutility_cxt.is_top_level = false;
            ProcessUtility(&proutility_cxt, None_Receiver, false, NULL, PROCESS_UTILITY_GENERATED);
            CommandCounterIncrement();
        }
    }
}

/**
 * Set the target relation to append mode.
 *
 * @param relation The relation to set append mode.
 * @return true if the operation is successful, false otherwise.
 */
void OnlineDDLEnableRelationAppendMode(Relation relation)
{
    OnlineDDLRelOperators* operators = RelationGetOnlineDDLCtl(relation);
    Assert(operators != NULL);
    if (operators == NULL) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("rd_online_ddl_operators is null, during online ddl.")));
    }
    if (relation->rd_rel->relkind == RELKIND_RELATION) {
        ItemPointerData endCtid;
        heap_get_max_tid(relation, &endCtid);
        operators->enableTargetRelationAppendMode(endCtid);
    } else {
        /* todo */
        Assert(0);
    }
}

void OnlineDDLCopyRelationIndexs(Relation srcRelation, Relation destRelation, List** srcIndexOidList,
                                 List** destIndexOidList)
{
    List* srcIndexRelationList = NIL;
    Oid destRelationOid = destRelation->rd_id;
    if (srcIndexOidList == NULL || destIndexOidList == NULL) {
        ereport(ERROR,
                (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                 errmsg("[Online-DDL] srcIndexOidList or destIndexOidList is null, during copy relation index.")));
    }
    if (srcRelation == NULL || destRelationOid == NULL) {
        ereport(ERROR, (errcode(ERRCODE_UNEXPECTED_NULL_VALUE),
                        errmsg("[Online-DDL] srcRelation or destRelation is invalid, during copy relation index.")));
    }
    ListCell* cell = NULL;
    *srcIndexOidList = RelationGetIndexList(srcRelation);
    foreach (cell, *srcIndexOidList) {
        Oid dstIndexPartTblspcOid;
        Oid clonedIndexRelationId;
        Oid indexDestPartOid;
        char tmpIndexName[NAMEDATALEN];
        Relation currentIndex;
        bool skipBuild = false;
        errno_t rc = EOK;

        Oid srcIndexOid = lfirst_oid(cell);
        /* Open the src index relation. */
        currentIndex = index_open(srcIndexOid, AccessShareLock);
        if (!IndexIsUsable(currentIndex->rd_index)) {
            ereport(ERROR, (errcode(ERRCODE_INVALID_OBJECT_DEFINITION),
                            errmsg("[Online-DDL] index %s is unusable, during copy relation index.",
                                   RelationGetRelationName(currentIndex))));
        } else {
            srcIndexRelationList = lappend(srcIndexRelationList, currentIndex);
        }
        if (OID_IS_BTREE(currentIndex->rd_rel->relam)) {
            skipBuild = true;
        } else {
            skipBuild = false;
        }
        /* build name for tmp index */
        rc = snprintf_s(tmpIndexName, sizeof(tmpIndexName), sizeof(tmpIndexName) - 1, "pg_tmp_%u_%u_index_online_ddl",
                        destRelationOid, currentIndex->rd_id);
        securec_check_ss_c(rc, "\0", "\0");
        dstIndexPartTblspcOid = destRelation->rd_rel->reltablespace;
        clonedIndexRelationId =
            generateClonedIndex(currentIndex, destRelation, tmpIndexName, dstIndexPartTblspcOid, skipBuild, false);
        *destIndexOidList = lappend_oid(*destIndexOidList, clonedIndexRelationId);
        ereport(ONLINE_DDL_LOG_LEVEL, (errcode(ERRCODE_SUCCESSFUL_COMPLETION),
                         errmsg("[Online-DDL] copy index %s to relation %s success.",
                                RelationGetRelationName(currentIndex), RelationGetRelationName(destRelation))));
    }
    foreach (cell, srcIndexRelationList) {
        Relation indexRel = (Relation)lfirst(cell);
        index_close(indexRel, AccessShareLock);
    }
    list_free_ext(srcIndexRelationList);
}
