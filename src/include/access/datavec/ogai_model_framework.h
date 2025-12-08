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
 * ogai_model_framework.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_model_framework.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_MODEL_FRAMEWORK_H
#define OGAI_MODEL_FRAMEWORK_H

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "nodes/execnodes.h"
#include "access/datavec/vector.h"

typedef char* OGAIString;

typedef enum {
    PROVIDER_OPENAI,
    PROVIDER_QWEN,
    PROVIDER_OLLAMA,
    PROVIDER_ONNX,

    /* number of provider */
    PROVIDER_COUNT
} ModelProvider;

typedef struct ModelConfig {
    ModelProvider provider;
    char* apiKey;
    char* modelName;
    char* baseUrl;
    size_t maxBatch;
    size_t timeout;
    size_t dimension;
} ModelConfig;

typedef char* OGAIString;

typedef struct RerankDocument {
    OGAIString document;
    double rerankScore;
    int originIndex;
} RerankDocument;

typedef struct RerankResults {
    RerankDocument* documents;
    int docCount;
} RerankResults;

typedef struct InputDocuments {
    OGAIString* docArray;
    int docCount;
} InputDocuments;

class EmbeddingClient : public BaseObject {
public:
    Vector** BatchEmbed(OGAIString* texts, size_t textNum, int* dim);
    virtual char* BuildEmbeddingReqBody(OGAIString* texts, size_t textNum) = 0;
    virtual void ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum) = 0;

    ModelConfig* config;
};

class GenerateClient : public BaseObject {
public:
    OGAIString Generate(OGAIString query);
    virtual OGAIString BuildGenerateReqBody(OGAIString query) = 0;
    virtual OGAIString ParseGenerateRespBody(OGAIString respBody) = 0;

    ModelConfig* config;
};

class RerankClient : public BaseObject {
public:
    RerankResults* Rerank(OGAIString query, InputDocuments* documents);
    virtual OGAIString BuildRerankReqBody(OGAIString query, InputDocuments* inputDocuments) = 0;
    virtual RerankResults* ParseRerankRespBody(OGAIString respBody, InputDocuments* inputDocuments) = 0;

    ModelConfig* config;
};

#endif // OGAI_MODEL_FRAMEWORK_H
