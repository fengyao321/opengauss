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
 * ogai.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai.cpp
 *
 * ---------------------------------------------------------------------------------------
 */

#include "postgres.h"
#include "funcapi.h"
#include "utils/memutils.h"
#include "utils/elog.h"
#include "access/datavec/ogai_model_framework.h"
#include "access/datavec/ogai_model_manager.h"
#include "access/datavec/vector.h"
#include "access/datavec/ogai.h"

Datum ogai_embedding(PG_FUNCTION_ARGS)
{
    char* text = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(0)));
    char* model = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(1)));
    int dim = PG_GETARG_INT32(2);

    ModelConfig config;
    config.dimension = dim;
    config.maxBatch = 1;
    GenerateModelConfig(&config, model);
    EmbeddingClient* client = CreateEmbeddingClient(&config);
    Vector** vectors = client->BatchEmbed(&text, 1, &dim);
    PG_RETURN_POINTER(vectors[0]);
}

Datum ogai_generate(PG_FUNCTION_ARGS)
{
    char* answer = NULL;
    char* query = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(0)));
    char* model = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(1)));

    ModelConfig config;
    GenerateModelConfig(&config, model);
    GenerateClient* client = CreateGenerateClient(&config);
    if (!client) {
        ereport(ERROR,
                (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                 errmsg("failed to create generate client for model: %s", model)));
    }
    
    answer = client->Generate(query);
    if (!answer) {
        ereport(ERROR,
                (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                 errmsg("failed to generate answer for query")));
    }
    
    PG_RETURN_TEXT_P(cstring_to_text(answer));
}

Datum ogai_rerank(PG_FUNCTION_ARGS)
{
    Datum result = NULL;
    return result;
}

