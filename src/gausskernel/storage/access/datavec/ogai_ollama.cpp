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
 * ogai_ollama.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai_ollama.cpp
 *
 * ---------------------------------------------------------------------------------------
 */

#include "utils/palloc.h"
#include "cjson/cJSON.h"
#include "keymgr/comm/security_utils.h"
#include "keymgr/comm/security_http.h"
#include "keymgr/comm/security_httpscan.h"
#include "access/datavec/ogai_utils.h"
#include "access/datavec/ogai_ollama.h"

EmbeddingClient* CreateOllamaEmbeddingClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) OllamaEmbeddingClient(config);
}

GenerateClient* CreateOllamaGenerateClient(ModelConfig* config)
{
    if (!config) return NULL;
    return New(CurrentMemoryContext) OllamaGenerateClient(config);
}

RerankClient* CreateOllamaRerankClient(ModelConfig* config)
{
    elog(LOG, "Ollama does not support rerank api.");
    return NULL;
}

char* OllamaEmbeddingClient::BuildEmbeddingReqBody(OGAIString* texts, size_t textNum)
{
    char* body = NULL;

    cJSON* root = cJSON_CreateObject();
    if (root == NULL) {
        elog(ERROR, "build embedding api body error for ollama.");
    }

    cJSON_AddStringToObject(root, "model", config->modelName);
    
    cJSON* input = cJSON_CreateArray();
    if (input == NULL) {
        cJSON_Delete(root);
        elog(ERROR, "build embedding input array error for ollama.");
        return NULL;
    }
    
    for (size_t i = 0; i < textNum; i++) {
        cJSON_AddItemToArray(input, cJSON_CreateString(texts[i]));
    }
    cJSON_AddItemToObject(root, "input", input);

    char* jsonStr = cJSON_PrintUnformatted(root);
    if (jsonStr == NULL) {
        cJSON_Delete(root);
        elog(ERROR, "build embedding json body error for ollama.");
        return NULL;
    }

    body = pg_strdup(jsonStr);
    cJSON_free(jsonStr);
    cJSON_Delete(root);
    return body;
}

void OllamaEmbeddingClient::ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum)
{
    cJSON* root = cJSON_Parse(respBody);
    if (root == NULL) {
        elog(ERROR, "parse embedding response json body error for ollama: %s.", respBody);
    }
    
    cJSON* embeddings = cJSON_GetObjectItem(root, "embeddings");
    if (embeddings == NULL || !cJSON_IsArray(embeddings)) {
        cJSON_Delete(root);
        elog(ERROR, "parse embeddings response error for ollama: %s.", respBody);
    }

    size_t embeddingCount = cJSON_GetArraySize(embeddings);
    if (embeddingCount != textNum) {
        cJSON_Delete(root);
        elog(ERROR,
            "The number of texts[%zu] and embeddings[%zu] is inconsistent for ollama.", textNum, embeddingCount);
    }

    for (size_t i = 0; i < embeddingCount; i++) {
        cJSON* embedding = cJSON_GetArrayItem(embeddings, i);
        if (embedding == NULL || !cJSON_IsArray(embedding)) {
            cJSON_Delete(root);
            elog(ERROR, "embedding at index %zu is not an array for ollama.", i);
        }
        
        config->dimension = cJSON_GetArraySize(embedding);
        if (config->dimension == 0) {
            cJSON_Delete(root);
            elog(ERROR, "embedding dimension is 0 at index %zu for ollama.", i);
        }

        Vector* vec = InitVector(config->dimension);
        for (size_t j = 0; j < config->dimension; j++) {
            cJSON* val = cJSON_GetArrayItem(embedding, j);
            if (val == NULL) {
                cJSON_Delete(root);
                elog(ERROR, "embedding value at index [%zu][%zu] is NULL for ollama.", i, j);
            }
            vec->x[j] = (float)val->valuedouble;
        }
        
        results[start + i] = vec;
    }
    
    cJSON_Delete(root);
}

OGAIString OllamaGenerateClient::BuildGenerateReqBody(OGAIString query)
{
    char* body = NULL;
    cJSON* root = cJSON_CreateObject();
    if (root == NULL) {
        elog(ERROR, "build generate api body error for ollama.");
    }

    cJSON_AddStringToObject(root, "model", config->modelName);
    cJSON* messages = cJSON_CreateArray();
    if (messages == NULL) {
        cJSON_Delete(root);
        elog(ERROR, "build generate api messages error for ollama.");
        return NULL;
    }

	// add system prompt
    cJSON* system_msg = cJSON_CreateObject();
    cJSON_AddStringToObject(system_msg, "role", "system");
    cJSON_AddStringToObject(system_msg, "content", "You are a helpful assistant.");
    cJSON_AddItemToArray(messages, system_msg);

    cJSON* user_msg = cJSON_CreateObject();
    cJSON_AddStringToObject(user_msg, "role", "user");
    cJSON_AddStringToObject(user_msg, "content", query);
    cJSON_AddItemToArray(messages, user_msg);

    cJSON_AddItemToObject(root, "messages", messages);
    cJSON_AddBoolToObject(root, "stream", false);

    char* jsonStr = cJSON_PrintUnformatted(root);
    if (jsonStr == NULL) {
        cJSON_Delete(root);
        elog(ERROR, "build generate json body error for ollama.");
        return NULL;
    }

    body = pg_strdup(jsonStr);
    cJSON_free(jsonStr);
    cJSON_Delete(root);
    return body;
}

OGAIString OllamaGenerateClient::ParseGenerateRespBody(OGAIString respBody)
{
    char* result = NULL;

    cJSON* root = cJSON_Parse(respBody);
    if (root == NULL) {
        elog(ERROR, "parse generate api response json body error for ollama: %s.", respBody);
    }

    cJSON* message = cJSON_GetObjectItem(root, "message");
    if (message == NULL || !cJSON_IsObject(message)) {
        cJSON_Delete(root);
        elog(ERROR, "parse generate api response message error for ollama: %s.", respBody);
    }

    cJSON* content = cJSON_GetObjectItem(message, "content");
    if (content == NULL || !cJSON_IsString(content) || content->valuestring == NULL) {
        cJSON_Delete(root);
        elog(ERROR, "parse generate api response content error for ollama.");
    }

    result = pg_strdup(content->valuestring);
    cJSON_Delete(root);
    return result;
}

OGAIString OllamaRerankClient::BuildRerankReqBody(OGAIString query, InputDocuments* inputDocuments)
{
    elog(ERROR, "Ollama does not support rerank api now.");
    return NULL;
}

RerankResults* OllamaRerankClient::ParseRerankRespBody(OGAIString respBody, InputDocuments* inputDocuments)
{
    elog(ERROR, "Ollama does not support rerank api now.");
    return NULL;
}
