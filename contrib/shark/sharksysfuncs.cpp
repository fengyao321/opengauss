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