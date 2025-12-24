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
 * -------------------------------------------------------------------------
 *
 * online_ddl_globalhash.h
 *
 * IDENTIFICATION
 *        src/include/commands/online_ddl_globalhash.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef ONLINE_DDL_GLOBALHASH_H
#define ONLINE_DDL_GLOBALHASH_H

#include "postgres.h"

#include "commands/online_ddl_append.h"
#include "nodes/relation.h"
#include "storage/lock/lock.h"
#include "utils/relcache.h"

const int ONLINE_DDL_GLOBAL_ID_INITIAL = 1;  // 1 ~ UINT64_MAX - 1

typedef enum {
    ONLINE_DDL_STATUS_NONE = 0,
    ONLINE_DDL_START,
    ONLINE_DDL_STATUS_PREPARE,
    ONLINE_DDL_STATUS_BASELINE_COPY,
    ONLINE_DDL_STATUS_CATCHUP,
    ONLINE_DDL_COMMITTING,
    ONLINE_DDL_END
} OnlineDDLStatus;

enum OnlineDDLType {
    ONLINE_DDL_INVALID = 0,
    ONLINE_DDL_CHECK = 1,
    ONLINE_DDL_REWRITE = 2,
};

struct DDLGlobalHashKey {
    Oid spcNode;     /* tablespace */
    Oid dbNode;      /* database */
    Oid relId;       /* relation */
    int2 bucketNode; /* bucketid */
};

class OnlineDDLRelOperators : public BaseObject {
private:
    Oid relId;
    RelFileNode relfilenode; /* relfilenode */
    OnlineDDLStatus status;  /* status of online ddl */
    OnlineDDLType onlineDDLType; /* online ddl type */

    /* ddl delta log table */
    TransactionId startXid;
    uint64 sessionId;
    StringInfo tempSchemaName; /* temp schema name for online ddl */

    StringInfo deltaRelname; /* delta log relation name */
    Relation deltaRelation;  /* delta log relation */
    Oid deltaRelid;          /* delta log relation relid */

    Oid deltaRelnamespace; /* delta log relation namespace */

    Relation ctidMapRelation; /* ctid map relation */

    /* baseline data copy */
    Snapshot baselineSnapshot;

    /* appender */
    OnlineDDLAppender* appender; /* appender */

    /* append mode info */
    bool appendMode; /* append mode */
    /* ctid when online ddl start */
    ItemPointerData endCtidInternal; /* end ctid for append mode */
    BlockNumber targetBlockNumber;   /* target block number for append mode */

    MemoryContext context; /* memory context for this object */

public:
    OnlineDDLRelOperators(MemoryContext context, Relation relation, bool appendMode, OnlineDDLType onlineDDLType);
    ~OnlineDDLRelOperators();
    bool recordTupleInsert(Relation relation, ItemPointer tid);
    bool recordTupleDelete(Relation relation, ItemPointer tid);
    bool recordTupleEmpty();
    bool recordTupleMultiInsert(Relation relation, Tuple* tuples, int ntuples);
    bool recordTupleUpdate(Relation relation, ItemPointer oldTid, ItemPointer newTid);
    void openDeltaRelation(LOCKMODE lockmode);
    void closeDeltaRelation(LOCKMODE lockmode);
    void initCtidMapRelation();
    void closeCtidMapRelation(LOCKMODE lockmode);
    bool insertCtidMap(ItemPointer oldTid, ItemPointer newTid);

    /* append mode */
    bool enableTargetRelationAppendMode(ItemPointerData endCtid);
    bool clearTargetRelationAppendMode();

    /* catch up data */
    void OnlineDDLAppendIncrementalData(Relation oldRelation, Relation newRelation, AlteredTableInfo* alterTableInfo);

    Oid getRelId() const
    {
        return relId;
    }

    OnlineDDLType getOnlineDDLType() const
    {
        return onlineDDLType;
    }

    /* ddl delta log table */
    void setStartXid(TransactionId xid)
    {
        startXid = xid;
    }

    uint64 getSessionId()
    {
        return sessionId;
    }

    void setSessionId(uint64 id)
    {
        sessionId = id;
    }

    TransactionId getStartXid()
    {
        return startXid;
    }

    void setStatus(OnlineDDLStatus status)
    {
        this->status = status;
    }

    OnlineDDLStatus getStatus() const
    {
        return status;
    }

    void setStringInfoTempSchemaName(char* schemaName)
    {
        if (tempSchemaName == NULL) {
            tempSchemaName = makeStringInfo();
        }
        resetStringInfo(tempSchemaName);
        appendStringInfo(tempSchemaName, "%s", schemaName);
    }

    void setStringInfoTempSchemaName(StringInfo schemaName)
    {
        if (tempSchemaName == NULL) {
            tempSchemaName = makeStringInfo();
        }
        resetStringInfo(tempSchemaName);
        appendBinaryStringInfo(tempSchemaName, schemaName->data, schemaName->len);
    }

    StringInfo getStringInfoTempSchemaName()
    {
        return tempSchemaName;
    }

    StringInfo getStringInfoDeltaRelname()
    {
        return deltaRelname;
    }
    void setStringInfoDeltaRelname(char* relname)
    {
        if (deltaRelname == NULL) {
            deltaRelname = makeStringInfo();
        }
        resetStringInfo(deltaRelname);
        appendStringInfo(deltaRelname, "%s", relname);
    }

    Oid getDeltaRelid()
    {
        return deltaRelid;
    }

    void setDeltaRelid(Oid relid)
    {
        deltaRelid = relid;
    }

    bool getAppendMode() const
    {
        return this->appendMode;
    }

    ItemPointerData getendCtidInternal()
    {
        return endCtidInternal;
    }

    BlockNumber getTargetBlockNumber()
    {
        return targetBlockNumber;
    }

    void setTargetBlockNumber(BlockNumber blockNumber)
    {
        targetBlockNumber = blockNumber;
    }

    Relation getDeltaRelation()
    {
        return deltaRelation;
    }

    Relation getCtidMapRelation()
    {
        return ctidMapRelation;
    }

    Snapshot getBaselineSnapshot()
    {
        return baselineSnapshot;
    }

    void setBaselineSnapshot(Snapshot snapshot)
    {
        baselineSnapshot = snapshot;
    }
};

/*
 * DDLGlobalHashEntry is a hash entry for ddl global hash table.
 */
struct DDLGlobalHashEntry {
    DDLGlobalHashKey hashKey; /* relfilenode */
    Oid relId;
    OnlineDDLRelOperators* operators; /* global info for online ddl */
};
inline DDLGlobalHashKey GetDDLGlobalHashKey(RelFileNode relfilenode, Oid relId)
{
    DDLGlobalHashKey hashKey;
    hashKey.spcNode = relfilenode.spcNode;
    hashKey.dbNode = relfilenode.dbNode;
    hashKey.relId = relId;
    hashKey.bucketNode = relfilenode.bucketNode;
    return hashKey;
}

inline OnlineDDLRelOperators* RelationGetOnlineDDLCtl(Relation relation)
{
    return (OnlineDDLRelOperators *) (relation->rd_online_ddl_operators);
}

extern void initDDLGlobalHash(MemoryContext memctx);
extern DDLGlobalHashEntry* onlineDDLInitHashEntry(Relation relation, bool appendMode, OnlineDDLType onlineDDLType);
extern void OnlineDDLRegisterGlobalHashEntry(DDLGlobalHashKey hashKey, OnlineDDLRelOperators* operators);
extern void OnlineDDLRegisterGlobalHashEntry(DDLGlobalHashEntry* entry);
extern bool CheckOnlineDDLStatusRunning(DDLGlobalHashKey hashKey, TransactionId xid);
extern bool OnlineDDLReleaseHashEntry(DDLGlobalHashKey hashKey, TransactionId xid);

extern DDLGlobalHashEntry* OnlineDDLGetHashEntry(DDLGlobalHashKey hashKey);

#endif /* ONLINE_DDL_H */
