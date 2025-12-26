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
#define DECIMAL_CARRY 10
#define SINGLE_DIGIT_LEN 1
#define MAX_DBL_DIG 17
#define MAX_FLOAT_DIG 5
#define MAX_DBL_DIG_INDEX (MAX_DBL_DIG - 1)
#define MAX_STRING_LEN 8000
#define SECOND_ARG_INDEX 2
#define TWO 2
#define MAX_PRECISION_LEN 38
#define MAX_SHARK_YEAR 9999
#define MAX_INDETITY_LEN 128
#define MAX_INDETITY_OUT_LEN 260  /* MAX_INDETITY_LEN * 2 + 2 */
#define SHARK_MAX_DATETIME_PRECISION 4
#define TOTAL_TYPEMAP_COUNT 28
#define MONTHS_COUNT_IN_A_YEAR 12
#define NUMERIC_PRECISION_BASE_LEN 4
#define NUMERIC_PRECISION_MASK 0xFFFF
#define SHORT_LENGTH 16
#define INT1_DEFAULT_PRECISION 3
#define INT2_DEFAULT_PRECISION 5
#define INT4_DEFAULT_PRECISION 10
#define INT8_DEFAULT_PRECISION 19
#define FLOAT8_DEFAULT_PRECISION 53
#define FLOAT4_DEFAULT_PRECISION 24
#define NUMERIC_DEFAULT_PRECISION 38
#define BIT_DEFAULT_PRECISION 1
#define CASH_DEFAULT_PRECISION 19
#define SMALLDATETIME_DEFAULT_PRECISION 16
#define DATETIME_DEFAULT_PRECISION 26
#define DATETIME_MIN_PRECISION 19
#define TIME_MIN_PRECISION 8
#define DATE_DEFAULT_PRECISION 10
#define TIME_DEFAULT_PRECISION 15
#define TIMESTAMP_DEFAULT_SCALE 6
#define NUMERIC_DEFAULT_SCALE 38
#define CASH_DEFAULT_SCALE 4
#define FLOAT4_PRECISION 6
#define FLOAT8_PRECISION 15

Datum get_base_type(PG_FUNCTION_ARGS, bytea *sv_value);
Datum get_precision(PG_FUNCTION_ARGS, bytea *sv_value);
Datum get_scale(PG_FUNCTION_ARGS, bytea *sv_value);
Datum get_total_bytes(PG_FUNCTION_ARGS, bytea *sv_value);
Datum get_max_length(PG_FUNCTION_ARGS, bytea *sv_value);
Datum get_collation(PG_FUNCTION_ARGS, bytea *sv_value);
extern char* pg_get_viewdef_worker(Oid viewoid, int prettyFlags, int wrapColumn);
extern char* pg_get_functiondef_worker(Oid funcid, int* headerlines);
extern char* pg_get_triggerdef_string(Oid trigid);

typedef struct TypeInfoMap {
    const char* pg_typname;
    const char* tsql_typname;
} TypeInfoMap;
extern bool StrEndWith(const char *str, const char *suffix);
#endif
