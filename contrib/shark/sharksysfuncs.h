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
 * --------------------------------------------------------------------------------------
 *
 * sharksysfuncs.h
 *
 * IDENTIFICATION
 *        contrib/shark/sharksysfuncs.h
 *
 * --------------------------------------------------------------------------------------
 */
#ifndef SHARK_SYS_FUNCS_H
#define SHARK_SYS_FUNCS_H
 
#include "postgres.h"
#include "knl/knl_variable.h"

#include <cctype>
#include <cfloat>
#include <climits>
#include <cmath>
#include "catalog/pg_type.h"
#include "utils/builtins.h"
#include "utils/date.h"

typedef struct object_info {
    char* object_name;
    Oid object_schema;
} object_info_t;

typedef object_info_t* (*oid_to_object_ptr)(Oid, Oid);

#define MAX_OBJECT_FUNCTION 5

extern char* pg_get_viewdef_worker(Oid viewoid, int prettyFlags, int wrapColumn);
extern char* pg_get_functiondef_worker(Oid funcid, int* headerlines);
extern char* pg_get_triggerdef_string(Oid trigid);
#endif
