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
* ogai_vector_processor.cpp
*
* IDENTIFICATION
*        src/gausskernel/storage/access/datavec/ogai_vector_processor.cpp
*
* ---------------------------------------------------------------------------------------
*/

#include "postgres.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "access/xact.h"
#include "utils/jsonb.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include "storage/lock/lwlock.h"
#include "utils/elog.h"
#include "utils/numeric.h"
#include "utils/builtins.h"
#include "fmgr.h"
#include "utils/snapmgr.h"
#include "utils/datum.h"
#include "catalog/pg_type.h"
#include "access/datavec/ogai_model_manager.h"
#include "access/datavec/ogai_model_framework.h"
#include "access/datavec/ogai_textsplitter_wrapper.h"
#include "access/datavec/ogai_vector_processor.h"

/* Internal configuration parameters */
#define SQL_BUF_SIZE       4096            /* Size of the SQL statement buffer */
#define PK_VALUE_BUF_SIZE  64              /* Buffer size for pk_value */
#define CONTENT_BUF_SIZE   8192            /* Buffer size for document content */
#define FAIL_REASON_BUF_SIZE 1024          /* Buffer size for failure reason description */

/* Ogai task config */
typedef struct {
    char model_key[64];         /* embedding model key */
    char src_schema[64];         /* source table schema */
    char src_table[64];          /* source table name */
    char src_col[64];            /* Name of the text column to be vectorized (input column) */
    char primary_key[64];        /* Primary key column name of the source table */
    char table_method[32];       /* Storage mode ("append" or "join") */
    int dim;                     /* Vector dimension (default: 1536) */
    int max_chunk_size;          /* Text chunk size (default: 1000) */
    int max_chunk_overlap;       /* Chunk overlap size (default: 200) */
} OgaiTaskConfig;

typedef enum {
    FAIL_TYPE_INVALID_JSON,               /* Invalid JSON format (not retryable) */
    FAIL_TYPE_JSON_NOT_ARRAY,             /* JSON is not an array (not retryable) */
    FAIL_TYPE_JSON_ELEM_COUNT_ERROR,      /* Incorrect number of JSON elements (not retryable) */
    FAIL_TYPE_TASK_ID_INVALID,            /* Invalid task ID (not retryable) */
    FAIL_TYPE_PK_VALUE_EMPTY,             /* pk_value is an empty string (not retryable) */
    FAIL_TYPE_TASK_CONFIG_NOT_FOUND,      /* Task configuration not found (not retryable) */
    FAIL_TYPE_DOCUMENT_NOT_FOUND,         /* Document not found (not retryable) */
    FAIL_TYPE_DOCUMENT_CONTENT_NULL,      /* Document content is null (not retryable) */
    FAIL_TYPE_SPI_ERROR,                  /* SPI execution error (retryable) */
    FAIL_TYPE_SQL_EXEC_FAILED,            /* SQL execution failed (retryable) */
    FAIL_TYPE_EMBEDDING_GENERATE_FAILED,  /* Embedding generation failed (retryable) */
    FAIL_TYPE_UNKNOWN                     /* Unknown error (retryable) */
} OgaiFailType;

/* Fetch task configuration */
static bool GetTaskConfig(
    int taskId,
    OgaiTaskConfig *config,
    OgaiFailType *failType,
    char *failReason,
    int failReasonLen
)
{
    int spiRc = 0;
    char sql[SQL_BUF_SIZE];
    HeapTuple tuple;
    TupleDesc tupdesc;
    char *value;
    errno_t nRet = 0;
    bool hasTransaction = IsTransactionState();

    *failType = FAIL_TYPE_UNKNOWN;
    nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1, "unkonwn error");
    securec_check_ss_c(nRet, "", "");
    errno_t rc = memset_s(config, sizeof(OgaiTaskConfig), 0, sizeof(OgaiTaskConfig));
    securec_check(rc, "\0", "\0");

    if (taskId <= 0) {
        *failType = FAIL_TYPE_TASK_ID_INVALID;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "task_id invalid: %d", taskId);
        securec_check_ss_c(nRet, "", "");
        return false;
    }

    MemoryContext tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                "OgaiTaskConfigCtx", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(tmpCtx);

    if (!hasTransaction) {
        start_xact_command();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT model_key, src_schema, src_table, src_col, primary_key, "
        "method, dim, max_chunk_size, max_chunk_overlap "
        "FROM ogai.vectorize_tasks "
        "WHERE task_id = $1 LIMIT 1;");
    securec_check_ss_c(nRet, "", "");
    Oid paramTypes[1] = {INT4OID};
    SPIPlanPtr plan = SPI_prepare(sql, 1, paramTypes);
    if (plan == NULL) {
        *failType = FAIL_TYPE_SPI_ERROR;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "Preprocessing task configuration SQL failed:%s", sql);
        securec_check_ss_c(nRet, "", "");

        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }

        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    Datum params[1] = {Int32GetDatum(taskId)};
    char paramNulls[1] = {' '};
    spiRc = SPI_execute_plan(plan, params, paramNulls, true, 0);
    SPI_freeplan(plan);

    if (spiRc != SPI_OK_SELECT) {
        *failType = FAIL_TYPE_SPI_ERROR;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Failed to execute task configuration query: SQL=%s, return code=%d",
                sql, spiRc);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }

        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    if (SPI_processed == 0) {
        *failType = FAIL_TYPE_TASK_CONFIG_NOT_FOUND;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "Task configuration not found: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }

        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    tuple = SPI_tuptable->vals[0];
    tupdesc = SPI_tuptable->tupdesc;

    /* get model_key, 1 is the first result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 1);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                         "Task configuration model_key is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->model_key, sizeof(config->model_key), value, sizeof(config->model_key) - 1);
    securec_check(nRet, "", "");
    config->model_key[sizeof(config->model_key) - 1] = '\0';

    /* get src_schema, 2 is the second result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 2);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "Task configuration src_schema is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->src_schema, sizeof(config->src_schema), value, sizeof(config->src_schema) - 1);
    securec_check(nRet, "", "");
    config->src_schema[sizeof(config->src_schema) - 1] = '\0';

    /* get src_table, 3 is the third result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 3);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Task configuration src_table is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->src_table, sizeof(config->src_table), value, sizeof(config->src_table) - 1);
    securec_check(nRet, "", "");
    config->src_table[sizeof(config->src_table) - 1] = '\0';

    /* get src_col, 4 is the fourth result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 4);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                 "Task configuration src_col is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->src_col, sizeof(config->src_col), value, sizeof(config->src_col) - 1);
    securec_check(nRet, "", "");
    config->src_col[sizeof(config->src_col) - 1] = '\0';

    /* get primary_key, 5 is the fifth result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 5);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                 "Task configuration primary_key is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->primary_key, sizeof(config->primary_key),
                value, sizeof(config->primary_key) - 1);
    securec_check(nRet, "", "");
    config->primary_key[sizeof(config->primary_key) - 1] = '\0';

    /* get table_method, 6 is the sixth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 6);
    if (value == NULL || strlen(value) == 0) {
        nRet = strncpy_s(config->table_method, sizeof(config->table_method),
                    "append", sizeof(config->table_method) - 1);
        securec_check(nRet, "", "");
    } else {
        nRet = strncpy_s(config->table_method, sizeof(config->table_method),
                    value, sizeof(config->table_method) - 1);
        securec_check(nRet, "", "");
    }
    config->table_method[sizeof(config->table_method) - 1] = '\0';

    /* get dim default 1536, 7 is the eventh result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 7);
    config->dim = (value && strlen(value) > 0) ? atoi(value) : 1536;

    /* get max_chunk_size default 1000, 8 is the eighth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 8);
    config->max_chunk_size = (value && strlen(value) > 0) ? atoi(value) : 1000;

    /* get max_chunk_overlap default 200, 9 is the ninth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 9);
    config->max_chunk_overlap = (value && strlen(value) > 0) ? atoi(value) : 200;

    if (!hasTransaction) {
        PopActiveSnapshot();
        finish_xact_command();
    }
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(tmpCtx);

    return true;
}

/* getdocument content */
static bool GetDocumentContent(
    OgaiTaskConfig *config,
    int pkValue,
    char *content,
    int contentLen,
    OgaiFailType *failType,
    char *failReason,
    int failReasonLen
)
{
    int spiRc = 0;
    errno_t nRet = 0;
    char sql[SQL_BUF_SIZE];
    HeapTuple tuple;
    TupleDesc tupdesc;
    char *value;
    bool hasTransaction = IsTransactionState();

    *failType = FAIL_TYPE_UNKNOWN;
    nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1, "unknown error");
    securec_check_ss_c(nRet, "", "");
    errno_t rc = memset_s(content, contentLen, 0, contentLen);
    securec_check(rc, "\0", "\0");

    errno_t ret = memset_s(sql, sizeof(sql), 0, sizeof(sql));
    securec_check(ret, "\0", "\0");

    MemoryContext tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                        "OgaiDocumentContentCtx", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(tmpCtx);

    if (!hasTransaction) {
        start_xact_command();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT %s FROM %s.%s WHERE %s = $1 LIMIT 1;",
        config->src_col, config->src_schema, config->src_table, config->primary_key);
    securec_check_ss_c(nRet, "", "");

    Oid paramTypes[1] = {INT4OID};
    SPIPlanPtr plan = SPI_prepare(sql, 1, paramTypes);
    if (plan == NULL) {
        *failType = FAIL_TYPE_SPI_ERROR;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "Failed to preprocess document query SQL: %s", sql);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    Datum params[1] = {Int32GetDatum(pkValue)};
    char paramNulls[1] = {' '};
    spiRc = SPI_execute_plan(plan, params, paramNulls, true, 0);
    SPI_freeplan(plan);

    if (spiRc != SPI_OK_SELECT) {
        *failType = FAIL_TYPE_SPI_ERROR;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                        "Failed to execute document query: SQL=%s, return code=%d", sql, spiRc);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    if (SPI_processed == 0) {
        *failType = FAIL_TYPE_DOCUMENT_NOT_FOUND;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Document not found: %s.%s(%s=%d)",
                config->src_schema, config->src_table, config->primary_key, pkValue);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    /* get document content */
    tuple = SPI_tuptable->vals[0];
    tupdesc = SPI_tuptable->tupdesc;
    value = SPI_getvalue(tuple, tupdesc, 1);
    if (value == NULL || strlen(value) == 0) {
        *failType = FAIL_TYPE_DOCUMENT_CONTENT_NULL;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
            "Document content is empty: %s.%s(%s=%d)",
            config->src_schema, config->src_table, config->primary_key, pkValue);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    /* Securely copy content and truncate if necessary */
    nRet = strncpy_s(content, contentLen, value, contentLen - 1);
    securec_check(nRet, "", "");
    content[contentLen - 1] = '\0';

    if (strlen(content) >= contentLen - 1) {
        ereport(WARNING, (errmsg("Document content is too long and has been truncated: %s.%s(%s=%d)",
            config->src_schema, config->src_table, config->primary_key, pkValue)));
    }

    if (!hasTransaction) {
        PopActiveSnapshot();
        finish_xact_command();
    }
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(tmpCtx);
    return true;
}

/* Generate embeddings and update the table */
static bool GenerateAndUpdateEmbedding(
    OgaiTaskConfig *config,
    int pkValue,
    const char *content,
    OgaiFailType *failType,
    char *failReason,
    int failReasonLen
)
{
    int spiRc = 0;
    char sql[SQL_BUF_SIZE];
    errno_t nRet = 0;
    *failType = FAIL_TYPE_UNKNOWN;
    nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1, "unknown error");
    securec_check_ss_c(nRet, "", "");
    if (content == NULL || strlen(content) == 0) {
        *failType = FAIL_TYPE_DOCUMENT_CONTENT_NULL;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Document content is empty; unable to generate embedding: pk_value=%d", pkValue);
        securec_check_ss_c(nRet, "", "");
        return false;
    }

    MemoryContext tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                    "OgaiGenerateEmbeddingCtx", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(tmpCtx);

    /* Append mode: update the ogai_embedding column in the original table */
    if (strcmp(config->table_method, "append") == 0) {
        /* Generate vectors directly at C level to avoid nested SPI calls */
        ModelConfig modelConfig;
        modelConfig.dimension = config->dim;
        modelConfig.maxBatch = 1;
        
        /* Get model configuration (uses existing SPI connection, no duplicate connection) */
        AsyncGenerateModelConfig(&modelConfig, config->model_key);
        
        /* Create embedding client and generate vectors */
        EmbeddingClient* client = CreateEmbeddingClient(&modelConfig);
        if (!client) {
            *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                    "Failed to create embedding client for model: %s", config->model_key);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }
        
        int dim = config->dim;
        char* text = const_cast<char*>(content);
        Vector** vectors = client->BatchEmbed(&text, 1, &dim);
        if (!vectors || !vectors[0]) {
            *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                        "Failed to generate embedding vector");
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }
        
        /* Get the Datum value of the vector */
        Datum vectorDatum = PointerGetDatum(vectors[0]);
        errno_t rc = memset_s(sql, sizeof(sql), 0, sizeof(sql));
        securec_check(rc, "\0", "\0");
        nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
            "UPDATE %s.%s "
            "SET ogai_embedding = $1 "
            "WHERE %s = $2;",
            config->src_schema, config->src_table, config->primary_key);
        securec_check_ss_c(nRet, "", "");
        Oid updateParamTypes[2] = {VECTOROID, INT4OID};
        SPIPlanPtr updatePlan = SPI_prepare(sql, 2, updateParamTypes);
        if (updatePlan == NULL) {
            *failType = FAIL_TYPE_SPI_ERROR;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                    "Failed to preprocess vector update SQL (append mode): %s", sql);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }

        Datum updateParams[2] = {
            vectorDatum,
            Int32GetDatum(pkValue)
        };
        char updateParamNulls[2] = {' ', ' '};
        spiRc = SPI_execute_plan(updatePlan, updateParams, updateParamNulls, false, 0);
        SPI_freeplan(updatePlan);

        if (spiRc != SPI_OK_UPDATE) {
            *failType = FAIL_TYPE_SQL_EXEC_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                     "Failed to execute vector update (append mode): SQL=%s, return code=%d", sql, spiRc);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }
        if (SPI_processed == 0) {
            *failType = FAIL_TYPE_SQL_EXEC_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "No rows affected by vector update (append mode): %s.%s(%s=%d)",
                config->src_schema, config->src_table, config->primary_key, pkValue);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }

    /* Join mode: update the associated table */
    } else if (strcmp(config->table_method, "join") == 0) {
        char joinTable[128];
        nRet = snprintf_s(joinTable, sizeof(joinTable), sizeof(joinTable) - 1,
                        "%s_vector", config->src_table);
        securec_check_ss_c(nRet, "", "");
        /* Use C++ class directly for text chunking to avoid SQL calls */
        TextSplitterWrapper splitter(config->max_chunk_size, config->max_chunk_overlap);
        ChunkResult* chunks = splitter.split(content);
        
        if (chunks == NULL || chunks->chunkNum == 0) {
            *failType = FAIL_TYPE_SPI_ERROR;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                        "Failed to split document into chunks");
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }

        /* Prepare embedding client */
        ModelConfig modelConfig;
        modelConfig.dimension = config->dim;
        modelConfig.maxBatch = 1;
        AsyncGenerateModelConfig(&modelConfig, config->model_key);
        
        EmbeddingClient* client = CreateEmbeddingClient(&modelConfig);
        if (!client) {
            *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Failed to create embedding client for model: %s", config->model_key);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }
        
        /* Prepare INSERT statement */
        nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
            "INSERT INTO %s.%s ("
                "%s, chunk_id, chunk_text, ogai_embedding) "
            "VALUES ($1, $2, $3, $4)",
            config->src_schema, joinTable, config->primary_key);
        securec_check_ss_c(nRet, "", "");
        Oid insertParamTypes[4] = {INT4OID, INT4OID, TEXTOID, VECTOROID};
        SPIPlanPtr insertPlan = SPI_prepare(sql, 4, insertParamTypes);
        if (insertPlan == NULL) {
            *failType = FAIL_TYPE_SPI_ERROR;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                        "Failed to preprocess INSERT SQL: %s", sql);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }
        
        /* Iterate through each chunk */
        for (int i = 0; i < chunks->chunkNum; i++) {
            Chunk* chunk = &chunks->chunks[i];
            char* chunkText = chunk->chunk;
            int chunkId = i + 1;
            
            /* Generate vector for each chunk */
            int dim = config->dim;
            char* text = chunkText;
            Vector** vectors = client->BatchEmbed(&text, 1, &dim);
            if (!vectors || !vectors[0]) {
                *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
                nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                        "Failed to generate embedding for chunk %d", chunkId);
                securec_check_ss_c(nRet, "", "");
                SPI_freeplan(insertPlan);
                MemoryContextSwitchTo(oldCtx);
                MemoryContextDelete(tmpCtx);
                return false;
            }
            
            Datum vectorDatum = PointerGetDatum(vectors[0]);
            Datum insertParams[4] = {
                Int32GetDatum(pkValue),
                Int32GetDatum(chunkId),
                CStringGetTextDatum(chunkText),
                vectorDatum
            };
            char insertParamNulls[4] = {' ', ' ', ' ', ' '};
            
            spiRc = SPI_execute_plan(insertPlan, insertParams, insertParamNulls, false, 0);
            if (spiRc != SPI_OK_INSERT) {
                *failType = FAIL_TYPE_SPI_ERROR;
                nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                            "Failed to insert chunk %d", chunkId);
                securec_check_ss_c(nRet, "", "");
                SPI_freeplan(insertPlan);
                MemoryContextSwitchTo(oldCtx);
                MemoryContextDelete(tmpCtx);
                return false;
            }
        }
        SPI_freeplan(insertPlan);
    } else {
        *failType = FAIL_TYPE_TASK_CONFIG_NOT_FOUND;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Unsupported storage mode: %s (only 'append' and 'join' are supported)",
                 config->table_method);
        securec_check_ss_c(nRet, "", "");
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(tmpCtx);
    return true;
}

static bool UpdateQueueStatus(
    int64 msgId,
    const char *status,
    int retryCount,
    const char *failReason
)
{
    int spiRc = 0;
    char sql[SQL_BUF_SIZE];
    bool hasTransaction = IsTransactionState();
    errno_t nRet = 0;
    errno_t ret = memset_s(sql, sizeof(sql), 0, sizeof(sql));
    securec_check(ret, "\0", "\0");

    if (!hasTransaction) {
        start_xact_command();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "UPDATE ogai.vectorize_queue "
        "SET status = $1::text::ogai.queue_status, retry_count = $2, "
            "vt = CURRENT_TIMESTAMP, update_at = CURRENT_TIMESTAMP, "
            "fail_reason = $3 "
        "WHERE msg_id = $4;");
    securec_check_ss_c(nRet, "", "");
    Oid paramTypes[4] = {TEXTOID, INT4OID, TEXTOID, INT8OID};
    SPIPlanPtr plan = SPI_prepare(sql, 4, paramTypes);
    if (plan == NULL) {
        ereport(WARNING, (errmsg("Failed to preprocess queue status update SQL: %s", sql)));
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        return false;
    }
    Datum params[4] = {
        CStringGetTextDatum(status),
        Int32GetDatum(retryCount),
        CStringGetTextDatum(failReason),
        Int64GetDatum(msgId)
    };
    char paramNulls[4] = {' ', ' ', ' ', ' '};
    spiRc = SPI_execute_plan(plan, params, paramNulls, false, 0);
    SPI_freeplan(plan);

    if (spiRc != SPI_OK_UPDATE || SPI_processed == 0) {
        ereport(WARNING, (errmsg("Failed to update queue status: msg_id=%ld, status=%s, fail_reason=%s",
            msgId, status, failReason)));

        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        return false;
    }
    if (!hasTransaction) {
        PopActiveSnapshot();
        finish_xact_command();
    }
    return true;
}

static bool DeleteQueueRecord(int64 msgId)
{
    int spiRc = 0;
    char sql[SQL_BUF_SIZE];
    errno_t nRet = 0;
    bool hasTransaction = IsTransactionState();
    if (!hasTransaction) {
        start_xact_command();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }
    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "DELETE FROM ogai.vectorize_queue WHERE msg_id = $1;");
    securec_check_ss_c(nRet, "", "");
    Oid paramTypes[1] = {INT8OID};
    SPIPlanPtr plan = SPI_prepare(sql, 1, paramTypes);
    if (plan == NULL) {
        ereport(WARNING, (errmsg("Failed to preprocess queue record deletion SQL: msg_id=%ld", msgId)));
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        return false;
    }

    Datum params[1] = {Int64GetDatum(msgId)};
    char paramNulls[1] = {' '};
    spiRc = SPI_execute_plan(plan, params, paramNulls, false, 0);
    SPI_freeplan(plan);

    if (spiRc != SPI_OK_DELETE || SPI_processed == 0) {
        ereport(WARNING, (errmsg("Failed to delete queue record: msg_id=%ld, return code=%d, rows affected=%d",
            msgId, spiRc, SPI_processed)));
        if (!hasTransaction) {
            PopActiveSnapshot();
            finish_xact_command();
        }
        return false;
    }
    ereport(DEBUG1, (errmsg("Successfully deleted queue record: msg_id=%ld", msgId)));
    if (!hasTransaction) {
        PopActiveSnapshot();
        finish_xact_command();
    }
    return true;
}

static bool IsRetryable(OgaiFailType failType)
{
    switch (failType) {
        case FAIL_TYPE_SPI_ERROR:
        case FAIL_TYPE_SQL_EXEC_FAILED:
        case FAIL_TYPE_EMBEDDING_GENERATE_FAILED:
        case FAIL_TYPE_UNKNOWN:
            return true;
        default:
            return false;
    }
}

/* Initialize environment and execute queue query */
static bool InitEnvAndQueryQueue(int *spiRc, MemoryContext oldCtx, MemoryContext spiCtx)
{
    char sql[SQL_BUF_SIZE];
    errno_t nRet;

    *spiRc = SPI_connect();
    if (*spiRc != SPI_OK_CONNECT) {
        ereport(ERROR, (errmsg(
                "Vector processor initialization failed: SPI connection failed (return code=%d)", *spiRc)));
        return false;
    }

    start_xact_command();
    PushActiveSnapshot(GetTransactionSnapshot(false));

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT msg_id, task_id, pk_value, retry_count "
        "FROM ogai.vectorize_queue "
        "WHERE status = 'ready' AND retry_count < %d "
        "ORDER BY vt ASC LIMIT 10;",
        VECTOR_PROCESSOR_MAX_RETRY_COUNT);
    securec_check_ss_c(nRet, "", "");

    *spiRc = SPI_execute(sql, true, 0);
    if (*spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        PopActiveSnapshot();
        finish_xact_command();
        SPI_finish();
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(spiCtx);
        return false;
    }
    return true;
}

/* Extract task tuple fields and perform basic validation */
static bool ExtractTaskFields(HeapTuple tuple, TupleDesc tupdesc, int64 *msgId,
                              int *taskId, int *pkValue, int *retryCount)
{
    Datum datum;
    bool isNull;

    /* get msg_id, 1 is the first result returned by the SQL statement */
    datum = SPI_getbinval(tuple, tupdesc, 1, &isNull);
    if (isNull) {
        ereport(WARNING, (errmsg("Task msg_id is null; skipping processing")));
        return false;
    }
    *msgId = DatumGetInt64(datum);

    /* get task_id, 2 is the second result returned by the SQL statement */
    datum = SPI_getbinval(tuple, tupdesc, 2, &isNull);
    if (isNull) {
        ereport(WARNING, (errmsg("Task msg_id=%ld has empty task_id; marking as failed", *msgId)));
        UpdateQueueStatus(*msgId, "failed", 0, "task_id is null");
        return false;
    }
    *taskId = DatumGetInt32(datum);

    /* get pk_value, 3 is the third result returned by the SQL statement */
    datum = SPI_getbinval(tuple, tupdesc, 3, &isNull);
    if (isNull) {
        ereport(WARNING, (errmsg("Task msg_id=%ld has empty pk_value; marking as failed", *msgId)));
        UpdateQueueStatus(*msgId, "failed", 0, "pk_value is null ");
        return false;
    }
    *pkValue = DatumGetInt32(datum);

    /* get retry_count, 4 is the fourth result returned by the SQL statement */
    datum = SPI_getbinval(tuple, tupdesc, 4, &isNull);
    *retryCount = isNull ? 0 : DatumGetInt32(datum);

    return true;
}

/* Handle embedding generation and result processing */
static void HandleEmbeddingGeneration(int64 msgId, int taskId, int pkValue, int retryCount,
                                      OgaiTaskConfig *taskConfig, const char *content,
                                      OgaiFailType *failType, char *failReason, size_t reasonSize)
{
    bool success = false;
    PG_TRY();
    {
        BeginInternalSubTransaction(NULL);
        success = GenerateAndUpdateEmbedding(taskConfig, pkValue, content, failType, failReason, reasonSize);
        if (success) {
            ReleaseCurrentSubTransaction();
            DeleteQueueRecord(msgId);
            ereport(LOG, (errmsg("Task success: msg_id=%ld, task_id=%d, pk_value=%d, mode=%s",
                msgId, taskId, pkValue, taskConfig->table_method)));
        } else {
            RollbackAndReleaseCurrentSubTransaction();
            ereport(WARNING, (errmsg("Vector gen failed for msg_id=%ld: %s", msgId, failReason)));
            
            BeginInternalSubTransaction(NULL);
            PG_TRY() {
                UpdateQueueStatus(msgId, IsRetryable(*failType) ? "ready" : "failed", retryCount + 1, failReason);
                ReleaseCurrentSubTransaction();
            } PG_CATCH() {
                RollbackAndReleaseCurrentSubTransaction();
                ereport(WARNING, (errmsg("Failed to update status for msg_id=%ld", msgId)));
            } PG_END_TRY();
        }
    }
    PG_CATCH();
    {
        if (IsSubTransaction()) {
            RollbackAndReleaseCurrentSubTransaction();
        }
        errno_t nRet = snprintf_s(failReason, reasonSize,
                                "Unexpected exception: msg_id=%ld, task_id=%d", msgId, taskId);
        securec_check_ss_c(nRet, "", "");
        ereport(WARNING, (errmsg("%s", failReason)));
        
        BeginInternalSubTransaction(NULL);
        PG_TRY() {
            UpdateQueueStatus(msgId, "failed", retryCount + 1, failReason);
            ReleaseCurrentSubTransaction();
        } PG_CATCH() {
            RollbackAndReleaseCurrentSubTransaction();
            ereport(WARNING, (errmsg("Failed to update status in exception for msg_id=%ld", msgId)));
        } PG_END_TRY();
    }
    PG_END_TRY();
}

/* Process core business logic for a single task */
static void ProcessTaskLogic(int64 msgId, int taskId, int pkValue, int retryCount)
{
    OgaiFailType failType = FAIL_TYPE_UNKNOWN;
    char failReason[FAIL_REASON_BUF_SIZE] = {0};
    OgaiTaskConfig taskConfig = {0};
    char content[CONTENT_BUF_SIZE] = {0};
    bool success = false;

    /* Mark task as processing */
    if (!UpdateQueueStatus(msgId, "processing", retryCount, "")) {
        ereport(WARNING, (errmsg("Failed to mark task msg_id=%ld as 'processing'; skipping", msgId)));
        return;
    }

    /* Get task configuration */
    if (!GetTaskConfig(taskId, &taskConfig, &failType, failReason, sizeof(failReason))) {
        ereport(WARNING, (errmsg("Failed to fetch config for msg_id=%ld: %s", msgId, failReason)));
        UpdateQueueStatus(msgId, IsRetryable(failType) ? "ready" : "failed", retryCount + 1, failReason);
        return;
    }

    /* Get document content */
    if (!GetDocumentContent(&taskConfig, pkValue, content, sizeof(content),
                            &failType, failReason, sizeof(failReason))) {
        ereport(WARNING, (errmsg("Failed to fetch document for msg_id=%ld: %s", msgId, failReason)));
        UpdateQueueStatus(msgId, IsRetryable(failType) ? "ready" : "failed", retryCount + 1, failReason);
        return;
    }

    /* Generate embedding and handle results */
    HandleEmbeddingGeneration(msgId, taskId, pkValue, retryCount, &taskConfig, content,
                              &failType, failReason, sizeof(failReason));
}

/* Core scan and process function */
static void InternalScanAndProcess()
{
    int spiRc = 0;
    int64 msgId;
    int taskId;
    int pkValue;
    int retryCount;
    MemoryContext spiCtx = AllocSetContextCreate(CurrentMemoryContext,
                                                "OgaiSPIContext", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(spiCtx);
    /* Initialize environment and query queue */
    if (!InitEnvAndQueryQueue(&spiRc, oldCtx, spiCtx)) {
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(spiCtx);
        return;
    }

    /* Iterate and process each task */
    for (int i = 0; i < SPI_processed; i++) {
        if (ExtractTaskFields(SPI_tuptable->vals[i], SPI_tuptable->tupdesc,
                              &msgId, &taskId, &pkValue, &retryCount)) {
            ProcessTaskLogic(msgId, taskId, pkValue, retryCount);
        }
    }

    SPI_freetuptable(SPI_tuptable);
    PopActiveSnapshot();
    finish_xact_command();
    SPI_finish();
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(spiCtx);
}

bool OgaiVectorProcessorInit()
{
    int spiRc = SPI_connect();
    if (spiRc != SPI_OK_CONNECT) {
        ereport(ERROR, (errmsg(
                "Vector processor initialization failed: SPI connection failed (return code=%d)", spiRc)));
        return false;
    }

    start_xact_command();
    PushActiveSnapshot(GetTransactionSnapshot(false));

    StringInfoData checkSql;
    initStringInfo(&checkSql);

    appendStringInfo(&checkSql,
        "SELECT 1 FROM pg_tables WHERE schemaname = 'ogai' AND tablename = 'vectorize_tasks';");
    
    spiRc = SPI_execute(checkSql.data, true, 0);
    if (spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        ereport(ERROR, (errmsg(
            "Vector processor initialization failed: dependent table ogai.vectorize_tasks does not exist")));
        pfree(checkSql.data);
        PopActiveSnapshot();
        finish_xact_command();
        SPI_finish();
        return false;
    }

    resetStringInfo(&checkSql);
    appendStringInfo(&checkSql,
        "SELECT 1 FROM pg_tables WHERE schemaname = 'ogai' AND tablename = 'vectorize_queue';");
    
    spiRc = SPI_execute(checkSql.data, true, 0);
    if (spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        ereport(ERROR, (errmsg(
            "Vector processor initialization failed: dependent table ogai.vectorize_queue does not exist")));
        pfree(checkSql.data);
        PopActiveSnapshot();
        finish_xact_command();
        SPI_finish();
        return false;
    }

    ereport(LOG, (errmsg("Vector processor initialized successfully")));
    pfree(checkSql.data);
    PopActiveSnapshot();
    finish_xact_command();
    return true;
}

void OgaiVectorProcessorScanAndProcess()
{
    PG_TRY();
    {
        InternalScanAndProcess();
    }
    PG_CATCH();
    {
        ereport(WARNING, (errmsg(
            "Vector processor encountered an exception while scanning the queue; proceeding to next iteration")));
        FlushErrorState();
    }
    PG_END_TRY();
}

void OgaiVectorProcessorDestroy()
{
    SPI_finish();
    ereport(LOG, (errmsg("Vector processor has been destroyed")));
}