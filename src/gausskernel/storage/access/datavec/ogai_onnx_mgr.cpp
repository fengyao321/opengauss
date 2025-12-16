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
#include "access/datavec/ogai_onnx_wrapper.h"
#include "access/datavec/ogai_onnx_mgr.h"

#define OGAI_NUM_PARTITIONS 2
ONNXModelMgr* ONNXModelMgr::onnxModelMgr = NULL;

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

ONNXModelDesc* ONNXModelMgr::GetONNXModelDesc(const char* modelName, const char* modelPath)
{
    RWLockGuard guard(mutex, LW_SHARED);
    ONNXModelTag tag;
    memset_s(&tag, sizeof(tag), 0, sizeof(tag));
    memcpy_s(tag.modelName, NAMEDATALEN, modelName, NAMEDATALEN - 1);
    memcpy_s(tag.modelPath, MAXPATH, modelPath, MAXPATH - 1);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_FIND, NULL);
    if (entry == NULL || entry->modelDesc == NULL) {
        return NULL;
    }
    return entry->modelDesc;
}

ONNXModelDesc* ONNXModelMgr::LoadONNXModel(const char* modelName, const char* modelPath)
{
    RWLockGuard guard(mutex, LW_EXCLUSIVE);
    bool found = false;
    ONNXModelTag tag;
    memcpy_s(tag.modelName, NAMEDATALEN, modelName, NAMEDATALEN - 1);
    memcpy_s(tag.modelPath, MAXPATH, modelPath, MAXPATH - 1);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_ENTER, &found);
    if (found) {
        ereport(ERROR,
            (errmsg("onnx model mgr: onnx model already exists, model name: %s, model path: %s.", modelName,
                modelPath)));
        return NULL;
    }

    MemoryContext oldcontext = MemoryContextSwitchTo(onnxModelMgr->onnxModelMgrCtx);
    entry->modelDesc = (ONNXModelDesc*)palloc0(sizeof(ONNXModelDesc));
    MemoryContextSwitchTo(oldcontext);
    int ret = pthread_rwlock_init(&entry->modelDesc->mutex, nullptr);
    if (ret != 0) {
        pfree(entry->modelDesc);
        hash_search(onnxModelHash, &tag, HASH_REMOVE, NULL);
        ereport(ERROR, (errmsg("onnx model mgr: pthread_rwlock_init failed")));
    }
    entry->modelDesc->handle = ONNXLoadModel(onnxEnvHandle, modelPath, NULL, &entry->modelDesc->dim);
    return entry->modelDesc;
}

void ONNXModelMgr::UnloadONNXModel(const char* modelName, const char* modelPath)
{
    RWLockGuard guard(mutex, LW_EXCLUSIVE);
    ONNXModelTag tag;
    memcpy_s(tag.modelName, NAMEDATALEN, modelName, NAMEDATALEN - 1);
    memcpy_s(tag.modelPath, MAXPATH, modelPath, MAXPATH - 1);
    ONNXModelHashEntry* entry = (ONNXModelHashEntry*)hash_search(onnxModelHash, &tag, HASH_FIND, NULL);
    if (entry == NULL || entry->modelDesc == NULL) {
        ereport(ERROR,
            (errmsg("onnx model mgr: can not find onnx model, model name: %s, model path: %s.", modelName, modelPath)));
    }
    ONNXUnloadModel(entry->modelDesc->handle);
    pfree(entry->modelDesc);
    hash_search(onnxModelHash, &tag, HASH_REMOVE, NULL);
}
