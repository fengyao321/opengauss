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
 * online_ddl_append.h
 *
 * IDENTIFICATION
 *        src/include/commands/online_ddl_append.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef ONLINE_DDL_APPEND_H

#define ONLINE_DDL_APPEND_H

#include "postgres.h"
#include "knl/knl_variable.h"
#include "access/rewriteheap.h"
#include "commands/tablecmds.h"
#include "commands/online_ddl_util.h"

extern const int ONLINE_DDL_APPENDER_MAX_SCAN_TIMES;
extern const int ONLINE_DDL_APPENDER_MAX_FINISH_PAGES;

enum OnlineDDLScenario {
    ONLINE_DDL_REWRITE_ROW_TABLE = 0,
    ONLINE_DDL_REWRITE_ROW_PARTITIONED_TABLE,
    ONLINE_DDL_SPLIT_PARTITION,
    ONLINE_DDL_SPLIT_SUBPARTITION,
    ONLINE_DDL_MERGE_PARTITION,
    ONLINE_DDL_VACUUM_TABLE,      /* vacuum normal table */
    ONLINE_DDL_VACUUM_PARTITION,  /* vacuum partition */
    ONLINE_DDL_VACUUM_PARTITIONS, /* vacuum partitioned table (multi partitions) */
    ONLINE_DDL_CLUSTER_PARTITIONS /* cluster partitioned table */
};

/* mapping old partition Oid to temp table Oid */
struct PartitionOidMapEntry {
    Oid oldPartOid;    // old partition Oid
    Oid tempTableOid;  // temp table Oid
};

/* vacuum state for appender */
struct VacuumState {
    TransactionId freezeXid;
    TransactionId oldestXid;
    int numTuples;
    int tupsVacuumed;
    int tupRecentlyDead;
    RewriteState rwstate;
};

/* partition relation info */
struct PartRelInfo {
    Oid relId;
    Oid subParentId;
    Oid partOid;
    bool isSubPartition;
};

struct OnlineDDLAppender {
    bool inAppendMode;
    OnlineDDLType type;
    int deltaLogScanTimes;
    int oldTableScanTimes;
    Relation oldRelation;
    Relation newRelation;
    List* oldPartitionList;
    List* newOidList;
    Relation deltaRelation;
    Relation ctidMapRelation;
    Relation ctidMapIndex;
    ItemPointerData deltaLogScanIdx;
    ItemPointerData oldTableScanIdx;
    HTAB* partitionAppendMap;
    AlteredTableInfo* alterTableInfo;
    HTAB* PartitionOidMap;
    int indexNum;
    VacuumState* vacuumState;
    PartRelInfo partRelInfo;
};

/* return true if a < b, else return false */
inline bool CompareItemPointer(ItemPointer a, ItemPointer b)
{
    if (ItemPointerGetBlockNumberNoCheck(a) < ItemPointerGetBlockNumberNoCheck(b)) {
        return true;
    } else if (ItemPointerGetBlockNumberNoCheck(a) == ItemPointerGetBlockNumberNoCheck(b) &&
               ItemPointerGetOffsetNumberNoCheck(a) < ItemPointerGetOffsetNumberNoCheck(b)) {
        return true;
    } else {
        return false;
    }
}

// for rewrite row table or split partition
extern OnlineDDLAppender* OnlineDDLInitAppender(Relation oldRelation, Relation newRelation, Relation deltaRelation,
                                                Relation ctidMapRelation, Relation ctidMapIndex,
                                                ItemPointerData endCtid, AlteredTableInfo* alterTableInfo,
                                                OnlineDDLType type);
// for rewrite row partitioned table
extern OnlineDDLAppender* OnlineDDLInitAppender(List* oldPartitionList, List* newOidList, Relation deltaRelation,
                                                Relation ctidMapRelation, Relation ctidMapIndex,
                                                HTAB* partitionAppendMap, AlteredTableInfo* alterTableInfo,
                                                OnlineDDLType type);
// for merge partition
extern OnlineDDLAppender* OnlineDDLInitAppender(List* oldPartitionList, Relation newRelation, Relation deltaRelation,
                                                Relation ctidMapRelation, Relation ctidMapIndex,
                                                HTAB* partitionAppendMap, AlteredTableInfo* alterTableInfo,
                                                OnlineDDLType type);
extern OnlineDDLAppender* OnlineDDLAppenderInitVacuumState(OnlineDDLAppender* appender, TransactionId freezeXid,
                                                           TransactionId oldestXid);
extern OnlineDDLAppender* OnlineDDLInitPartRelInfo(OnlineDDLAppender* appender, Oid relId, Oid subParentId, Oid partOid,
                                                   bool isSubPartition);
extern bool OnlineDDLAppend(OnlineDDLAppender* appender, OnlineDDLScenario scenario);
extern bool OnlineDDLOnlyCheck(OnlineDDLAppender* appender);
extern void AddPartitionOidMapping(OnlineDDLAppender* appender, Oid oldPartOid, Oid tempTableOid);
extern Oid GetTempTableFromOldPartition(OnlineDDLAppender* appender, Oid oldPartOid);
extern void CleanupAppender(OnlineDDLAppender* appender);

#endif /* ONLINE_DDL_APPEND_H */