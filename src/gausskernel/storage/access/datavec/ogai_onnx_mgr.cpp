/*
* Copyright (c) 2025 Huawei Technologies Co.,Ltd.
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
 * ogai_onnx_mgr.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_onnx_mgr.h
 *
 * ---------------------------------------------------------------------------------------
 */

#include "postgres.h"
#include "knl/knl_variable.h"
#include "utils/memutils.h"
#include "miscadmin.h"
#include "utils/timestamp.h"
#include "access/datavec/ogai_onnx_wrapper.h"
#include "access/datavec/ogai_onnx_mgr.h"

#define OGAI_NUM_PARTITIONS 2
ONNXModelMgr* ONNXModelMgr::onnxModelMgr = NULL;

static inline void InitONNXModelTag(ONNXModelTag* tag, const char* modelKey, const char* ownerName)
{
    errno_t rc;
    
    rc = memset_s(tag, sizeof(ONNXModelTag), 0, sizeof(ONNXModelTag));
    securec_check(rc, "\0", "\0");
    
    rc = strncpy_s(tag->modelKey, NAMEDATALEN, modelKey, NAMEDATALEN - 1);
    securec_check(rc, "\0", "\0");
    
    rc = strncpy_s(tag->ownerName, NAMEDATALEN, ownerName, NAMEDATALEN - 1);
    securec_check(rc, "\0", "\0");
}

/*
 * @Description: get Singleton Instance of onnx model mgr.
 * @Return: onnx model mgr.
 */
ONNXModelMgr* ONNXModelMgr::GetInstance(void)
{
    Assert(onnxModelMgr != NULL);
    if (!onnxModelMgr->IsInit()) {
        ereport(ERROR, (errmsg("onnx model mgr: onnx model mgr is not init")));
    }
    return onnxModelMgr;
}

void ONNXModelMgr::NewSingletonInstance(void)
{
    if (IsUnderPostmaster)
        return;
    onnxModelMgr = New(CurrentMemoryContext) ONNXModelMgr;

    onnxModelMgr->onnxModelMgrCtx = AllocSetContextCreate(
                                    g_instance.instance_context,
                                    "onnx model context",
                                    ALLOCSET_SMALL_MINSIZE,
                                    ALLOCSET_SMALL_INITSIZE,
                                    ALLOCSET_DEFAULT_MAXSIZE,
                                    SHARED_CONTEXT);
    onnxModelMgr->onnxEnvHandle = ONNXEnvCreate();
    if (onnxModelMgr->onnxEnvHandle == NULL) {
        onnxModelMgr->isInit = false;
        MemoryContextDelete(onnxModelMgr->onnxModelMgrCtx);
        ereport(WARNING, (errmsg("onnx model mgr: onnx env create failed")));
        return;
    }

    MemoryContext oldcontext = MemoryContextSwitchTo(onnxModelMgr->onnxModelMgrCtx);
    int ret = pthread_rwlock_init(&onnxModelMgr->mutex, nullptr);
    if (ret != 0) {
        onnxModelMgr->isInit = false;
        MemoryContextSwitchTo(oldcontext);
        MemoryContextDelete(onnxModelMgr->onnxModelMgrCtx);
        ereport(WARNING, (errmsg("onnx model mgr pthread_rwlock_init failed")));
        return;
    }

    HASHCTL info;
    int hash_flags = HASH_CONTEXT | HASH_EXTERN_CONTEXT | HASH_ELEM | HASH_FUNCTION | HASH_PARTITION;
    errno_t rc = memset_s(&info, sizeof(info), 0, sizeof(info));
    securec_check(rc, "\0", "\0");

    info.keysize = sizeof(ONNXModelTag);
    info.entrysize = sizeof(ONNXModelHashEntry);
    info.hash = tag_hash;
    info.hcxt = onnxModelMgr->onnxModelMgrCtx;
    info.num_partitions = NUM_CACHE_BUFFER_PARTITIONS / OGAI_NUM_PARTITIONS;
    onnxModelMgr->onnxModelHash = hash_create(
        "onnx model Lookup Table", ONNX_MODEL_HASH_CAPACITY, &info, hash_flags);
    MemoryContextSwitchTo(oldcontext);
    onnxModelMgr->isInit = true;
}


bool ONNXModelMgr::IsInit()
{
    return isInit;
}

ONNXModelDesc* ONNXModelMgr::GetONNXModelDescByKey(const char* modelKey, const char* ownerName)
{
    RWLockGuard guard(mutex, LW_SHARED);
    
    ONNXModelTag tag;
    InitONNXModelTag(&tag, modelKey, ownerName);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_FIND, NULL);
    if (entry == NULL || entry->modelDesc == NULL) {
        return NULL;
    }
    return entry->modelDesc;
}

ONNXModelDesc* ONNXModelMgr::LoadONNXModelByKey(const char* modelKey, const char* ownerName,
                                                 const char* modelPath)
{
    ONNXModelTag tag;
    bool found = false;

    RWLockGuard guard(mutex, LW_EXCLUSIVE);
    InitONNXModelTag(&tag, modelKey, ownerName);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_ENTER, &found);
    if (found && entry->modelDesc && entry->modelDesc->handle) {
        elog(WARNING, "[LOAD] Model already loaded");
        return entry->modelDesc;
    }

    MemoryContext oldcontext = MemoryContextSwitchTo(onnxModelMgrCtx);
    entry->modelDesc = (ONNXModelDesc*)palloc0(sizeof(ONNXModelDesc));
    MemoryContextSwitchTo(oldcontext);
    
    int ret = pthread_rwlock_init(&entry->modelDesc->mutex, nullptr);
    if (ret != 0) {
        pfree(entry->modelDesc);
        hash_search(onnxModelHash, &tag, HASH_REMOVE, NULL);
        ereport(ERROR, (errmsg("onnx model mgr: pthread_rwlock_init failed")));
    }
    
    entry->modelDesc->handle = ONNXLoadModel(onnxEnvHandle, modelPath, NULL, &entry->modelDesc->dim);
    if (!entry->modelDesc->handle) {
        pthread_rwlock_destroy(&entry->modelDesc->mutex);
        pfree(entry->modelDesc);
        hash_search(onnxModelHash, &tag, HASH_REMOVE, NULL);
        ereport(ERROR, (errmsg("onnx model mgr: failed to load ONNX model: model_key=%s, path=%s",
            modelKey, modelPath)));
    }
    elog(DEBUG1, "Loaded ONNX model: model_key=%s, owner=%s, dim=%d, path=%s",
         modelKey, ownerName, entry->modelDesc->dim, modelPath);
    return entry->modelDesc;
}

void ONNXModelMgr::UnloadONNXModelByKey(const char* modelKey, const char* ownerName)
{
    ONNXModelTag tag;

    RWLockGuard guard(mutex, LW_EXCLUSIVE);
    InitONNXModelTag(&tag, modelKey, ownerName);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_FIND, NULL);
    if (entry == NULL || entry->modelDesc == NULL) {
        ereport(ERROR, (errmsg("onnx model mgr: can not find model: model_key=%s, owner=%s",
                               modelKey, ownerName)));
        return;
    }
    
    if (entry->modelDesc->handle) {
        ONNXUnloadModel(entry->modelDesc->handle);
    }
    
    pthread_rwlock_destroy(&entry->modelDesc->mutex);
    pfree(entry->modelDesc);
    entry->modelDesc = NULL;
    
    hash_search(onnxModelHash, &tag, HASH_REMOVE, NULL);
    
    elog(LOG, "[UNLOAD] Successfully unloaded: model_key=%s, owner=%s", modelKey, ownerName);
}
