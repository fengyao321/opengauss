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
 * online_ddl_util.h
 *
 * IDENTIFICATION
 *        src/include/commands/online_ddl_util.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef ONLINE_DDL_UTIL_H
#define ONLINE_DDL_UTIL_H

#include "postgres.h"

#include "access/htup.h"
#include "nodes/parsenodes.h"
#include "nodes/relation.h"
#include "storage/lock/lock.h"
#include "utils/relcache.h"

#define LOG_ONLINE_DDL_DEFAULT (0)
#define LOE_ONLINE_DDL_LOG (1)
#define LOG_ONLINE_DDL_NOTICE (2)

struct DDLGlobalHashKey {
    Oid spcNode;     /* tablespace */
    Oid dbNode;      /* database */
    Oid relId;       /* relation */
};

/* online ddl operator type */
enum OnlineDDLType {
    ONLINE_DDL_INVALID = 0,
    ONLINE_DDL_CHECK = 1,
    ONLINE_DDL_REWRITE = 2,
    ONLINE_DDL_VACUUM = 3,
    ONLINE_DDL_CLUSTER = 4
};

#define ONLINE_DDL_LOG_LEVEL                                                 \
    (u_sess->attr.attr_common.log_online_ddl_level == LOG_ONLINE_DDL_DEFAULT \
         ? DEBUG5                                                            \
         : (u_sess->attr.attr_common.log_online_ddl_level == LOE_ONLINE_DDL_LOG ? LOG : NOTICE))

extern void OnlineDDLExecuteCommand(char* query);
extern void OnlineDDLEnableRelationAppendMode(Relation relation);
extern void OnlineDDLCopyRelationIndexs(Relation srcRelation, Relation destRelation, List** srcIndexOidList,
                                        List** destIndexOidList);
extern void OnlineDDLLockCheck(Oid relid);
extern void OnlineDDLLockCheck(Oid relationId, Oid partitionId);
extern void OnlineDDLPartitionLockCleanup(Oid relationId, Oid partitionId);

#endif /* ONLINE_DDL_UTIL_H */
