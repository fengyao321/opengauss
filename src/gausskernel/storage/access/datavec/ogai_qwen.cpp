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
 * ogai_qwen.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai_qwen.cpp
 *
 * ---------------------------------------------------------------------------------------
 */

#include "utils/palloc.h"
#include "cjson/cJSON.h"
#include "keymgr/comm/security_utils.h"
#include "keymgr/comm/security_http.h"
#include "keymgr/comm/security_httpscan.h"
#include "access/datavec/ogai_utils.h"
#include "access/datavec/ogai_qwen.h"

EmbeddingClient* CreateQwenEmbeddingClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) QwenEmbeddingClient(config);
}

GenerateClient* CreateQwenGenerateClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) QwenGenerateClient(config);
}

RerankClient* CreateQwenRerankClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) QwenRerankClient(config);
}

char* QwenEmbeddingClient::BuildEmbeddingReqBody(OGAIString* texts, size_t textNum)
{
    return NULL;
}

void QwenEmbeddingClient::ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum)
{
    return ;
}

OGAIString QwenGenerateClient::BuildGenerateReqBody(OGAIString query)
{
    return NULL;
}

OGAIString QwenGenerateClient::ParseGenerateRespBody(OGAIString respBody)
{
    return NULL;
}

OGAIString QwenRerankClient::BuildRerankReqBody(OGAIString query, InputDocuments* inputDocuments)
{
    return NULL;
}

RerankResults* QwenRerankClient::ParseRerankRespBody(OGAIString respBody, InputDocuments* inputDocuments)
{
    return NULL;
}
