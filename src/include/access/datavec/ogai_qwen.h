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
 * ogai_qwen.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_qwen.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_QWEN_H
#define OGAI_QWEN_H

#include "access/datavec/ogai_model_framework.h"

EmbeddingClient* CreateQwenEmbeddingClient(ModelConfig* config);
GenerateClient* CreateQwenGenerateClient(ModelConfig* config);
RerankClient* CreateQwenRerankClient(ModelConfig* config);

class QwenEmbeddingClient : public EmbeddingClient {
public:
    QwenEmbeddingClient(ModelConfig* modelConfig)
    {
        config = modelConfig;
    }
    char* BuildEmbeddingReqBody(OGAIString* texts, size_t textNum) override;
    void ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum) override;
};

class QwenGenerateClient : public GenerateClient {
public:
    QwenGenerateClient(ModelConfig* modelConfig)
    {
        config = modelConfig;
    }
    OGAIString Generate(OGAIString query);
    OGAIString BuildGenerateReqBody(OGAIString query) override;
    OGAIString ParseGenerateRespBody(OGAIString respBody)  override;
};

class QwenRerankClient : public RerankClient {
public:
    QwenRerankClient(ModelConfig* modelConfig)
    {
        config = modelConfig;
    }

    RerankResults* Rerank(OGAIString query, InputDocuments* documents);
    OGAIString BuildRerankReqBody(OGAIString query, InputDocuments* inputDocuments)  override;
    RerankResults* ParseRerankRespBody(OGAIString respBody, InputDocuments* inputDocuments) override;
};

#endif // OGAI_QWEN_H
