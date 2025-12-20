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
 * online_ddl_deltalog.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/optimizer/commands/online_ddl/online_ddl_deltalog.cpp
 *
 * ---------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "fmgr.h"
#include "access/tableam.h"
#include "utils/rel.h"
#include "utils/lsyscache.h"
#include "catalog/pg_type.h"
#include "utils/builtins.h"

#include "commands/online_ddl_globalhash.h"
#include "commands/online_ddl_util.h"
#include "commands/online_ddl_deltalog.h"