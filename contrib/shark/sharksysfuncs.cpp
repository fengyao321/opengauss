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
 * sharksysfuncs.cpp
 *
 * IDENTIFICATION
 *        contrib/shark/sharksysfuncs.cpp
 *
 * --------------------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"

#include <cctype>
#include <cfloat>
#include <climits>
#include <cmath>
#include "catalog/pg_type.h"
#include "utils/builtins.h"
#include "utils/date.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include "utils/datetime.h"
#include "utils/memutils.h"
#include "libpq/pqformat.h"
#include "parser/scansup.h"
#include "common/int.h"
#include "miscadmin.h"
#include "access/xact.h"
#include "shark.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_trigger.h"
#include "catalog/pg_constraint.h"
#include "catalog/pg_attrdef.h"
#include "catalog/indexing.h"
#include "access/sysattr.h"
#include "utils/fmgroids.h"
#include "utils/cash.h"
#include "utils/lsyscache.h"
#include "sharksysfuncs.h"

extern "C" Datum object_name(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(object_name);

extern "C" Datum object_schema_name(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(object_schema_name);

extern "C" Datum object_define(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(object_define);


extern "C" Datum sysdatetime(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(sysdatetime);

extern "C" Datum eomonth(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(eomonth);

extern "C" Datum truncate_identifier(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(truncate_identifier);

extern "C" Datum translate_pg_type_to_tsql(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(translate_pg_type_to_tsql);

extern "C" Datum is_date(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(is_date);

extern "C" Datum columnproperty(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(columnproperty);

TypeInfoMap g_type_maps[TOTAL_TYPEMAP_COUNT] = {
    {"sql_variant", "sql_variant"},
    {"datetime", "datetime2"},
    {"smalldatetime", "smalldatetime"},
    {"date", "date"},
    {"time", "time"},
    {"float8", "float"},
    {"float4", "real"},
    {"numeric", "numeric"},
    {"money", "money"},
    {"int8", "bigint"},
    {"int4", "int"},
    {"int2", "smallint"},
    {"int1", "tinyint"},
    {"tinyint", "tinyint"},
    {"bool", "tinyint"},
    {"bit", "bit"},
    {"nvarchar", "nvarchar"},
    {"nvarchar2", "nvarchar"},
    {"nchar", "nchar"},
    {"varchar", "varchar"},
    {"bpchar", "char"},
    {"varbinary", "varbinary"},
    {"binary", "binary"},
    {"text", "text"},
    {"xml", "xml"},
    {"bpchar", "char"},
    {"decimal", "decimal"},
    {"timestamp", "timestamp"},
};

void FreeObjectInfo(object_info_t* info)
{
    if (info == NULL) {
        return;
    }

    pfree_ext(info->object_name);
    pfree_ext(info);
}

object_info_t* oid_to_pg_class_object(Oid object_id, Oid user_id)
{
    HeapTuple tuple;
    object_info_t* object_info = NULL;
    tuple = SearchSysCache1(RELOID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        /* check if user have right permission on object */
        if (pg_class_aclcheck(object_id, user_id, ACL_SELECT) == ACLCHECK_OK) {
            Form_pg_class pg_class = (Form_pg_class) GETSTRUCT(tuple);
            object_info = (object_info_t*)palloc0(sizeof(object_info_t));
            object_info->object_name = pstrdup(NameStr(pg_class->relname));
            object_info->object_schema = pg_class->relnamespace;
        }
        ReleaseSysCache(tuple);
    }
    return object_info;
}

object_info_t* oid_to_pg_proc_object(Oid object_id, Oid user_id)
{
    HeapTuple tuple;
    object_info_t* object_info = NULL;
    tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        if (pg_proc_aclcheck(object_id, user_id, ACL_EXECUTE) == ACLCHECK_OK) {
            Form_pg_proc procform = (Form_pg_proc) GETSTRUCT(tuple);
            object_info = (object_info_t*)palloc0(sizeof(object_info_t));
            object_info->object_name = pstrdup(NameStr(procform->proname));
            object_info->object_schema = procform->pronamespace;
        }
        ReleaseSysCache(tuple);
    }
    return object_info;
}

object_info_t* oid_to_pg_type_object(Oid object_id, Oid user_id)
{
    HeapTuple tuple;
    object_info_t* object_info = NULL;
    tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        if (pg_type_aclcheck(object_id, user_id, ACL_USAGE) == ACLCHECK_OK) {
            Form_pg_type pg_type = (Form_pg_type) GETSTRUCT(tuple);
            object_info = (object_info_t*)palloc0(sizeof(object_info_t));
            object_info->object_name = pstrdup(NameStr(pg_type->typname));
            object_info->object_schema = pg_type->typnamespace;
        }
        ReleaseSysCache(tuple);
    }
    return object_info;
}

object_info_t* oid_to_pg_trigger_object(Oid object_id, Oid user_id)
{
    HeapTuple tuple;
    object_info_t* object_info = NULL;
    Relation tgrel;
    ScanKeyData key;
    SysScanDesc tgscan;

    tgrel = heap_open(TriggerRelationId, AccessShareLock);
    ScanKeyInit(&key, ObjectIdAttributeNumber, BTEqualStrategyNumber, F_OIDEQ, ObjectIdGetDatum(object_id));
    tgscan = systable_beginscan(tgrel, TriggerOidIndexId, true, NULL, 1, &key);
    tuple = systable_getnext(tgscan);
    if (HeapTupleIsValid(tuple)) {
        Form_pg_trigger pg_trigger = (Form_pg_trigger) GETSTRUCT(tuple);
        if (OidIsValid(pg_trigger->tgrelid) &&
            pg_class_aclcheck(pg_trigger->tgrelid, user_id, ACL_SELECT) == ACLCHECK_OK) {
                object_info = (object_info_t*)palloc0(sizeof(object_info_t));
                object_info->object_name = pstrdup(NameStr(pg_trigger->tgname));
                object_info->object_schema = get_rel_namespace(pg_trigger->tgrelid);
        }
    }
    systable_endscan(tgscan);
    relation_close(tgrel, AccessShareLock);
    return object_info;
}

object_info_t* oid_to_pg_constraint_object(Oid object_id, Oid user_id)
{
    HeapTuple tuple;
    object_info_t* object_info = NULL;
    tuple = SearchSysCache1(CONSTROID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        Form_pg_constraint con = (Form_pg_constraint) GETSTRUCT(tuple);
        if (OidIsValid(con->conrelid) &&
            (pg_class_aclcheck(con->conrelid, user_id, ACL_SELECT) == ACLCHECK_OK)) {
            object_info = (object_info_t*)palloc0(sizeof(object_info_t));
            object_info->object_name = pstrdup(NameStr(con->conname));
            object_info->object_schema = con->connamespace;
        }
        ReleaseSysCache(tuple);
    }
    return object_info;
}

char* object_id_to_view_def(Oid object_id, Oid user_id)
{
    char* result = NULL;
    HeapTuple tuple = SearchSysCache1(RELOID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        Form_pg_class pg_class = (Form_pg_class) GETSTRUCT(tuple);
        if (pg_class_aclcheck(object_id, user_id, ACL_SELECT) == ACLCHECK_OK
             && (pg_class->relkind == 'v' || pg_class->relkind == 'm')) {
                result = pg_get_viewdef_worker(object_id, 0, -1);
        }
        ReleaseSysCache(tuple);
    }
    return result;
}

char* object_id_to_proc_def(Oid object_id, Oid user_id)
{
    char* result = NULL;
    HeapTuple tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        if (pg_proc_aclcheck(object_id, user_id, ACL_EXECUTE) == ACLCHECK_OK) {
            Form_pg_proc procform = (Form_pg_proc) GETSTRUCT(tuple);
            int headerlines = 0;
            result = pg_get_functiondef_worker(object_id, &headerlines);
        }
        ReleaseSysCache(tuple);
    }
    return result;
}

char* object_id_to_trigger_def(Oid object_id, Oid user_id)
{
    Relation tgrel;
    ScanKeyData key;
    SysScanDesc tgscan;
    HeapTuple tuple;
    char* result = NULL;
    tgrel = heap_open(TriggerRelationId, AccessShareLock);
    ScanKeyInit(&key, ObjectIdAttributeNumber, BTEqualStrategyNumber, F_OIDEQ, ObjectIdGetDatum(object_id));
    tgscan = systable_beginscan(tgrel, TriggerOidIndexId, true, NULL, 1, &key);
    tuple = systable_getnext(tgscan);
    if (HeapTupleIsValid(tuple)) {
        Form_pg_trigger pg_trigger = (Form_pg_trigger) GETSTRUCT(tuple);
        if (OidIsValid(pg_trigger->tgrelid) &&
            pg_class_aclcheck(pg_trigger->tgrelid, user_id, ACL_SELECT) == ACLCHECK_OK) {
                result = pg_get_triggerdef_string(object_id);
        }
    }
    systable_endscan(tgscan);
    relation_close(tgrel, AccessShareLock);
    return result;
}

char* object_id_to_constraint_def(Oid object_id, Oid user_id)
{
    char* result = NULL;
    HeapTuple tuple = SearchSysCache1(CONSTROID, ObjectIdGetDatum(object_id));
    if (HeapTupleIsValid(tuple)) {
        Form_pg_constraint con = (Form_pg_constraint) GETSTRUCT(tuple);
        if (OidIsValid(con->conrelid) && con->contype == 'c' &&
            (pg_class_aclcheck(con->conrelid, user_id, ACL_SELECT) == ACLCHECK_OK)) {
                result = pg_get_constraintdef_string(object_id);
            }
        ReleaseSysCache(tuple);
    }
    return result;
}

bool check_input_valid(PG_FUNCTION_ARGS)
{
    int32 input1 = PG_GETARG_INT32(0);
    if (input1 < 0) {
        return false;
    }

    if (!PG_ARGISNULL(1)) {
        int32 database_id = (Oid)PG_GETARG_INT32(1);
        if (database_id != u_sess->proc_cxt.MyDatabaseId) {
            return false;
        }
    }
    return true;
}

Datum object_name(PG_FUNCTION_ARGS)
{
    Oid object_id;
    Oid user_id = GetUserId();
    text *result = NULL;
    object_info_t* object_info = NULL;

    if (!check_input_valid(fcinfo)) {
        PG_RETURN_NULL();
    }

    object_id = (Oid)PG_GETARG_INT32(0);
    oid_to_object_ptr oid_to_objects[MAX_OBJECT_FUNCTION] = {
        (oid_to_object_ptr)oid_to_pg_class_object,
        (oid_to_object_ptr)oid_to_pg_proc_object,
        (oid_to_object_ptr)oid_to_pg_type_object,
        (oid_to_object_ptr)oid_to_pg_trigger_object,
        (oid_to_object_ptr)oid_to_pg_constraint_object
        };

    for (int i = 0; i < MAX_OBJECT_FUNCTION; i++) {
        oid_to_object_ptr oid_to_object_ptr_func = oid_to_objects[i];
        object_info = oid_to_object_ptr_func(object_id, user_id);
        if (object_info != NULL) {
            result = cstring_to_text(object_info->object_name);
            FreeObjectInfo(object_info);
            PG_RETURN_NVARCHAR2_P((VarChar *) result);
        }
    }

    PG_RETURN_NULL();
}

Datum object_schema_name(PG_FUNCTION_ARGS)
{
    Oid object_id;
    Oid user_id = GetUserId();
    text *result = NULL;
    object_info_t* object_info = NULL;

    if (!check_input_valid(fcinfo)) {
        PG_RETURN_NULL();
    }

    object_id = (Oid)PG_GETARG_INT32(0);
    oid_to_object_ptr oid_to_objects[MAX_OBJECT_FUNCTION] = {
        (oid_to_object_ptr)oid_to_pg_class_object,
        (oid_to_object_ptr)oid_to_pg_proc_object,
        (oid_to_object_ptr)oid_to_pg_type_object,
        (oid_to_object_ptr)oid_to_pg_trigger_object,
        (oid_to_object_ptr)oid_to_pg_constraint_object
        };

    for (int i = 0; i < MAX_OBJECT_FUNCTION; i++) {
        oid_to_object_ptr oid_to_object_ptr_func = oid_to_objects[i];
        object_info = oid_to_object_ptr_func(object_id, user_id);
        if (object_info != NULL && OidIsValid(object_info->object_schema)) {
            Oid namespace_oid = object_info->object_schema;
            char* namespace_name = get_namespace_name(namespace_oid);
            if (pg_namespace_aclcheck(namespace_oid, user_id, ACL_USAGE) != ACLCHECK_OK) {
                PG_RETURN_NULL();
            }
            FreeObjectInfo(object_info);
            result = cstring_to_text(namespace_name);
            PG_RETURN_NVARCHAR2_P((VarChar *) result);
        }
    }

    PG_RETURN_NULL();
}

Datum object_define(PG_FUNCTION_ARGS)
{
    int32 object_id = PG_GETARG_INT32(0);
    Oid user_id = GetUserId();
    text *result = NULL;
    char* def;

    def = object_id_to_view_def(object_id, user_id);
    if (def == NULL) {
        def = object_id_to_proc_def(object_id, user_id);
    }

    if (def == NULL) {
        def = object_id_to_trigger_def(object_id, user_id);
    }

    if (def == NULL) {
        def = object_id_to_constraint_def(object_id, user_id);
    }

    if (def != NULL) {
        result = cstring_to_text(def);
        pfree_ext(def);
        PG_RETURN_VARCHAR_P(result);
    }
    PG_RETURN_NULL();
}

Datum sysdatetime(PG_FUNCTION_ARGS)
{
    return TimestampTzGetDatum(GetCurrentStatementStartTimestamp());
}

Datum eomonth(PG_FUNCTION_ARGS)
{
    int year = 0;
    int month = 0;
    int day = 0;
    int offset = 0;
    DateADT date;
    bool isOffsetGiven = false;
    bool isOriginalDateOutsideTSQLEndLimit = false;

    if (PG_ARGISNULL(0)) {
        PG_RETURN_NULL();
    } else {
        date = PG_GETARG_DATEADT(0);
    }
    if (!PG_ARGISNULL(1)) {
        offset = PG_GETARG_INT32(1);
        isOffsetGiven = true;
    }

    j2date(date + POSTGRES_EPOCH_JDATE, &year, &month, &day);
    isOriginalDateOutsideTSQLEndLimit = year < 1 || year > MAX_SHARK_YEAR;
    month += offset;

    if (month > 0) {
        year += (month - 1) / MONTHS_COUNT_IN_A_YEAR;
        month = (month - 1) % MONTHS_COUNT_IN_A_YEAR + 1;
    } else {
        year += month / MONTHS_COUNT_IN_A_YEAR - 1;
        month = month % MONTHS_COUNT_IN_A_YEAR + MONTHS_COUNT_IN_A_YEAR;
    }

    month++;
    if (year < 1 || year > MAX_SHARK_YEAR) {
        if (isOffsetGiven && !isOriginalDateOutsideTSQLEndLimit) {
            ereport(ERROR,
                (errcode(ERRCODE_DATETIME_FIELD_OVERFLOW),
                 errmsg("Adding a value to a 'date' column caused an overflow.")));
        } else {
            ereport(ERROR,
                (errcode(ERRCODE_DATETIME_FIELD_OVERFLOW),
                 errmsg("The date exceeds openGauss compatibility limits.")));
        }
    }
    date = date2j(year, month, 1) - POSTGRES_EPOCH_JDATE - 1;
    PG_RETURN_DATEADT(date);
}
Datum truncate_identifier(PG_FUNCTION_ARGS)
{
    char *ident = text_to_cstring(PG_GETARG_TEXT_PP(0));
    int len = strlen(ident);
    if (len >= NAMEDATALEN) {
        len = pg_mbcliplen(ident, len, NAMEDATALEN - 1);
        ident[len] = '\0';
    }
    PG_RETURN_TEXT_P(cstring_to_text(ident));
}

Datum translate_pg_type_to_tsql(PG_FUNCTION_ARGS)
{
    Oid pg_type = PG_GETARG_OID(0);
    char* type_name = NULL;
    if (OidIsValid(pg_type)) {
        type_name = get_typename(pg_type);
        for (int i = 0; i < TOTAL_TYPEMAP_COUNT; i++) {
            if (strcmp(g_type_maps[i].pg_typname, type_name) == 0) {
                pfree_ext(type_name);
                PG_RETURN_TEXT_P(cstring_to_text(g_type_maps[i].tsql_typname));
            }
        }
    }
    text* result = cstring_to_text(type_name);
    pfree_ext(type_name);
    PG_RETURN_TEXT_P(result);
}

bool is_precision_more_than_3(char* timestampstr)
{
    int len = strlen(timestampstr);
    int i = len - 1;
    while (i >= 0 && timestampstr[i] == ' ') {
        i--;
    }
    while (i >= 0 && timestampstr[i] != '.') {
        i--;
    }
    if (len - i > SHARK_MAX_DATETIME_PRECISION) {
        return true;
    }
    return false;
}

/*
 * the fsec precision of datetime2 is greater than 3
 */
bool check_is_datetime2(char* timestampstr, Datum timestamp_result)
{
    struct pg_tm tt;
    struct pg_tm* tm = &tt;
    Timestamp timestampVal = DatumGetTimestamp(timestamp_result);
    fsec_t fsec;
    if (timestamp2tm(timestampVal, NULL, tm, &fsec, NULL, NULL) != 0) {
        return true;
    }
    if (fsec != 0) {
        return is_precision_more_than_3(timestampstr);
    }
    return false;
}

bool check_is_time2(char* timestampstr, Datum timestamp_result)
{
    struct pg_tm tt;
    struct pg_tm* tm = &tt;
    TimeADT time = DatumGetTimeADT(timestamp_result);
    fsec_t fsec;
    if (time2tm(time, tm, &fsec) != 0) {
        return true;
    }
    if (fsec != 0) {
        return is_precision_more_than_3(timestampstr);
    }
    return false;
}

bool is_time(char* tmp)
{
    Datum time_result;
    bool is_error = false;
    PG_TRY();
    {
        time_result = DirectFunctionCall3(time_in, CStringGetDatum(tmp),
                                          ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
    }
    PG_CATCH();
    {
        FlushErrorState();
        is_error = true;
    }
    PG_END_TRY();
    
    if (!is_error) {
        is_error = check_is_time2(tmp, time_result);
    }
    return is_error;
}


Datum is_date(PG_FUNCTION_ARGS)
{
    if (PG_ARGISNULL(0)) {
        PG_RETURN_INT32(0);
    }
    bool is_error = false;
    Datum timestamp_result;
    char* tmp = NULL;
    struct pg_tm tt;
    struct pg_tm* tm = &tt;
    tmp = DatumGetCString(DirectFunctionCall1(textout, PG_GETARG_DATUM(0)));

    PG_TRY();
    {
        timestamp_result = DirectFunctionCall1(text_timestamp, PG_GETARG_DATUM(0));
    }
    PG_CATCH();
    {
        FlushErrorState();
        is_error = true;
    }
    PG_END_TRY();

    if (!is_error) {
        is_error = check_is_datetime2(tmp, timestamp_result);
    }

    if (!is_error) {
        pfree_ext(tmp);
        PG_RETURN_INT32(1);
    }

    is_error = is_time(tmp);
    pfree_ext(tmp);
    if (is_error) {
        PG_RETURN_INT32(0);
    }
    
    PG_RETURN_INT32(1);
}

bool is_column_exist(Oid rel_oid, char* colname)
{
    HeapTuple attTuple;
    bool attisdropped;
    attTuple = SearchSysCache2(ATTNAME, ObjectIdGetDatum(rel_oid), PointerGetDatum(colname));
    if (!HeapTupleIsValid(attTuple)) {
        return 0;
    }

    attisdropped = ((Form_pg_attribute)GETSTRUCT(attTuple))->attisdropped;
    ReleaseSysCache(attTuple);
    return !attisdropped;
}

char* formated_string(text *input)
{
    char* input_str = text_to_cstring(input);
    if (strlen(input_str) < 1) {
        return NULL;
    }

    input_str = downcase_truncate_identifier(input_str, strlen(input_str), true);
    input_str = remove_trailing_spaces(input_str);
    return input_str;
}

int get_charmaxlen(Oid rel_oid, char* colname)
{
    HeapTuple attTuple;
    int atttypmod;
    attTuple = SearchSysCache2(ATTNAME, ObjectIdGetDatum(rel_oid), PointerGetDatum(colname));
    if (!HeapTupleIsValid(attTuple)) {
        return -1;
    }

    atttypmod = ((Form_pg_attribute)GETSTRUCT(attTuple))->atttypmod;
    ReleaseSysCache(attTuple);
    if (atttypmod > 0) {
        return atttypmod - NUMERIC_PRECISION_BASE_LEN;
    }
    return -1;
}

int get_allow_null(Oid rel_oid, char* colname)
{
    HeapTuple attTuple;
    bool attnotnull;
    attTuple = SearchSysCache2(ATTNAME, ObjectIdGetDatum(rel_oid), PointerGetDatum(colname));
    if (!HeapTupleIsValid(attTuple)) {
        return -1;
    }

    attnotnull = ((Form_pg_attribute)GETSTRUCT(attTuple))->attnotnull;
    ReleaseSysCache(attTuple);
    return !attnotnull;
}

int get_column_id(Oid rel_oid, char* colname)
{
    HeapTuple attTuple;
    int column_id;
    attTuple = SearchSysCache2(ATTNAME, ObjectIdGetDatum(rel_oid), PointerGetDatum(colname));
    if (!HeapTupleIsValid(attTuple)) {
        return -1;
    }

    column_id = ((Form_pg_attribute)GETSTRUCT(attTuple))->attnum;
    ReleaseSysCache(attTuple);
    return column_id;
}

int get_is_compute(Oid rel_oid, char* colname)
{
    HeapTuple attTuple;
    int attnum;
    Relation attrdef_rel;
    ScanKeyData scankeys[TWO];
    SysScanDesc scan;
    HeapTuple tuple;
    bool is_compute = false;
    attnum = get_column_id(rel_oid, colname);

    attrdef_rel = heap_open(AttrDefaultRelationId, AccessShareLock);
    ScanKeyInit(&scankeys[0], Anum_pg_attrdef_adrelid, BTEqualStrategyNumber, F_OIDEQ, ObjectIdGetDatum(rel_oid));
    ScanKeyInit(&scankeys[1], Anum_pg_attrdef_adnum, BTEqualStrategyNumber, F_INT2EQ, Int16GetDatum(attnum));
    scan = systable_beginscan(attrdef_rel, AttrDefaultIndexId, true, NULL, TWO, scankeys);

    /* There should be at most one matching tuple, but we loop anyway */
    while (HeapTupleIsValid(tuple = systable_getnext(scan))) {
        bool isnull = false;
        Datum val = fastgetattr(tuple, Anum_pg_attrdef_adgencol, attrdef_rel->rd_att, &isnull);
        if (isnull) {
            continue;
        }
        bool is_gencol = DatumGetBool(val);
        if (is_gencol) {
            is_compute = true;
            break;
        }
    }
    systable_endscan(scan);
    heap_close(attrdef_rel, AccessShareLock);

    return is_compute;
}

int get_is_identity(Oid rel_oid, char* colname)
{
    bool is_identity = false;
    char* relname = get_rel_name(rel_oid);

    bool isRetNull = false;
    Datum result = DirectCall2(&isRetNull, pg_get_serial_sequence, InvalidOid,
                               CStringGetTextDatum(relname), CStringGetTextDatum(colname));
    if (isRetNull) {
        pfree_ext(relname);
        return 0;
    }
    
    char* seqname =  text_to_cstring(DatumGetTextPP(result));
    if (StrEndWith(seqname, "_seq_identity")) {
        is_identity = true;
    }
    pfree_ext(relname);
    pfree_ext(seqname);
    return is_identity;
}

int get_is_hidden(Oid rel_oid, char* colname)
{
    int attnum;
    attnum = get_column_id(rel_oid, colname);
    if (attnum >= 0) {
        return 1;
    } else {
        return 0;
    }
}

int get_ordinal(Oid rel_oid, char* colname)
{
    HeapTuple attr_tuple;
    Form_pg_attribute attr_form;
    int col_position = 0;
    int current_pos = 0;
    ScanKeyData scan_key[1];
    SysScanDesc scan_desc;
    Relation rel_att;
    ScanKeyInit(&scan_key[0], Anum_pg_attribute_attrelid, BTEqualStrategyNumber, F_OIDEQ, ObjectIdGetDatum(rel_oid));
    rel_att = heap_open(AttributeRelationId, AccessShareLock);
    scan_desc = systable_beginscan(rel_att, AttributeRelidNumIndexId, true, NULL, 1, scan_key);
    while (HeapTupleIsValid(attr_tuple = systable_getnext(scan_desc))) {
        attr_form = (Form_pg_attribute)GETSTRUCT(attr_tuple);
        if (attr_form->attisdropped || attr_form->attnum <= 0) {
            continue;
        }
    
        current_pos++;
        if (strcmp(NameStr(attr_form->attname), colname) == 0) {
            col_position = current_pos;
            break;
        }
    }
    systable_endscan(scan_desc);
    heap_close(rel_att, AccessShareLock);

    return col_position;
}

int get_column_type_andtymod(Oid rel_oid, char* colname, Oid* type, int* tymod)
{
    HeapTuple attTuple;
    int column_id;
    attTuple = SearchSysCache2(ATTNAME, ObjectIdGetDatum(rel_oid), PointerGetDatum(colname));
    if (!HeapTupleIsValid(attTuple)) {
        return -1;
    }

    *type = ((Form_pg_attribute)GETSTRUCT(attTuple))->atttypid;
    *tymod = ((Form_pg_attribute)GETSTRUCT(attTuple))->atttypmod;
    ReleaseSysCache(attTuple);
    return 0;
}

int get_type_no_mod_scale(Oid typeoid)
{
    int scale = -1;
    switch (typeoid) {
        case SMALLDATETIMEOID:
            scale = 0;
            break;

        case TIMESTAMPOID:
        case TIMESTAMPTZOID:
            scale = TIMESTAMP_DEFAULT_SCALE;
            break;

        case DATEOID:
            scale = 0;
            break;

        case TIMEOID:
        case TIMETZOID:
            scale = TIMESTAMP_DEFAULT_SCALE;
            break;

        case NUMERICOID:
            scale = NUMERIC_DEFAULT_SCALE;
            break;

        case CASHOID:
            scale = CASH_DEFAULT_SCALE;
            break;

        default:
            scale = 0;
            break;
    }

    return scale;
}

int get_type_scale(Oid typeoid, int typmod)
{
    if (typmod == -1) {
        return get_type_no_mod_scale(typeoid);
    }
    int scale = -1;
    switch (typeoid) {
        case NUMERICOID:
            scale = ((typmod - NUMERIC_PRECISION_BASE_LEN)) & NUMERIC_PRECISION_MASK;
            break;

        case TIMESTAMPOID:
        case TIMESTAMPTZOID:
        case TIMEOID:
        case TIMETZOID:
            scale = typmod;
            break;

        case CHAROID:
        case VARCHAROID:
        case BPCHAROID:
        case TEXTOID:
            scale = typmod - NUMERIC_PRECISION_BASE_LEN;
            break;

        default:
            scale = typmod;
            break;
    }
    return scale;
}

int get_scale(Oid rel_oid, char* colname)
{
    Oid typid = 0;
    int32 typmod = 0;
    if (get_column_type_andtymod(rel_oid, colname, &typid, &typmod) == -1) {
        return -1;
    }
    return get_type_scale(typid, typmod);
}

int get_type_no_mod_precision(Oid typeoid)
{
    int precision = -1;
    switch (typeoid) {
        case SMALLDATETIMEOID:
            precision = SMALLDATETIME_DEFAULT_PRECISION;
            break;

        case TIMESTAMPOID:
        case TIMESTAMPTZOID:
            precision = DATETIME_DEFAULT_PRECISION;
            break;

        case DATEOID:
            precision = DATE_DEFAULT_PRECISION;
            break;

        case TIMEOID:
        case TIMETZOID:
            precision = TIME_DEFAULT_PRECISION;
            break;

        case FLOAT8OID:
            precision = FLOAT8_DEFAULT_PRECISION;
            break;

        case FLOAT4OID:
            precision = FLOAT4_DEFAULT_PRECISION;
            break;

        case NUMERICOID:
            precision = NUMERIC_DEFAULT_PRECISION;
            break;

        case CASHOID:
            precision = CASH_DEFAULT_PRECISION;
            break;

        case INT8OID:
            precision = INT8_DEFAULT_PRECISION;
            break;

        case INT4OID:
            precision = INT4_DEFAULT_PRECISION;
            break;

        case INT2OID:
            precision = INT2_DEFAULT_PRECISION;
            break;

        case INT1OID:
            precision = INT1_DEFAULT_PRECISION;
            break;

        case BITOID:
            precision = BIT_DEFAULT_PRECISION;
            break;

        default:
            precision = 0;
            break;
    }

    return precision;
}

int get_type_precision(Oid typeoid, int typmod)
{
    if (typmod == -1) {
        return get_type_no_mod_precision(typeoid);
    }
    int precision = -1;
    switch (typeoid) {
        case NUMERICOID:
            precision = ((typmod - NUMERIC_PRECISION_BASE_LEN) >> SHORT_LENGTH) & NUMERIC_PRECISION_MASK;
            break;

        case SMALLDATETIMEOID:
            precision = SMALLDATETIME_DEFAULT_PRECISION;
            break;

        case TIMESTAMPOID:
        case TIMESTAMPTZOID:
            {
                if (typmod == 0) {
                    precision = DATETIME_MIN_PRECISION;
                } else {
                    precision = DATETIME_MIN_PRECISION + 1 + typmod;
                }
            }
            break;

        case TIMEOID:
        case TIMETZOID:
            {
                if (typmod == 0) {
                    precision = TIME_MIN_PRECISION;
                } else {
                    precision = TIME_MIN_PRECISION + 1 + typmod;
                }
            }
            break;

        case CHAROID:
        case VARCHAROID:
        case BPCHAROID:
        case TEXTOID:
            precision = typmod - NUMERIC_PRECISION_BASE_LEN;
            break;

        default:
            precision = typmod;
            break;
    }
    return precision;
}

int get_precision(Oid rel_oid, char* colname)
{
    Oid typid = 0;
    int32 typmod = 0;
    if (get_column_type_andtymod(rel_oid, colname, &typid, &typmod) == -1) {
        return -1;
    }
    return get_type_precision(typid, typmod);
}

Datum columnproperty(PG_FUNCTION_ARGS)
{
    int32 object_id = PG_GETARG_INT32(0);
    char* column_name = formated_string(PG_GETARG_TEXT_PP(1));
    char* property = formated_string(PG_GETARG_TEXT_PP(2));
    int result = -1;

    if (column_name == NULL || property == NULL || !is_column_exist(object_id, column_name)) {
        pfree_ext(column_name);
        pfree_ext(property);
        PG_RETURN_NULL();
    }

    if (strcmp("charmaxlen", property) == 0) {
        result = get_charmaxlen(object_id, column_name);
    } else if (strcmp("allowsnull", property) == 0) {
        result = get_allow_null(object_id, column_name);
    } else if (strcmp("iscomputed", property) == 0) {
        result = get_is_compute(object_id, column_name);
    } else if (strcmp("columnid", property) == 0) {
        result = get_column_id(object_id, column_name);
    } else if (strcmp("ishidden", property) == 0) {
        result = get_is_hidden(object_id, column_name);
    } else if (strcmp("isidentity", property) == 0) {
        result = get_is_identity(object_id, column_name);
    } else if (strcmp("ordinal", property) == 0) {
        result = get_ordinal(object_id, column_name);
    } else if (strcmp("precision", property) == 0) {
        result = get_precision(object_id, column_name);
    } else if (strcmp("scale", property) == 0) {
        result = get_scale(object_id, column_name);
    }

    pfree_ext(column_name);
    pfree_ext(property);
    if (result == -1) {
        PG_RETURN_NULL();
    }

    PG_RETURN_INT32(result);
}

