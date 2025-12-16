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
 * ogai_onnx_embedding.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai_onnx_embedding.cpp
 *
 * ---------------------------------------------------------------------------------------
 */

#include "postgres.h"
#include "knl/knl_variable.h"
#include "utils/memutils.h"
#include "access/datavec/ogai_model_framework.h"
#include "access/datavec/ogai_onnx_mgr.h"
#include "access/datavec/ogai_onnx_embedding.h"


EmbeddingClient* CreateONNXEmbeddingClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) ONNXEmbeddingClient(config);
}

Vector** ONNXEmbeddingClient::BatchEmbed(OGAIString* texts, size_t textNum, int* dim)
{
    ONNXModelDesc* modelDesc = NULL;

    modelDesc = ONNX_MODEL_MGR->GetONNXModelDesc(config->modelName, config->baseUrl);
    if (!modelDesc || !modelDesc->handle) {
        modelDesc = ONNX_MODEL_MGR->LoadONNXModel(config->modelName, config->baseUrl);
    };

    RWLockGuard guard(modelDesc->mutex, LW_SHARED);
    float** embeddings = (float**)palloc0(textNum * sizeof(float*));
    for (size_t i = 0; i < textNum; i++) {
        embeddings[i] = (float*)palloc0(modelDesc->dim * sizeof(float));
    }

    int ret = ONNXEmbeddingInferBatch(modelDesc->handle, texts, textNum, embeddings, modelDesc->dim);
    if (ret != 0) {
        elog(ERROR, "ONNXEmbeddingInferBatch failed");
    }

    Vector** results = (Vector**)palloc0(textNum * sizeof(Vector*));
    for (size_t i = 0; i < textNum; i++) {
        Vector* vec = InitVector(modelDesc->dim);
        errno_t rc = memcpy_s(vec->x, modelDesc->dim * sizeof(float), embeddings[i], modelDesc->dim * sizeof(float));
        securec_check_c(rc, "\0", "\0");
        results[i] = vec;
    }
    return results;
}

char* ONNXEmbeddingClient::BuildEmbeddingReqBody(OGAIString* texts, size_t textNum)
{
    elog(ERROR, "ONNXEmbeddingClient::BuildEmbeddingReqBody not implemented");
}

void ONNXEmbeddingClient::ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum)
{
    elog(ERROR, "ONNXEmbeddingClient::BuildEmbeddingReqBody not implemented");
}
