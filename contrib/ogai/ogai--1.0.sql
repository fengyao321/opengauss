/* contrib/ogai/ogai--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION ogai" to load this file. \quit

-- ========================================================================
-- PART 1: Schema, Types and Tables (from ogai_tables.sql)
-- ========================================================================

-- Schema is automatically created by openGauss based on ogai.control (schema = ogai)
-- No need to CREATE SCHEMA here
GRANT USAGE ON SCHEMA ogai TO PUBLIC;

CREATE TYPE ogai.model_provider_type AS ENUM (
    'openai',
    'onnx',
    'ollama',
    'Qwen'
);
GRANT USAGE ON TYPE ogai.model_provider_type TO PUBLIC;

CREATE TABLE IF NOT EXISTS ogai.model_sources
(
    id BIGSERIAL PRIMARY KEY,
    model_key   TEXT NOT NULL,
    model_name  TEXT NOT NULL,
    model_provider ogai.model_provider_type NOT NULL,
    url         VARCHAR(2048) NOT NULL,
    description TEXT DEFAULT '',
    api_key     TEXT,
    owner_name  TEXT NOT NULL,
    UNIQUE (model_key, owner_name)
    );
CREATE INDEX IF NOT EXISTS model_sources_model_key_idx ON ogai.model_sources (model_key);
CREATE INDEX IF NOT EXISTS model_sources_owner_name_idx ON ogai.model_sources (owner_name);

CREATE TYPE ogai.task_type AS ENUM (
    'sync',
    'async'
);

CREATE TYPE ogai.table_method AS ENUM (
    'append',
    'join'
);

GRANT USAGE ON TYPE ogai.task_type TO PUBLIC;
GRANT USAGE ON TYPE ogai.table_method TO PUBLIC;

CREATE TABLE IF NOT EXISTS ogai.vectorize_tasks
(
    task_id BIGSERIAL PRIMARY KEY,
    task_name TEXT NOT NULL,
    type ogai.task_type NOT NULL,
    index_type TEXT NOT NULL,
    model_key TEXT NOT NULL,
    src_schema TEXT NOT NULL,
    src_table TEXT NOT NULL,
    src_col TEXT NOT NULL,
    primary_key TEXT NOT NULL,
    method ogai.table_method NOT NULL,
    dim integer NOT NULL,
    max_chunk_size integer NOT NULL DEFAULT 0,
    max_chunk_overlap integer NOT NULL DEFAULT 0,
    enable_bm25 BOOLEAN NOT NULL DEFAULT true,
    owner_name NAME NOT NULL DEFAULT CURRENT_USER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (task_name, owner_name)
    );
CREATE INDEX IF NOT EXISTS vectorize_tasks_task_name_idx ON ogai.vectorize_tasks (task_name);
CREATE INDEX IF NOT EXISTS vectorize_tasks_owner_name_idx ON ogai.vectorize_tasks (owner_name);

CREATE TYPE ogai.queue_status AS ENUM (
    'ready',
    'processing',
    'completed',
    'failed'
);
GRANT USAGE ON TYPE ogai.queue_status TO PUBLIC;

CREATE TABLE IF NOT EXISTS ogai.vectorize_queue
(
    msg_id BIGSERIAL UNIQUE,
    task_id integer,
    pk_value integer,
    status ogai.queue_status NOT NULL DEFAULT 'ready',
    vt TIMESTAMP NOT NULL,
    fail_reason TEXT DEFAULT NULL,
    create_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    update_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    retry_count integer DEFAULT 0,
    owner_name NAME NOT NULL DEFAULT CURRENT_USER
);
CREATE INDEX IF NOT EXISTS vectorize_queue_vt_idx ON ogai.vectorize_queue (vt);
CREATE INDEX IF NOT EXISTS vectorize_queue_status_idx ON ogai.vectorize_queue (status);
CREATE INDEX IF NOT EXISTS vectorize_queue_owner_name_idx ON ogai.vectorize_queue (owner_name);


-- Enable Row Level Security on all tables
ALTER TABLE ogai.model_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE ogai.vectorize_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE ogai.vectorize_queue ENABLE ROW LEVEL SECURITY;

-- Create policies for model_sources table
CREATE ROW LEVEL SECURITY POLICY model_sources_owner_policy ON ogai.model_sources
    FOR ALL TO PUBLIC
    USING (owner_name = CURRENT_USER);

-- Create policies for vectorize_task table
CREATE ROW LEVEL SECURITY POLICY vectorize_task_owner_policy ON ogai.vectorize_tasks
    FOR ALL TO PUBLIC
    USING (owner_name = CURRENT_USER);

-- Create policies for vectorize_queue table
CREATE ROW LEVEL SECURITY POLICY vectorize_queue_owner_policy ON ogai.vectorize_queue
    FOR ALL TO PUBLIC
    USING (owner_name = CURRENT_USER);

-- Grant appropriate permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ogai.model_sources TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON ogai.vectorize_tasks TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON ogai.vectorize_queue TO PUBLIC;

GRANT USAGE, SELECT ON SEQUENCE ogai.model_sources_id_seq TO PUBLIC;
GRANT USAGE, SELECT ON SEQUENCE ogai.vectorize_tasks_task_id_seq TO PUBLIC;
GRANT USAGE, SELECT ON SEQUENCE ogai.vectorize_queue_msg_id_seq TO PUBLIC;

GRANT CREATE ON SCHEMA ogai TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ogai TO PUBLIC;
-- ========================================================================
-- PART 2: Functions (from ogai_functions.sql)
-- ========================================================================

CREATE OR REPLACE FUNCTION ogai.vectorize_trigger_handle(
    p_content TEXT,
    p_embed_model TEXT,
    p_dim INTEGER,
    p_task_name TEXT,
    p_task_type TEXT,
    p_src_schema TEXT,
    p_src_table TEXT,
    p_primary_key TEXT,
    p_table_method TEXT,
    p_operation TEXT,
    p_pk_value TEXT,
    p_max_chunk_size INTEGER DEFAULT 1000,
    p_max_chunk_overlap INTEGER DEFAULT 200
)
RETURNS VOID AS $$
DECLARE
    v_chunk_record RECORD;
    v_chunk_id INTEGER := 1;
BEGIN
    -- Check if the operation is UPDATE, if so, raise an error
    IF p_operation = 'UPDATE' THEN
        RAISE EXCEPTION 'Vectorization does not support UPDATE operations. Please use DELETE + INSERT instead, or recreate the vectorization task.'
            USING HINT = 'To update vectorized data: 1) Delete the old record, 2) Insert the new record, or use ai_unvectorize() and ai_vectorize() to recreate the task.';
    END IF;

    IF p_task_type = 'sync' THEN
        IF p_operation = 'INSERT' AND p_content IS NOT NULL THEN
            IF p_table_method = 'append' THEN
                EXECUTE format(
                    'UPDATE %I.%I SET ogai_embedding = ogai_embedding($1, $2, $3) WHERE %I = $4',
                    p_src_schema, p_src_table, p_primary_key
                ) USING p_content, p_embed_model, p_dim, p_pk_value;
ELSE
                -- join mode: supports text chunking
                -- Delete old text first
                EXECUTE format(
                    'DELETE FROM %I.%I WHERE %I = $1',
                    p_src_schema, p_src_table || '_vector', p_primary_key
                ) USING p_pk_value;
                -- Decide processing method based on chunk size
                IF p_max_chunk_size > 0 THEN
                    -- Need chunking processing
                    FOR v_chunk_record IN
SELECT chunk FROM ogai_chunk(p_content, p_max_chunk_size, p_max_chunk_overlap)
                      LOOP
    EXECUTE format(
                            'INSERT INTO %I.%I (%I, chunk_id, chunk_text, ogai_embedding, updated_at)
                             VALUES ($1, $2, $3, ogai_embedding($4, $5, $6), CURRENT_TIMESTAMP)',
                            p_src_schema, p_src_table || '_vector', p_primary_key
                        ) USING p_pk_value, v_chunk_id, v_chunk_record.chunk,
                                v_chunk_record.chunk, p_embed_model, p_dim;
v_chunk_id := v_chunk_id + 1;
END LOOP;
ELSE
                    -- No chunking, only store vectors
                    EXECUTE format(
                        'INSERT INTO %I.%I (%I, ogai_embedding, updated_at)
                         VALUES ($1, ogai_embedding($2, $3, $4), CURRENT_TIMESTAMP)',
                        p_src_schema, p_src_table || '_vector', p_primary_key
                    ) USING p_pk_value, p_content, p_embed_model, p_dim;
END IF;
END IF;
        ELSIF p_operation = 'DELETE' AND p_table_method = 'join' THEN
            EXECUTE format(
                'DELETE FROM %I.%I WHERE %I = $1',
                p_src_schema, p_src_table || '_vector', p_primary_key
            ) USING p_pk_value;
END IF;
    -- Async mode: write to queue
ELSE
        DECLARE
            v_task_id BIGINT;
        BEGIN
            -- Get task ID
            SELECT task_id INTO v_task_id
            FROM ogai.vectorize_tasks
            WHERE task_name = p_task_name AND owner_name = CURRENT_USER;

            -- Insert queue record: task_id and pk_value
            INSERT INTO ogai.vectorize_queue (task_id, pk_value, status, vt)
            VALUES (v_task_id, p_pk_value::INTEGER, 'ready', CURRENT_TIMESTAMP);
            
            -- Notify background processing
            PERFORM ogai_notify();
        END;
END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ogai.vectorize_param_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_content TEXT;
    v_pk_value TEXT;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        EXECUTE format('SELECT ($1).%I::TEXT', TG_ARGV[6])
           INTO v_content
           USING NEW;
        EXECUTE format('SELECT ($1).%I::TEXT', TG_ARGV[7])
           INTO v_pk_value
           USING NEW;
ELSE
        EXECUTE format('SELECT ($1).%I::TEXT', TG_ARGV[7])
           INTO v_pk_value
           USING OLD;
END IF;

    RAISE NOTICE 'vectorize_trigger_handle';
    PERFORM ogai.vectorize_trigger_handle(
        p_content => v_content,
        p_embed_model => TG_ARGV[0]::TEXT,
        p_dim => TG_ARGV[1]::INTEGER,
        p_task_name => TG_ARGV[2]::TEXT,
        p_task_type => TG_ARGV[3]::TEXT,
        p_src_schema => TG_ARGV[4]::TEXT,
        p_src_table => TG_ARGV[5]::TEXT,
        p_primary_key => TG_ARGV[7]::TEXT,
        p_table_method => TG_ARGV[8]::TEXT,
        p_operation => TG_OP,
        p_pk_value => v_pk_value,
        p_max_chunk_size => TG_ARGV[9]::INTEGER,
        p_max_chunk_overlap => TG_ARGV[10]::INTEGER
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
ELSE
        RETURN NEW;
END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ogai.ai_vectorize(
    p_task_name TEXT,
    p_task_type TEXT,
    p_index_type TEXT,
    p_embed_model TEXT,
    p_src_schema TEXT,
    p_src_table TEXT,
    p_src_col TEXT,
    p_primary_key TEXT,
    p_table_method TEXT,
    p_dim INTEGER,
    p_max_chunk_size INTEGER DEFAULT 1000,
    p_max_chunk_overlap INTEGER DEFAULT 200,
    p_enable_bm25 BOOLEAN DEFAULT true
) RETURNS TABLE(
    task_id INT,
    success BOOLEAN,
    processed_count INT,
    message TEXT
) AS $$
DECLARE
v_task_id INT;
    v_src_query TEXT;
    v_row RECORD;
    v_processed INT := 0;
    v_error TEXT := '';
    v_vector_col TEXT := 'ogai_embedding';
    v_trigger_name TEXT;
    v_error_rows TEXT[] := '{}';
    v_error_msgs TEXT[] := '{}';
    v_error_summary TEXT;
BEGIN
    -- 1. Validate input parameters
    IF p_task_type NOT IN ('sync', 'async') THEN
        RETURN QUERY SELECT NULL::INT, false, 0, 'Invalid task_type. Must be ''sync'' or ''async''';
    RETURN;
    END IF;

    IF p_table_method NOT IN ('append', 'join') THEN
        RETURN QUERY SELECT NULL::INT, false, 0, 'Invalid table_method. Allowed: append, join';
    RETURN;
    END IF;

    IF p_dim IS NULL OR p_dim <= 0 THEN
        RETURN QUERY SELECT NULL::INT, false, 0, 'dim must be a positive integer';
    RETURN;
    END IF;

    -- Validate column type for BM25 index
    IF p_enable_bm25 THEN
        DECLARE
            v_column_type TEXT;
        BEGIN
            SELECT data_type INTO v_column_type
            FROM information_schema.columns
            WHERE table_schema = p_src_schema
              AND table_name = p_src_table
              AND column_name = p_src_col;
            
            IF v_column_type IS NULL THEN
                RETURN QUERY SELECT NULL::INT, false, 0, 
                    format('Column %I.%I.%I not found', p_src_schema, p_src_table, p_src_col);
                RETURN;
            END IF;
            
            IF v_column_type != 'text' THEN
                RETURN QUERY SELECT NULL::INT, false, 0, 
                    format('BM25 index only supports TEXT type columns. Column %I is of type %s. Please disable BM25 (set enable_bm25=false) or change the column type to TEXT.', 
                           p_src_col, v_column_type);
                RETURN;
            END IF;
        END;
    END IF;

    -- 2. Check if task already exists
    PERFORM 1 FROM ogai.vectorize_tasks WHERE task_name = p_task_name;
    IF FOUND THEN
        RETURN QUERY SELECT NULL::INT, false, 0, 'Task already exists: ' || p_task_name;
    RETURN;
    END IF;

    -- 3. Insert task record
INSERT INTO ogai.vectorize_tasks (
    task_name, type, index_type, model_key,
    src_schema, src_table, src_col, primary_key,
    method, dim, max_chunk_size, max_chunk_overlap, enable_bm25
) VALUES (
             p_task_name, p_task_type::ogai.task_type, p_index_type, p_embed_model,
             p_src_schema, p_src_table, p_src_col, p_primary_key,
             p_table_method::ogai.table_method, p_dim, p_max_chunk_size, p_max_chunk_overlap, p_enable_bm25
         ) RETURNING task_id INTO v_task_id;

-- 4. Create trigger
v_trigger_name := format('trg_ogai_vectorize_%s', replace(p_task_name, '-', '_'));
    PERFORM 1
    FROM pg_trigger
    WHERE tgname = v_trigger_name;

    IF NOT FOUND THEN
        EXECUTE format(
            'CREATE TRIGGER %I
             AFTER INSERT OR UPDATE OF %I OR DELETE
             ON %I.%I
             FOR EACH ROW
             EXECUTE FUNCTION ogai.vectorize_param_trigger(%L, %L, %L, %L, %L, %L, %L, %L, %L, %L, %L)',
            v_trigger_name,
            p_src_col,
            p_src_schema,
            p_src_table,
            p_embed_model,
            p_dim,
            p_task_name,
            p_task_type,
            p_src_schema,
            p_src_table,
            p_src_col,
            p_primary_key,
            p_table_method,
            p_max_chunk_size,
            p_max_chunk_overlap
        );
END IF;

    -- 5. Initialize vector storage based on method
    IF p_table_method = 'append' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = p_src_schema
            AND table_name = p_src_table
            AND column_name = v_vector_col
        ) THEN
            EXECUTE format(
            'ALTER TABLE %I.%I ADD COLUMN %I vector(%s)',
            p_src_schema, p_src_table, v_vector_col, p_dim
        );
END IF;
ELSE  -- join mode: create independent vector table (in user schema)
        PERFORM 1
        FROM information_schema.tables
        WHERE table_schema = p_src_schema
        AND table_name = p_src_table || '_vector';

        IF NOT FOUND THEN
            IF p_max_chunk_size > 0 THEN
                -- Table structure with chunking support
                EXECUTE format(
                    'CREATE TABLE %I.%I (
                        %I %s NOT NULL,
                        chunk_id INTEGER NOT NULL,
                        chunk_text TEXT,
                        ogai_embedding VECTOR(%s) NOT NULL,
                        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                        PRIMARY KEY (%I, chunk_id),
                        FOREIGN KEY (%I) REFERENCES %I.%I(%I)
                    )',
                    p_src_schema,
                    p_src_table || '_vector',
                    p_primary_key,
                    (SELECT data_type
                     FROM information_schema.columns
                     WHERE table_schema = p_src_schema
                     AND table_name = p_src_table
                     AND column_name = p_primary_key),
                    p_dim,
                    p_primary_key,
                    p_primary_key,
                    p_src_schema, p_src_table, p_primary_key
                );
EXECUTE format(
        'CREATE VIEW %I.%I AS
         SELECT s.*, v.chunk_id, v.chunk_text, v.ogai_embedding
         FROM %I.%I s
         JOIN %I.%I v ON s.%I = v.%I',
        p_src_schema,
        p_src_table || '_vector_view',
        p_src_schema, p_src_table,
        p_src_schema, p_src_table || '_vector',
        p_primary_key, p_primary_key
        );
ELSE
                -- Table structure without chunking
                EXECUTE format(
                    'CREATE TABLE %I.%I (
                        %I %s PRIMARY KEY REFERENCES %I.%I(%I),
                        ogai_embedding VECTOR(%s) NOT NULL,
                        created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                    )',
                    p_src_schema,
                    p_src_table || '_vector',
                    p_primary_key,
                    (SELECT data_type
                     FROM information_schema.columns
                     WHERE table_schema = p_src_schema
                     AND table_name = p_src_table
                     AND column_name = p_primary_key),
                    p_src_schema, p_src_table, p_primary_key,
                    p_dim
                );
            -- View for non-chunking mode
EXECUTE format(
        'CREATE VIEW %I.%I AS
         SELECT s.*, v.ogai_embedding
         FROM %I.%I s
         JOIN %I.%I v ON s.%I = v.%I',
        p_src_schema,
        p_src_table || '_vector_view',
        p_src_schema, p_src_table,
        p_src_schema, p_src_table || '_vector',
        p_primary_key, p_primary_key
        );
END IF;
END IF;
END IF;

    -- 6. Process data based on task type
    v_src_query := format(
        'SELECT %I AS pk, %I AS content FROM %I.%I',
        p_primary_key, p_src_col, p_src_schema, p_src_table
    );

    IF p_task_type = 'sync' THEN
        -- Sync task: process vector conversion
        FOR v_row IN EXECUTE v_src_query LOOP
        BEGIN
            IF v_row.content IS NULL THEN
                v_error := v_error || format('Row %s skipped due to null content; ', v_row.pk);
                CONTINUE;
            END IF;

            IF p_table_method = 'append' THEN
                -- Append mode: update vector column in original table
                EXECUTE format(
                    'UPDATE %I.%I SET %I = ogai_embedding($1, $2, $3) WHERE %I = $4',
                    p_src_schema, p_src_table, v_vector_col, p_primary_key
                ) USING v_row.content, p_embed_model, p_dim, v_row.pk;
            ELSE
                -- Join mode: insert or update independent vector table
                IF p_max_chunk_size > 0 THEN
                    -- Need chunking processing
                    DECLARE
                        v_chunk_record RECORD;
                        v_chunk_id INTEGER := 1;
                    BEGIN
                        FOR v_chunk_record IN
                            SELECT chunk FROM ogai_chunk(v_row.content, p_max_chunk_size, p_max_chunk_overlap)
                        LOOP
                            EXECUTE format(
                                'INSERT INTO %I.%I (%I, chunk_id, chunk_text, ogai_embedding)
                                 VALUES ($1, $2, $3, ogai_embedding($4, $5, $6))',
                                p_src_schema, p_src_table || '_vector', p_primary_key
                            ) USING v_row.pk, v_chunk_id, v_chunk_record.chunk,
                                    v_chunk_record.chunk, p_embed_model, p_dim;
                            v_chunk_id := v_chunk_id + 1;
                        END LOOP;
                    END;
                ELSE
                    -- No chunking, only store vectors
                    EXECUTE format(
                        'INSERT INTO %I.%I (%I, ogai_embedding)
                         VALUES ($1, ogai_embedding($2, $3, $4))',
                        p_src_schema, p_src_table || '_vector', p_primary_key
                    ) USING v_row.pk, v_row.content, p_embed_model, p_dim;
                END IF;
            END IF;

            v_processed := v_processed + 1;

        EXCEPTION WHEN OTHERS THEN
            v_error_rows := array_append(v_error_rows, v_row.pk);
            v_error_msgs := array_append(v_error_msgs, format('Row %s error at %s: %s', v_row.pk, now(), SQLERRM));
            CONTINUE;
        END;
        END LOOP;
    ELSE
        -- Async task: enqueue all historical data primary keys
        -- Batch insert all non-null content primary keys to queue
        EXECUTE format(
            'INSERT INTO ogai.vectorize_queue (task_id, pk_value, status, vt)
             SELECT $1, %I::INTEGER, ''ready'', CURRENT_TIMESTAMP
             FROM %I.%I
             WHERE %I IS NOT NULL',
            p_primary_key, p_src_schema, p_src_table, p_src_col
        ) USING v_task_id;

        GET DIAGNOSTICS v_processed = ROW_COUNT;

        -- Notify background worker
        PERFORM ogai_notify();
    END IF;

    -- 7. Create indexes
    BEGIN
        IF p_table_method = 'append' THEN
            -- Append mode: create indexes on source table
            -- Create BM25 full-text index based on enable_bm25 parameter
            IF p_enable_bm25 THEN
                EXECUTE format(
                    'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(%I)',
                    p_src_table || '_bm25_idx',
                    p_src_schema, p_src_table, p_src_col
                );
            END IF;
            
            -- Create HNSW vector index
            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING hnsw(ogai_embedding %s)',
                p_src_table || '_vector_idx',
                p_src_schema, p_src_table,
                CASE p_index_type
                    WHEN 'l2' THEN 'vector_l2_ops'
                    WHEN 'ip' THEN 'vector_ip_ops'
                    WHEN 'cosine' THEN 'vector_cosine_ops'
                    ELSE 'vector_l2_ops'
                END
            );
        ELSE
            -- Join mode: create indexes on vector table
            -- Create BM25 index based on enable_bm25 parameter
            IF p_enable_bm25 THEN
                IF p_max_chunk_size > 0 THEN
                    -- Chunking mode: create BM25 index on chunk_text
                    EXECUTE format(
                        'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(chunk_text)',
                        p_src_table || '_vector_bm25_idx',
                        p_src_schema, p_src_table || '_vector'
                    );
                ELSE
                    -- No chunking: create BM25 index on content column of source table
                    EXECUTE format(
                        'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(%I)',
                        p_src_table || '_bm25_idx',
                        p_src_schema, p_src_table, p_src_col
                    );
                END IF;
            END IF;
            
            -- Create HNSW vector index
            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING hnsw(ogai_embedding %s)',
                p_src_table || '_vector_vector_idx',
                p_src_schema, p_src_table || '_vector',
                CASE p_index_type
                    WHEN 'l2' THEN 'vector_l2_ops'
                    WHEN 'ip' THEN 'vector_ip_ops'
                    WHEN 'cosine' THEN 'vector_cosine_ops'
                    ELSE 'vector_l2_ops'
                END
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to create indexes: %', SQLERRM;
    END;

    -- 8. Return processing results
    IF p_task_type = 'sync' THEN
        -- Sync mode result
        IF array_length(v_error_rows, 1) IS NULL THEN
            RETURN QUERY SELECT v_task_id, true, v_processed,
                                format('Sync task completed with table: %s', p_src_table);
        ELSE
            -- Limit error message length to prevent oversized return value
            v_error_summary := array_to_string(v_error_msgs, '; ');
            IF length(v_error_summary) > 8192 THEN
                v_error_summary := left(v_error_summary, 8192) || '... (truncated)';
            END IF;
            RETURN QUERY SELECT v_task_id, false, v_processed,
                                'Partial errors: ' || v_error_summary;
        END IF;
    ELSE
        -- Async mode result
        RETURN QUERY SELECT v_task_id, true, v_processed,
                        format('Async task registered. Enqueued %s existing rows from %I.%I for background processing', 
                               v_processed, p_src_schema, p_src_table);
    END IF;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER;