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
 * online_ddl.h
 *
 * IDENTIFICATION
 *        src/include/commands/online_ddl.h
 *
 * -------------------------------------------------------------------------
 */

#ifndef ONLINE_DDL_H
#define ONLINE_DDL_H

#include "postgres.h"

#include "nodes/relation.h"
#include "storage/lock/lock.h"
#include "utils/relcache.h"
#include "commands/tablecmds.h"
#include "commands/online_ddl_globalhash.h"

#define ONLINE_DDL_DETAL_RELNAME "online_ddl_delta_log"

extern bool OnlineDDLInstanceInit(List* wqueue, Relation* relation, List* cmds, LOCKMODE lockmode,
                                  OnlineDDLType onlineDDLType);
extern OnlineDDLType OnlineDDLCheckFeasible(List** wqueue, Relation relation, List* cmds, LOCKMODE lockmode);
extern bool OnlineDDLInstanceFinish(Relation relation);
extern void OnlineDDLinit();
extern void OnlineDDLCleanup();
#endif /* ONLINE_DDL_H */
