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
#include "access/datavec/ogai_textsplitter_wrapper.h"
#include "access/datavec/vector.h"
#include "access/datavec/ogai_worker.h"
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
    FuncCallContext  *funcctx;
    if (SRF_IS_FIRSTCALL()) {
        MemoryContext oldcontext;
        Datum      *elements;
        bool       *nulls;
        int         numDocs;
        TupleDesc tupdesc = NULL;

        funcctx = SRF_FIRSTCALL_INIT();
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        tupdesc = CreateTemplateTupleDesc(3, false, TableAmHeap);
        TupleDescInitEntry(tupdesc, (AttrNumber)1, "origin_index", INT4OID, -1, 0);
        TupleDescInitEntry(tupdesc, (AttrNumber)2, "document", TEXTOID, -1, 0);
        TupleDescInitEntry(tupdesc, (AttrNumber)3, "rerank_score", FLOAT8OID, -1, 0);

        char *query = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(0)));
        ArrayType *arr = PG_GETARG_ARRAYTYPE_P(1);
        char *model = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(2)));

        if (ARR_NDIM(arr) != 1) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("array must be 1-dimensional")));
        }

        deconstruct_array(arr, TEXTOID, -1, false, 'i',
                          &elements, &nulls, &numDocs);

        if (numDocs == 0) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("document array cannot be empty")));
        }

        OGAIString *docArray = (OGAIString*) palloc(sizeof(OGAIString) * numDocs);
        for (int i = 0; i < numDocs; i++) {
            if (nulls[i]) {
                MemoryContextSwitchTo(oldcontext);
                ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("null document at index %d", i)));
            }
            docArray[i] = text_to_cstring(DatumGetVarCharPP(elements[i]));
        }

        InputDocuments input_docs = { .docArray = docArray, .docCount = numDocs };

        ModelConfig config;
        GenerateModelConfig(&config, model);
        RerankClient *client = CreateRerankClient(&config);
        if (!client) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                 errmsg("failed to create rerank client for model: %s", model)));
        }

        RerankResults *results = client->Rerank(query, &input_docs);
        if (!results) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                 errmsg("failed to rerank documents")));
        }

        funcctx->user_fctx = results;
        funcctx->max_calls = results->docCount;
        funcctx->tuple_desc = BlessTupleDesc(tupdesc);
        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();
    if (funcctx->call_cntr < funcctx->max_calls) {
        Datum values[3];
        bool nulls[3] = {false, false, false};

        RerankResults *results = (RerankResults*) funcctx->user_fctx;
        RerankDocument *doc = &results->documents[funcctx->call_cntr];

        values[0] = Int32GetDatum(doc->originIndex);
        values[1] = CStringGetTextDatum(doc->document);
        values[2] = Float8GetDatum(doc->rerankScore);

        HeapTuple tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);
        Datum result = HeapTupleGetDatum(tuple);

        SRF_RETURN_NEXT(funcctx, result);
    } else {
        SRF_RETURN_DONE(funcctx);
    }
}

Datum ogai_chunk(PG_FUNCTION_ARGS)
{
    FuncCallContext* funcctx;

    if (SRF_IS_FIRSTCALL()) {
        MemoryContext oldcontext;
        TupleDesc tupdesc = NULL;

        funcctx = SRF_FIRSTCALL_INIT();
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        tupdesc = CreateTemplateTupleDesc(2, false, TableAmHeap);
        TupleDescInitEntry(tupdesc, (AttrNumber)1, "chunk_id", INT4OID, -1, 0);
        TupleDescInitEntry(tupdesc, (AttrNumber)2, "chunk", TEXTOID, -1, 0);

        char* document = text_to_cstring(DatumGetVarCharPP(PG_GETARG_DATUM(0)));
        int maxChunkSize = PG_GETARG_INT32(1);

        int maxChunkOverlap = 0;
        if (PG_NARGS() > 2 && !PG_ARGISNULL(2)) {
            maxChunkOverlap = PG_GETARG_INT32(2);
        }

        if (maxChunkSize <= 0) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("maxChunkSize must be greater than 0")));
        }

        if (maxChunkOverlap < 0 || maxChunkOverlap >= maxChunkSize) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("maxChunkOverlap must be between 0 and maxChunkSize")));
        }

        TextSplitterWrapper splitter(maxChunkSize, maxChunkOverlap);
        ChunkResult* returnChunksResult = splitter.split(document);

        if (returnChunksResult == NULL || returnChunksResult->chunkNum == 0) {
            MemoryContextSwitchTo(oldcontext);
            ereport(ERROR,
                (errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                 errmsg("failed to split document into chunks")));
        }

        funcctx->user_fctx = returnChunksResult;
        funcctx->max_calls = returnChunksResult->chunkNum;
        funcctx->tuple_desc = BlessTupleDesc(tupdesc);

        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();
    if (funcctx->call_cntr < funcctx->max_calls) {
        Datum values[2];
        bool nulls[2] = {false, false};

        ChunkResult* ctx = (ChunkResult*) funcctx->user_fctx;
        Chunk* chunk = &ctx->chunks[funcctx->call_cntr];

        values[0] = Int32GetDatum(funcctx->call_cntr);
        values[1] = CStringGetTextDatum(chunk->chunk);

        HeapTuple tuple = heap_form_tuple(funcctx->tuple_desc, values, nulls);
        Datum result = HeapTupleGetDatum(tuple);

        SRF_RETURN_NEXT(funcctx, result);
    }
    SRF_RETURN_DONE(funcctx);
}

Datum ogai_notify(PG_FUNCTION_ARGS)
{
/* Wake up the Undo Launcher */
    Oid dboid = u_sess->proc_cxt.MyDatabaseId;
    int actualOgaiWorkers = MAX_OGAI_WORKERS;
    for (int i = 0; i < actualOgaiWorkers; i++) {
        if (!OidIsValid(t_thrd.ogailauncher_cxt.ogaiWorkerShmem->target_dbs[i])) {
            t_thrd.ogailauncher_cxt.ogaiWorkerShmem->target_dbs[i] = dboid;
            break;
        }
    }
    SetLatch(&t_thrd.ogailauncher_cxt.ogaiWorkerShmem->latch);
}