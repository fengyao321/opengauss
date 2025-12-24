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
#ifndef ONLINE_DDL_DELTALOG_H
#define ONLINE_DDL_DELTALOG_H

#include "postgres.h"

#include "nodes/relation.h"
#include "utils/relcache.h"

const short int ONLINE_DDL_OPERATION_EMPTY = 0;
const short int ONLINE_DDL_OPERATION_INSERT = 1;
const short int ONLINE_DDL_OPERATION_DELETE = 2;
const int ONLINE_DDL_OPERATEION_TYPE_NUM = 3;

extern const int DELTALOG_OPERATION_TYPE_IDX;
extern const int DELTALOG_TUP_CTDI_IDX;
extern const int ONLINE_DDL_DELTALOG_ATTR_NUM;

extern bool OnlineDDLCheckTempSchemaFormat(char* npName, TransactionId* xid, Oid* spcNode, Oid* dbNode, Oid* relId,
                                           int2* bucketNode);
extern void OnlineDDLCheckDeltaLog(Relation rel, bool checkInProgress);
extern void OnlineDDLInsertDeltaLog(Relation deltaRelation, ItemPointer tid);
extern void OnlineDDLDeleteDeltaLog(Relation deltaRelation, ItemPointer tid);
extern void OnlineDDLUpdateDeltaLog(Relation deltaRelation, ItemPointer oldTid, ItemPointer newTid);
extern void OnlineDDLEmptyDeltaLog(Relation deltaRelation, ItemPointer tid);

#endif /* ONLINE_DDL_DELTALOG_H */
