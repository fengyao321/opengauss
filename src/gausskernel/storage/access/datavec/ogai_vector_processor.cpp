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
#include "postmaster/bgworker.h"
#include "commands/user.h"
#include "access/datavec/ogai_model_manager.h"
#include "access/datavec/ogai_model_framework.h"
#include "access/datavec/ogai_textsplitter_wrapper.h"
#include "access/datavec/ogai_vector_processor.h"

/* Internal configuration parameters */
#define SQL_BUF_SIZE       4096            /* Size of the SQL statement buffer */
#define PK_VALUE_BUF_SIZE  64              /* Buffer size for pk_value */
#define FAIL_REASON_BUF_SIZE 1024          /* Buffer size for failure reason description */

/* Default values for task configuration */
#define DEFAULT_VECTOR_DIM         1536    /* Default embedding vector dimension */
#define DEFAULT_MAX_CHUNK_SIZE     1000    /* Default text chunk size for join mode */
#define DEFAULT_MAX_CHUNK_OVERLAP  200     /* Default chunk overlap size for join mode */

/* Ogai task config */
typedef struct {
    char modelKey[64];           /* embedding model key */
    char srcSchema[64];          /* source table schema */
    char srcTable[64];           /* source table name */
    char srcCol[64];             /* Name of the text column to be vectorized (input column) */
    char primaryKey[64];         /* Primary key column name of the source table */
    char tableMethod[32];        /* Storage mode ("append" or "join") */
    char ownerName[64];          /* owner of the task */
    int dim;                     /* Vector dimension (default: 1536) */
    int maxChunkSize;            /* Text chunk size (default: 1000) */
    int maxChunkOverlap;         /* Chunk overlap size (default: 200) */
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
        StartTransactionCommand();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT model_key, src_schema, src_table, src_col, primary_key, "
        "method, dim, max_chunk_size, max_chunk_overlap, owner_name "
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->modelKey, sizeof(config->modelKey), value, sizeof(config->modelKey) - 1);
    securec_check(nRet, "", "");
    config->modelKey[sizeof(config->modelKey) - 1] = '\0';

    /* get src_schema, 2 is the second result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 2);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                          "Task configuration src_schema is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->srcSchema, sizeof(config->srcSchema), value, sizeof(config->srcSchema) - 1);
    securec_check(nRet, "", "");
    config->srcSchema[sizeof(config->srcSchema) - 1] = '\0';

    /* get src_table, 3 is the third result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 3);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Task configuration src_table is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->srcTable, sizeof(config->srcTable), value, sizeof(config->srcTable) - 1);
    securec_check(nRet, "", "");
    config->srcTable[sizeof(config->srcTable) - 1] = '\0';

    /* get src_col, 4 is the fourth result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 4);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                 "Task configuration src_col is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->srcCol, sizeof(config->srcCol), value, sizeof(config->srcCol) - 1);
    securec_check(nRet, "", "");
    config->srcCol[sizeof(config->srcCol) - 1] = '\0';

    /* get primary_key, 5 is the fifth result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 5);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                 "Task configuration primary_key is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->primaryKey, sizeof(config->primaryKey),
                value, sizeof(config->primaryKey) - 1);
    securec_check(nRet, "", "");
    config->primaryKey[sizeof(config->primaryKey) - 1] = '\0';

    /* get table_method, 6 is the sixth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 6);
    if (value == NULL || strlen(value) == 0) {
        nRet = strncpy_s(config->tableMethod, sizeof(config->tableMethod),
                    "append", sizeof(config->tableMethod) - 1);
        securec_check(nRet, "", "");
    } else {
        nRet = strncpy_s(config->tableMethod, sizeof(config->tableMethod),
                    value, sizeof(config->tableMethod) - 1);
        securec_check(nRet, "", "");
    }
    config->tableMethod[sizeof(config->tableMethod) - 1] = '\0';

    /* get dim default 1536, 7 is the eventh result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 7);
    config->dim = (value && strlen(value) > 0) ? atoi(value) : DEFAULT_VECTOR_DIM;

    /* get maxChunkSize, 8 is the eighth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 8);
    config->maxChunkSize = (value && strlen(value) > 0) ? atoi(value) : DEFAULT_MAX_CHUNK_SIZE;

    /* get maxChunkOverlap, 9 is the ninth result returned by the SQL statement */
    value = SPI_getvalue(tuple, tupdesc, 9);
    config->maxChunkOverlap = (value && strlen(value) > 0) ? atoi(value) : DEFAULT_MAX_CHUNK_OVERLAP;

    /* get owner_name, 10 is the fourth result returned by the SQL statement. */
    value = SPI_getvalue(tuple, tupdesc, 10);
    if (value == NULL || strlen(value) == 0) {
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                 "Task configuration src_col is empty: task_id=%d", taskId);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }
    nRet = strncpy_s(config->ownerName, sizeof(config->ownerName), value, sizeof(config->ownerName) - 1);
    securec_check(nRet, "", "");
    config->ownerName[sizeof(config->ownerName) - 1] = '\0';

    if (!hasTransaction) {
        PopActiveSnapshot();
        CommitTransactionCommand();
    }
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(tmpCtx);

    return true;
}

/* getdocument content */
static bool GetDocumentContent(
    OgaiTaskConfig *config,
    int pkValue,
    char **contentOut,
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

    *contentOut = NULL;
    *failType = FAIL_TYPE_UNKNOWN;
    nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1, "unknown error");
    securec_check_ss_c(nRet, "", "");

    errno_t ret = memset_s(sql, sizeof(sql), 0, sizeof(sql));
    securec_check(ret, "\0", "\0");

    MemoryContext tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                        "OgaiDocumentContentCtx", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(tmpCtx);

    if (!hasTransaction) {
        StartTransactionCommand();
        PushActiveSnapshot(GetTransactionSnapshot(false));
    }

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT %s FROM %s.%s WHERE %s = $1 LIMIT 1;",
        config->srcCol, config->srcSchema, config->srcTable, config->primaryKey);
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    if (SPI_processed == 0) {
        *failType = FAIL_TYPE_DOCUMENT_NOT_FOUND;
        nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Document not found: %s.%s(%s=%d)",
                config->srcSchema, config->srcTable, config->primaryKey, pkValue);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
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
            config->srcSchema, config->srcTable, config->primaryKey, pkValue);
        securec_check_ss_c(nRet, "", "");
        if (!hasTransaction) {
            PopActiveSnapshot();
            CommitTransactionCommand();
        }
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        return false;
    }

    MemoryContextSwitchTo(oldCtx);
    *contentOut = pstrdup(value);

    if (!hasTransaction) {
        PopActiveSnapshot();
        CommitTransactionCommand();
    }
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
    if (strcmp(config->tableMethod, "append") == 0) {
        /* Generate vectors directly at C level to avoid nested SPI calls */
        ModelConfig modelConfig;
        modelConfig.dimension = config->dim;
        modelConfig.maxBatch = 1;
        
        /* Get model configuration (uses existing SPI connection, no duplicate connection) */
        AsyncGenerateModelConfig(&modelConfig, config->modelKey, config->ownerName);
        
        /* Create embedding client and generate vectors */
        EmbeddingClient* client = CreateEmbeddingClient(&modelConfig);
        if (!client) {
            *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                    "Failed to create embedding client for model: %s", config->modelKey);
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
            config->srcSchema, config->srcTable, config->primaryKey);
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
                config->srcSchema, config->srcTable, config->primaryKey, pkValue);
            securec_check_ss_c(nRet, "", "");
            MemoryContextSwitchTo(oldCtx);
            MemoryContextDelete(tmpCtx);
            return false;
        }

    /* Join mode: update the associated table */
    } else if (strcmp(config->tableMethod, "join") == 0) {
        char joinTable[128];
        nRet = snprintf_s(joinTable, sizeof(joinTable), sizeof(joinTable) - 1,
                        "%s_vector", config->srcTable);
        securec_check_ss_c(nRet, "", "");
        /* Use C++ class directly for text chunking to avoid SQL calls */
        TextSplitterWrapper splitter(config->maxChunkSize, config->maxChunkOverlap);
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
        AsyncGenerateModelConfig(&modelConfig, config->modelKey, config->ownerName);
        
        EmbeddingClient* client = CreateEmbeddingClient(&modelConfig);
        if (!client) {
            *failType = FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            nRet = snprintf_s(failReason, failReasonLen, failReasonLen - 1,
                "Failed to create embedding client for model: %s", config->modelKey);
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
            config->srcSchema, joinTable, config->primaryKey);
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
                 config->tableMethod);
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
        StartTransactionCommand();
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
        }
        return false;
    }
    if (!hasTransaction) {
        PopActiveSnapshot();
        CommitTransactionCommand();
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
        StartTransactionCommand();
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
            CommitTransactionCommand();
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
            CommitTransactionCommand();
        }
        return false;
    }
    ereport(DEBUG1, (errmsg("Successfully deleted queue record: msg_id=%ld", msgId)));
    if (!hasTransaction) {
        PopActiveSnapshot();
        CommitTransactionCommand();
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

/*
 * Query the vectorize_queue and build a shared context for parallel processing.
 * Returns NULL if no tasks are found.
 */
static OgaiVectorizeSharedContext* OgaiInitSharedContext(int *nworkers)
{
    OgaiVectorizeSharedContext *shared = NULL;
    int spiRc;
    char sql[SQL_BUF_SIZE];
    errno_t nRet;
    Datum datum;
    bool isNull;

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "SELECT msg_id, task_id, pk_value, retry_count "
        "FROM ogai.vectorize_queue "
        "WHERE status != 'processing' AND retry_count < %d "
        "ORDER BY vt ASC LIMIT %d;",
        VECTOR_PROCESSOR_MAX_RETRY_COUNT, OGAI_MAX_BATCH_TASKS);
    securec_check_ss_c(nRet, "", "");

    spiRc = SPI_execute(sql, true, 0);
    if (spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        *nworkers = 0;
        return NULL;
    }

    int taskCount = (int)SPI_processed;

    /* Allocate shared context from instance-level memory.
     * This memory is freed by BgworkerCleanupSharedContext via pfree_ext(bwc->bgshared). */
    shared = (OgaiVectorizeSharedContext *)MemoryContextAllocZero(
        INSTANCE_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_STORAGE),
        sizeof(OgaiVectorizeSharedContext));

    pg_atomic_init_u32(&shared->nextTask, 0);
    shared->taskCount = taskCount;

    TupleDesc tupdesc = SPI_tuptable->tupdesc;
    for (int i = 0; i < taskCount; i++) {
        HeapTuple tuple = SPI_tuptable->vals[i];

        /* msg_id (column 1) */
        datum = SPI_getbinval(tuple, tupdesc, 1, &isNull);
        shared->tasks[i].msgId = isNull ? 0 : DatumGetInt64(datum);

        /* task_id (column 2) */
        datum = SPI_getbinval(tuple, tupdesc, 2, &isNull);
        shared->tasks[i].taskId = isNull ? 0 : DatumGetInt32(datum);

        /* pk_value (column 3) */
        datum = SPI_getbinval(tuple, tupdesc, 3, &isNull);
        shared->tasks[i].pkValue = isNull ? 0 : DatumGetInt32(datum);

        /* retry_count (column 4) */
        datum = SPI_getbinval(tuple, tupdesc, 4, &isNull);
        shared->tasks[i].retryCount = isNull ? 0 : DatumGetInt32(datum);
    }

    SPI_freetuptable(SPI_tuptable);

    /* Number of workers: min(taskCount, OGAI_DEFAULT_WORKERS) */
    *nworkers = taskCount < OGAI_DEFAULT_WORKERS ? taskCount : OGAI_DEFAULT_WORKERS;

    return shared;
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
                msgId, taskId, pkValue, taskConfig->tableMethod)));
        } else {
            RollbackAndReleaseCurrentSubTransaction();
            ereport(WARNING, (errmsg("Vector gen failed for msg_id=%ld: %s", msgId, failReason)));
            
            BeginInternalSubTransaction(NULL);
            PG_TRY();
            {
                UpdateQueueStatus(msgId, IsRetryable(*failType) ? "ready" : "failed", retryCount + 1, failReason);
                ReleaseCurrentSubTransaction();
            }
            PG_CATCH();
            {
                RollbackAndReleaseCurrentSubTransaction();
                ereport(WARNING, (errmsg("Failed to update status for msg_id=%ld", msgId)));
            }
            PG_END_TRY();
        }
    }
    PG_CATCH();
    {
        if (IsSubTransaction()) {
            RollbackAndReleaseCurrentSubTransaction();
        }
        errno_t nRet = snprintf_s(failReason, reasonSize, reasonSize - 1,
                                "Unexpected exception: msg_id=%ld, task_id=%d", msgId, taskId);
        securec_check_ss_c(nRet, "", "");
        ereport(WARNING, (errmsg(failReason)));
        
        BeginInternalSubTransaction(NULL);
        PG_TRY();
        {
            UpdateQueueStatus(msgId, "failed", retryCount + 1, failReason);
            ReleaseCurrentSubTransaction();
        }
        PG_CATCH();
        {
            RollbackAndReleaseCurrentSubTransaction();
            ereport(WARNING, (errmsg("Failed to update status in exception for msg_id=%ld", msgId)));
        }
        PG_END_TRY();
    }
    PG_END_TRY();
}

/* Process core business logic for a single task (original, uses subtransactions) */
static void ProcessTaskLogic(int64 msgId, int taskId, int pkValue, int retryCount)
{
    OgaiFailType failType = FAIL_TYPE_UNKNOWN;
    char failReason[FAIL_REASON_BUF_SIZE] = {0};
    OgaiTaskConfig taskConfig = {0};
    char *content = NULL;

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
    if (!GetDocumentContent(&taskConfig, pkValue, &content,
                            &failType, failReason, sizeof(failReason))) {
        ereport(WARNING, (errmsg("Failed to fetch document for msg_id=%ld: %s", msgId, failReason)));
        UpdateQueueStatus(msgId, IsRetryable(failType) ? "ready" : "failed", retryCount + 1, failReason);
        return;
    }

    /* Generate embedding and handle results */
    HandleEmbeddingGeneration(msgId, taskId, pkValue, retryCount, &taskConfig, content,
                              &failType, failReason, sizeof(failReason));
    pfree_ext(content);
}

/* Append mode: generate one embedding for the whole document and copy to instance memory. */
static void WorkerGenerateAppendEmbedding(OgaiVectorizeTask *task,
                                          EmbeddingClient *client, const char *content, int dim)
{
    char *text = const_cast<char *>(content);
    Vector **vectors = client->BatchEmbed(&text, 1, &dim);
    if (!vectors || !vectors[0]) {
        task->resultStatus = TASK_RESULT_FAIL;
        task->failType = (int)FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
        errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                  sizeof(task->failReason) - 1, "Failed to generate embedding vector");
        securec_check_ss_c(nRet, "", "");
        return;
    }

    int vsize = VARSIZE(vectors[0]);
    void *dataCopy = MemoryContextAlloc(
        INSTANCE_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_STORAGE), vsize);
    errno_t rc = memcpy_s(dataCopy, vsize, vectors[0], vsize);
    securec_check(rc, "", "");
    task->vectorData = dataCopy;
    task->vectorSize = vsize;
    task->resultStatus = TASK_RESULT_SUCCESS;
}

/* Copy a single chunk's text and embedding vector to instance memory. Returns true on success. */
static bool CopyChunkEmbeddingToInstance(OgaiEmbeddingChunk *dest,
                                         const char *chunkText, Vector *vector)
{
    int textLen = strlen(chunkText) + 1;
    dest->chunkText = (char *)MemoryContextAlloc(
        INSTANCE_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_STORAGE), textLen);
    errno_t rc = strncpy_s(dest->chunkText, textLen, chunkText, textLen - 1);
    securec_check(rc, "", "");

    int vsize = VARSIZE(vector);
    dest->vectorData = MemoryContextAlloc(
        INSTANCE_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_STORAGE), vsize);
    rc = memcpy_s(dest->vectorData, vsize, vector, vsize);
    securec_check(rc, "", "");
    dest->vectorSize = vsize;
    return true;
}

/* Join mode: split text into chunks, generate embedding for each, copy to instance memory. */
static void WorkerGenerateJoinEmbeddings(OgaiVectorizeTask *task,
                                         EmbeddingClient *client, const char *content,
                                         const OgaiTaskConfig *taskConfig)
{
    TextSplitterWrapper splitter(taskConfig->maxChunkSize, taskConfig->maxChunkOverlap);
    ChunkResult *chunks = splitter.split(content);

    if (chunks == NULL || chunks->chunkNum == 0) {
        task->resultStatus = TASK_RESULT_FAIL;
        task->failType = (int)FAIL_TYPE_SPI_ERROR;
        errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                  sizeof(task->failReason) - 1, "Failed to split document into chunks");
        securec_check_ss_c(nRet, "", "");
        return;
    }

    int chunkCount = chunks->chunkNum;
    OgaiEmbeddingChunk *chunkResults = (OgaiEmbeddingChunk *)MemoryContextAllocZero(
        INSTANCE_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_STORAGE),
        sizeof(OgaiEmbeddingChunk) * chunkCount);

    bool allOk = true;
    for (int i = 0; i < chunkCount; i++) {
        char *chunkText = chunks->chunks[i].chunk;
        int dim = taskConfig->dim;
        Vector **vectors = client->BatchEmbed(&chunkText, 1, &dim);
        if (!vectors || !vectors[0]) {
            task->resultStatus = TASK_RESULT_FAIL;
            task->failType = (int)FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                      sizeof(task->failReason) - 1,
                                      "Failed to generate embedding for chunk %d", i + 1);
            securec_check_ss_c(nRet, "", "");
            allOk = false;
            break;
        }
        CopyChunkEmbeddingToInstance(&chunkResults[i], chunkText, vectors[0]);
    }

    if (allOk) {
        task->chunkCount = chunkCount;
        task->chunks = chunkResults;
        task->resultStatus = TASK_RESULT_SUCCESS;
    } else {
        for (int j = 0; j < chunkCount; j++) {
            pfree_ext(chunkResults[j].chunkText);
            pfree_ext(chunkResults[j].vectorData);
        }
        pfree_ext(chunkResults);
    }
}

/* Copy config subset from full OgaiTaskConfig to the task's OgaiTaskConfigResult for leader DML. */
static void SaveTaskConfigForLeader(OgaiVectorizeTask *task, const OgaiTaskConfig *taskConfig)
{
    errno_t nRet;
    nRet = strncpy_s(task->config.srcSchema, sizeof(task->config.srcSchema),
                     taskConfig->srcSchema, sizeof(task->config.srcSchema) - 1);
    securec_check(nRet, "", "");
    nRet = strncpy_s(task->config.srcTable, sizeof(task->config.srcTable),
                     taskConfig->srcTable, sizeof(task->config.srcTable) - 1);
    securec_check(nRet, "", "");
    nRet = strncpy_s(task->config.primaryKey, sizeof(task->config.primaryKey),
                     taskConfig->primaryKey, sizeof(task->config.primaryKey) - 1);
    securec_check(nRet, "", "");
    nRet = strncpy_s(task->config.tableMethod, sizeof(task->config.tableMethod),
                     taskConfig->tableMethod, sizeof(task->config.tableMethod) - 1);
    securec_check(nRet, "", "");
}

/* Set task failure result with the given fail type and reason. */
static void SetTaskFail(OgaiVectorizeTask *task, OgaiFailType failType,
                        const char *failReason)
{
    task->resultStatus = TASK_RESULT_FAIL;
    task->failType = (int)failType;
    errno_t nRet = strncpy_s(task->failReason, sizeof(task->failReason),
                             failReason, sizeof(task->failReason) - 1);
    securec_check(nRet, "", "");
}

/* Create embedding client and dispatch to append/join mode handler. */
static void WorkerCallEmbeddingModel(OgaiVectorizeTask *task,
                                     const OgaiTaskConfig *taskConfig, const char *content)
{
    MemoryContext tmpCtx = AllocSetContextCreate(CurrentMemoryContext,
                                "OgaiWorkerEmbeddingCtx", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldCtx = MemoryContextSwitchTo(tmpCtx);
    PG_TRY();
    {
        ModelConfig modelConfig;
        modelConfig.dimension = taskConfig->dim;
        modelConfig.maxBatch = 1;
        AsyncGenerateModelConfig(&modelConfig, taskConfig->modelKey, taskConfig->ownerName);

        EmbeddingClient *client = CreateEmbeddingClient(&modelConfig);
        if (!client) {
            task->resultStatus = TASK_RESULT_FAIL;
            task->failType = (int)FAIL_TYPE_EMBEDDING_GENERATE_FAILED;
            errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                      sizeof(task->failReason) - 1,
                                      "Failed to create embedding client for model: %s", taskConfig->modelKey);
            securec_check_ss_c(nRet, "", "");
        } else if (strcmp(taskConfig->tableMethod, "append") == 0) {
            WorkerGenerateAppendEmbedding(task, client, content, taskConfig->dim);
        } else if (strcmp(taskConfig->tableMethod, "join") == 0) {
            WorkerGenerateJoinEmbeddings(task, client, content, taskConfig);
        } else {
            task->resultStatus = TASK_RESULT_FAIL;
            task->failType = (int)FAIL_TYPE_TASK_CONFIG_NOT_FOUND;
            errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                      sizeof(task->failReason) - 1,
                                      "Unsupported storage mode: %s", taskConfig->tableMethod);
            securec_check_ss_c(nRet, "", "");
        }
    }
    PG_CATCH();
    {
        MemoryContextSwitchTo(oldCtx);
        MemoryContextDelete(tmpCtx);
        FlushErrorState();
        task->resultStatus = TASK_RESULT_FAIL;
        task->failType = (int)FAIL_TYPE_UNKNOWN;
        errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                  sizeof(task->failReason) - 1,
                                  "Exception in embedding model call for task_id=%d, pk_value=%d",
                                  task->taskId, task->pkValue);
        securec_check_ss_c(nRet, "", "");
        return;
    }
    PG_END_TRY();
    MemoryContextSwitchTo(oldCtx);
    MemoryContextDelete(tmpCtx);
}

static void WorkerGenerateEmbedding(OgaiVectorizeTask *task)
{
    OgaiFailType failType = FAIL_TYPE_UNKNOWN;
    char failReason[FAIL_REASON_BUF_SIZE] = {0};
    OgaiTaskConfig taskConfig = {0};
    char *content = NULL;

    if (!GetTaskConfig(task->taskId, &taskConfig, &failType, failReason, sizeof(failReason))) {
        SetTaskFail(task, failType, failReason);
        return;
    }

    SaveTaskConfigForLeader(task, &taskConfig);

    if (!GetDocumentContent(&taskConfig, task->pkValue, &content,
                            &failType, failReason, sizeof(failReason))) {
        SetTaskFail(task, failType, failReason);
        return;
    }

    if (content == NULL || content[0] == '\0') {
        task->resultStatus = TASK_RESULT_FAIL;
        task->failType = (int)FAIL_TYPE_DOCUMENT_CONTENT_NULL;
        errno_t nRet = snprintf_s(task->failReason, sizeof(task->failReason),
                                  sizeof(task->failReason) - 1,
                                  "Document content is empty: pk_value=%d", task->pkValue);
        securec_check_ss_c(nRet, "", "");
        pfree_ext(content);
        return;
    }

    WorkerCallEmbeddingModel(task, &taskConfig, content);
    pfree_ext(content);
}

/*
 * ogaiworker-side: free embedding data allocated by workers in instance memory.
 */
static void LeaderFreeTaskEmbeddings(OgaiVectorizeSharedContext *shared)
{
    for (int i = 0; i < shared->taskCount; i++) {
        OgaiVectorizeTask *task = &shared->tasks[i];
        pfree_ext(task->vectorData);
        if (task->chunks != NULL) {
            for (int j = 0; j < task->chunkCount; j++) {
                pfree_ext(task->chunks[j].chunkText);
                pfree_ext(task->chunks[j].vectorData);
            }
            pfree_ext(task->chunks);
        }
    }
}

/* Append mode: UPDATE target table with embedding vector. Returns true on success. */
static bool LeaderWriteAppendResult(OgaiVectorizeTask *task)
{
    char sql[SQL_BUF_SIZE];
    errno_t nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "UPDATE %s.%s SET ogai_embedding = $1 WHERE %s = $2;",
        task->config.srcSchema, task->config.srcTable, task->config.primaryKey);
    securec_check_ss_c(nRet, "", "");

    Oid paramTypes[2] = {VECTOROID, INT4OID};
    SPIPlanPtr plan = SPI_prepare(sql, 2, paramTypes);
    if (plan == NULL) {
        return false;
    }
    Datum params[2] = { PointerGetDatum(task->vectorData), Int32GetDatum(task->pkValue) };
    char paramNulls[2] = {' ', ' '};
    int spiRc = SPI_execute_plan(plan, params, paramNulls, false, 0);
    SPI_freeplan(plan);
    return (spiRc == SPI_OK_UPDATE && SPI_processed > 0);
}

/* Join mode: INSERT each chunk with embedding into the vector table. Returns true on success. */
static bool LeaderWriteJoinResults(OgaiVectorizeTask *task)
{
    char joinTable[128];
    char sql[SQL_BUF_SIZE];
    errno_t nRet = snprintf_s(joinTable, sizeof(joinTable), sizeof(joinTable) - 1,
                              "%s_vector", task->config.srcTable);
    securec_check_ss_c(nRet, "", "");

    nRet = snprintf_s(sql, sizeof(sql), sizeof(sql) - 1,
        "INSERT INTO %s.%s (%s, chunk_id, chunk_text, ogai_embedding) VALUES ($1, $2, $3, $4)",
        task->config.srcSchema, joinTable, task->config.primaryKey);
    securec_check_ss_c(nRet, "", "");

    Oid paramTypes[4] = {INT4OID, INT4OID, TEXTOID, VECTOROID};
    SPIPlanPtr plan = SPI_prepare(sql, 4, paramTypes);
    if (plan == NULL) {
        return false;
    }
    for (int j = 0; j < task->chunkCount; j++) {
        Datum params[4] = {
            Int32GetDatum(task->pkValue), Int32GetDatum(j + 1),
            CStringGetTextDatum(task->chunks[j].chunkText),
            PointerGetDatum(task->chunks[j].vectorData)
        };
        char paramNulls[4] = {' ', ' ', ' ', ' '};
        int spiRc = SPI_execute_plan(plan, params, paramNulls, false, 0);
        if (spiRc != SPI_OK_INSERT) {
            SPI_freeplan(plan);
            return false;
        }
    }
    SPI_freeplan(plan);
    return true;
}

/*
 * ogaiworker-side: process worker results by doing all DML.
 */
static void LeaderProcessTaskResults(OgaiVectorizeSharedContext *shared)
{
    for (int i = 0; i < shared->taskCount; i++) {
        OgaiVectorizeTask *task = &shared->tasks[i];

        if (task->resultStatus == TASK_RESULT_SUCCESS) {
            bool writeOk = false;
            if (strcmp(task->config.tableMethod, "append") == 0 && task->vectorData != NULL) {
                writeOk = LeaderWriteAppendResult(task);
            } else if (strcmp(task->config.tableMethod, "join") == 0 && task->chunks != NULL) {
                writeOk = LeaderWriteJoinResults(task);
            }

            if (writeOk) {
                DeleteQueueRecord(task->msgId);
                ereport(LOG, (errmsg("Task success: msg_id=%ld, task_id=%d, pk_value=%d, mode=%s",
                                     task->msgId, task->taskId, task->pkValue, task->config.tableMethod)));
            } else {
                ereport(WARNING, (errmsg("Leader: failed to write embedding for msg_id=%ld", task->msgId)));
                UpdateQueueStatus(task->msgId, "ready", task->retryCount + 1,
                                  "Leader failed to write embedding to target table");
            }
        } else if (task->resultStatus == TASK_RESULT_FAIL) {
            OgaiFailType ft = (OgaiFailType)task->failType;
            ereport(WARNING, (errmsg("Worker failed for msg_id=%ld: %s", task->msgId, task->failReason)));
            UpdateQueueStatus(task->msgId, IsRetryable(ft) ? "ready" : "failed",
                              task->retryCount + 1, task->failReason);
        }
    }
}

/* Prepare shared context: start transaction, query queue, mark tasks as "processing". */
static OgaiVectorizeSharedContext *PrepareParallelTasks(int *nworkers)
{
    OgaiVectorizeSharedContext *shared = NULL;

    if (!IsTransactionState()) {
        StartTransactionCommand();
    }
    PushActiveSnapshot(GetTransactionSnapshot(false));

    int spiRc = SPI_connect();
    if (spiRc != SPI_OK_CONNECT) {
        PopActiveSnapshot();
        CommitTransactionCommand();
        ereport(WARNING, (errmsg("OGAI parallel vectorize: SPI connect failed (rc=%d)", spiRc)));
        return NULL;
    }

    shared = OgaiInitSharedContext(nworkers);
    if (shared == NULL || *nworkers == 0) {
        SPI_finish();
        PopActiveSnapshot();
        CommitTransactionCommand();
        return NULL;
    }

    for (int i = 0; i < shared->taskCount; i++) {
        UpdateQueueStatus(shared->tasks[i].msgId, "processing",
                          shared->tasks[i].retryCount, "");
    }
    CommandCounterIncrement();
    SPI_finish();
    return shared;
}

/* Wait for workers, process results, free resources, commit. */
static void WaitAndProcessResults(OgaiVectorizeSharedContext *shared, int successWorkers)
{
    PG_TRY();
    {
        BgworkerListWaitFinish(&successWorkers);
    }
    PG_CATCH();
    {
        BgworkerListSyncQuit();
        PG_RE_THROW();
    }
    PG_END_TRY();

    pg_memory_barrier();

    int spiRc = SPI_connect();
    bool spiOk = (spiRc == SPI_OK_CONNECT);
    if (spiOk) {
        LeaderProcessTaskResults(shared);
        SPI_finish();
    } else {
        ereport(WARNING, (errmsg("OGAI: leader SPI reconnect failed (rc=%d), aborting transaction", spiRc)));
    }

    LeaderFreeTaskEmbeddings(shared);
    BgworkerListSyncQuit();
    PopActiveSnapshot();
    if (spiOk) {
        CommitTransactionCommand();
    } else {
        AbortCurrentTransaction();
    }
}

/*
 * Exit callback for BgWorkerContext: free embedding data from instance memory
 * before BgworkerCleanupSharedContext frees the shared struct itself.
 */
static void OgaiVectorizeExitCleanup(const BgWorkerContext *bwc)
{
    OgaiVectorizeSharedContext *shared = (OgaiVectorizeSharedContext *)bwc->bgshared;
    if (shared != NULL) {
        LeaderFreeTaskEmbeddings(shared);
    }
}

static void InternalParallelVectorize()
{
    int nworkers = 0;
    OgaiVectorizeSharedContext *shared = PrepareParallelTasks(&nworkers);
    if (shared == NULL) {
        return;
    }

    ereport(DEBUG1, (errmsg("OGAI parallel vectorize: launching %d workers for %d tasks",
                            nworkers, shared->taskCount)));

    int successWorkers = LaunchBackgroundWorkers(nworkers, shared,
                                                OgaiVectorizeWorkerMain, OgaiVectorizeExitCleanup);
    if (successWorkers == 0) {
        LeaderFreeTaskEmbeddings(shared);
        pfree_ext(shared);
        pfree_ext(t_thrd.bgworker_cxt.bgwcontext);
        t_thrd.bgworker_cxt.bgwcontext = NULL;
        PopActiveSnapshot();
        AbortCurrentTransaction();
        ereport(WARNING, (errmsg("OGAI parallel vectorize: all workers failed to start")));
        return;
    }

    WaitAndProcessResults(shared, successWorkers);
}

bool OgaiVectorProcessorInit()
{
    if (!IsTransactionState()) {
        StartTransactionCommand();
    }
    PushActiveSnapshot(GetTransactionSnapshot(false));

    int spiRc = SPI_connect();
    if (spiRc != SPI_OK_CONNECT) {
        PopActiveSnapshot();
        CommitTransactionCommand();
        ereport(ERROR, (errmsg(
                "Vector processor initialization failed: SPI connection failed (return code=%d)", spiRc)));
        return false;
    }

    StringInfoData checkSql;
    initStringInfo(&checkSql);

    appendStringInfo(&checkSql,
        "SELECT 1 FROM pg_tables WHERE schemaname = 'ogai' AND tablename = 'vectorize_tasks';");
    
    spiRc = SPI_execute(checkSql.data, true, 0);
    if (spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        ereport(ERROR, (errmsg(
            "Vector processor initialization failed: dependent table ogai.vectorize_tasks does not exist")));
    }

    resetStringInfo(&checkSql);
    appendStringInfo(&checkSql,
        "SELECT 1 FROM pg_tables WHERE schemaname = 'ogai' AND tablename = 'vectorize_queue';");
    
    spiRc = SPI_execute(checkSql.data, true, 0);
    if (spiRc != SPI_OK_SELECT || SPI_processed == 0) {
        ereport(ERROR, (errmsg(
            "Vector processor initialization failed: dependent table ogai.vectorize_queue does not exist")));
    }

    /* Set MyProcPort->user_name for bgworker authentication. */
    if (u_sess->proc_cxt.MyProcPort->user_name == NULL ||
        u_sess->proc_cxt.MyProcPort->user_name[0] == '\0') {
        MemoryContext oldMemCtx = MemoryContextSwitchTo(
            SESS_GET_MEM_CXT_GROUP(MEMORY_CONTEXT_EXECUTOR));
        char superuserBuf[NAMEDATALEN] = {0};
        char *superuserName = GetSuperUserName(superuserBuf);
        if (superuserName != NULL && superuserName[0] != '\0') {
            u_sess->proc_cxt.MyProcPort->user_name = pstrdup(superuserName);
        }
        MemoryContextSwitchTo(oldMemCtx);
    }

    ereport(LOG, (errmsg("Vector processor initialized successfully")));
    pfree(checkSql.data);
    SPI_finish();
    PopActiveSnapshot();
    CommitTransactionCommand();
    return true;
}

/* Bgworker main function for parallel vectorization. */
void OgaiVectorizeWorkerMain(const BgWorkerContext *bwc)
{
    OgaiVectorizeSharedContext *shared = (OgaiVectorizeSharedContext *)bwc->bgshared;

    /* Push active snapshot for SPI_prepare catalog access (read-only) */
    PushActiveSnapshot(GetTransactionSnapshot(false));

    int spiRc = SPI_connect();
    if (spiRc != SPI_OK_CONNECT) {
        PopActiveSnapshot();
        ereport(ERROR, (errmsg("OGAI vectorize worker: SPI connect failed (rc=%d)", spiRc)));
        return;
    }

    /* Grab tasks from shared context via atomic counter.
     * Multiple workers compete — each gets a unique index. */
    for (;;) {
        uint32 idx = pg_atomic_fetch_add_u32(&shared->nextTask, 1);
        if (idx >= (uint32)shared->taskCount) {
            break;
        }

        /* Read config + content + generate embedding (NO DML) */
        WorkerGenerateEmbedding(&shared->tasks[idx]);

        ereport(LOG, (errmsg("OGAI worker: task idx=%u, msg_id=%ld completed, status=%d",
                             idx, shared->tasks[idx].msgId, shared->tasks[idx].resultStatus)));
    }

    SPI_finish();
    PopActiveSnapshot();
}

/* Public entry point for parallel vectorization. */
void OgaiParallelVectorize(void)
{
    PG_TRY();
    {
        InternalParallelVectorize();
    }
    PG_CATCH();
    {
        ereport(WARNING, (errmsg(
            "OGAI parallel vectorize: exception encountered; proceeding to next iteration")));
        FlushErrorState();
        AbortOutOfAnyTransaction();
    }
    PG_END_TRY();
}