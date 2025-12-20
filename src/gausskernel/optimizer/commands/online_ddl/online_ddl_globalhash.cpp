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
 * online_ddl_globalhash.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/optimizer/commands/online_ddl/online_ddl_globalhash.cpp
 *
 * ---------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"

#include "access/heapam.h"
#include "access/htup.h"
#include "catalog/namespace.h"
#include "utils/elog.h"
#include "storage/buf/bufmgr.h"
#include "storage/buf/buf_internals.h"
#include "storage/lmgr.h"
#include "storage/smgr/relfilenode_hash.h"
#include "utils/fmgrtab.h"
#include "utils/hsearch.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"

#include "commands/online_ddl_deltalog.h"
#include "commands/online_ddl_ctid_map.h"
#include "commands/online_ddl_util.h"
#include "commands/online_ddl_globalhash.h"

OnlineDDLRelOperators::OnlineDDLRelOperators(MemoryContext context, Relation relation, bool appendMode,
                                             OnlineDDLType onlineDDLType)
{
    this->relId = relation->rd_id;
    this->relfilenode = relation->rd_node; /* relfilenode */
    this->onlineDDLType = onlineDDLType;
    this->status = ONLINE_DDL_START;
    this->startXid = InvalidTransactionId;
    this->sessionId = 0;

    this->deltaRelation = NULL;
    this->deltaRelid = InvalidOid;

    this->deltaRelnamespace = InvalidOid;
    this->ctidMapRelation = NULL;

    this->appender = NULL;
    this->appendMode = appendMode;

    this->targetBlockNumber = 0;
    this->context = context;
    MemoryContext oldContext = MemoryContextSwitchTo(context);
    this->tempSchemaName = makeStringInfo();
    this->deltaRelname = makeStringInfo();
    MemoryContextSwitchTo(oldContext);
}

OnlineDDLRelOperators::~OnlineDDLRelOperators()
{
    if (tempSchemaName != NULL) {
        DestroyStringInfo(tempSchemaName);
    }
    if (deltaRelation != NULL) {
        relation_close(deltaRelation, AccessExclusiveLock);
        deltaRelation = NULL;
    }
    if (deltaRelname != NULL) {
        DestroyStringInfo(deltaRelname);
    }
}

void OnlineDDLRelOperators::openDeltaRelation(LOCKMODE lockmode)
{
}

void OnlineDDLRelOperators::initCtidMapRelation()
{
}

void OnlineDDLRelOperators::closeDeltaRelation(LOCKMODE lockmode)
{
}

void OnlineDDLRelOperators::closeCtidMapRelation(LOCKMODE lockmode)
{
}

bool OnlineDDLRelOperators::recordTupleInsert(Relation relation, ItemPointer tid)
{
    return true;
}

bool OnlineDDLRelOperators::recordTupleEmpty()
{
    return true;
}

bool OnlineDDLRelOperators::recordTupleMultiInsert(Relation relation, Tuple* tuples, int ntuples)
{
    return true;
}

bool OnlineDDLRelOperators::recordTupleDelete(Relation relation, ItemPointer tid)
{
    return true;
}

bool OnlineDDLRelOperators::recordTupleUpdate(Relation relation, ItemPointer oldTid, ItemPointer newTid)
{
    return true;
}

bool OnlineDDLRelOperators::enableTargetRelationAppendMode(ItemPointerData endCtid)
{
    return true;
}

bool OnlineDDLRelOperators::clearTargetRelationAppendMode()
{
    return true;
}

bool OnlineDDLRelOperators::insertCtidMap(ItemPointer oldTid, ItemPointer newTid)
{
    return true;
}

void OnlineDDLRelOperators::OnlineDDLAppendIncrementalData(Relation oldRelation, Relation newRelation,
                                                           AlteredTableInfo* alterTableInfo)
{
}