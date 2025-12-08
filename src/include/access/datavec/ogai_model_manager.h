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
 * ogai_model_manager.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_model_manager.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_MODEL_MANAGER_H
#define OGAI_MODEL_MANAGER_H

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "nodes/execnodes.h"
#include "access/datavec/vector.h"
#include "access/datavec/ogai_qwen.h"
#include "access/datavec/ogai_model_framework.h"

typedef EmbeddingClient* (*EmbeddingClientCreator)(ModelConfig*);
typedef GenerateClient* (*GenerateClientCreator)(ModelConfig*);
typedef RerankClient* (*RerankClientCreator)(ModelConfig*);

typedef struct {
    EmbeddingClientCreator createEmbedding;
    GenerateClientCreator createGenerate;
    RerankClientCreator createRerank;
} ProviderClientCreators;

void GenerateModelConfig(ModelConfig* config, const char* model);
EmbeddingClient* CreateEmbeddingClient(ModelConfig* config);
GenerateClient* CreateGenerateClient(ModelConfig* config);
RerankClient* CreateRerankClient(ModelConfig* config);

#endif // OGAI_MODEL_MANAGER_H
