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
 * online_ddl_ctid_map.h
 *
 * IDENTIFICATION
 *        src/include/commands/online_ddl_ctid_map.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef ONLINE_DDL_CTID_MAP_H
#define ONLINE_DDL_CTID_MAP_H

#include "postgres.h"

#include "nodes/relation.h"
#include "utils/relcache.h"
#include "utils/rel.h"

extern const char* ONLINE_DDL_CTID_MAP_RELNAME;
extern const uint32 CTID_MAP_ATTR_NUM; /* old_tup_ctid, new_tup_ctid */
extern ItemPointerData CTID_MAP_DEFAULT_CTID;

extern Oid OnlineDDLCreateCtidMap(StringInfo tempSchemaName);
extern bool OnlineDDLInsertCtidMap(ItemPointer oldTid, ItemPointer newTid, Relation relation);
extern bool OnlineDDLInsertCtidMap(ItemPointer oldTid, Oid relId, ItemPointer newTid, Relation relation);
extern ItemPointerData OnlineDDLGetTargetCtid(ItemPointer oldTid, Relation relation, Relation indexRelation);
extern ItemPointerData OnlineDDLGetTargetCtid(ItemPointer oldTid, Oid* partOid, Relation relation,
                                              Relation indexRelation);

#endif /* ONLINE_DDL_CTID_MAP_H */
