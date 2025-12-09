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
    -- 检查是否为 UPDATE 操作，如果是则报错
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
                -- join模式：支持文本分块
                -- 先删除旧的文本
                EXECUTE format(
                    'DELETE FROM %I.%I WHERE %I = $1',
                    p_src_schema, p_src_table || '_vector', p_primary_key
                ) USING p_pk_value;
                -- 根据分块大小决定处理方式
                IF p_max_chunk_size > 0 THEN
                    -- 需要分块处理
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
                    -- 不分块，只存储向量
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
    -- 异步模式：写入队列
ELSE
        INSERT INTO ogai.vectorize_queue (message, status, vt)
        VALUES (json_build_array(
            p_task_name,
            json_build_array(p_pk_value)
        )::TEXT, 'ready', CURRENT_TIMESTAMP);
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
    p_task_name TEXT,     -- 任务名称
    p_task_type TEXT,     -- sync或async
    p_index_type TEXT,  -- 索引类型
    p_embed_model TEXT,   --
    p_src_schema TEXT,
    p_src_table TEXT,
    p_src_col TEXT,
    p_primary_key TEXT,
    p_table_method TEXT,  -- append或join
    p_dim INTEGER,
    p_max_chunk_size INTEGER DEFAULT 1000,    -- 新增：最大分块大小
    p_max_chunk_overlap INTEGER DEFAULT 200   -- 新增：分块重叠大小
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
    v_vector_col TEXT := 'ogai_embedding';  -- 新增向量列的默认名称
    v_trigger_name TEXT;
    v_error_rows TEXT[] := '{}';  -- 声明变量
    v_error_msgs TEXT[] := '{}';  -- 声明变量
    v_error_summary TEXT;  -- 声明变量
BEGIN
    -- 1. 验证输入参数
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

    -- 2. 检查任务是否已存在
    PERFORM 1 FROM ogai.vectorize_tasks WHERE task_name = p_task_name;
    IF FOUND THEN
        RETURN QUERY SELECT NULL::INT, false, 0, 'Task already exists: ' || p_task_name;
RETURN;
END IF;

    -- 3. 插入任务记录
INSERT INTO ogai.vectorize_tasks (
    task_name, type, index_type, model_key,
    src_schema, src_table, src_col, primary_key,
    method, dim, max_chunk_size, max_chunk_overlap
) VALUES (
             p_task_name, p_task_type::ogai.task_type, p_index_type, p_embed_model,
             p_src_schema, p_src_table, p_src_col, p_primary_key,
             p_table_method::ogai.table_method, p_dim, p_max_chunk_size, p_max_chunk_overlap
         ) RETURNING task_id INTO v_task_id;

-- 4. 创建触发器
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

    -- 5. 根据method初始化向量存储
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
ELSE  -- join模式：创建独立向量表（在用户schema下）
        PERFORM 1
        FROM information_schema.tables
        WHERE table_schema = p_src_schema
        AND table_name = p_src_table || '_vector';

        IF NOT FOUND THEN
            IF p_max_chunk_size > 0 THEN
                -- 支持分块的表结构
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
                -- 不分块的表结构
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
            -- 非分块模式下的视图
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

    -- 6. 同步任务：处理向量转换
    v_src_query := format(
        'SELECT %I AS pk, %I AS content FROM %I.%I',
        p_primary_key, p_src_col, p_src_schema, p_src_table
    );

FOR v_row IN EXECUTE v_src_query LOOP
BEGIN
            IF v_row.content IS NULL THEN
                v_error := v_error || format('Row %s skipped due to null content; ', v_row.pk);
CONTINUE;
END IF;

            IF p_table_method = 'append' THEN
                -- 追加模式：更新原表的向量列
                EXECUTE format(
                    'UPDATE %I.%I SET %I = ogai_embedding($1, $2, $3) WHERE %I = $4',
                    p_src_schema, p_src_table, v_vector_col, p_primary_key
                ) USING v_row.content, p_embed_model, p_dim, v_row.pk;
ELSE
                -- 连接模式：插入或更新独立向量表
                IF p_max_chunk_size > 0 THEN
                    -- 需要分块处理
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
                    -- 不分块，只存储向量
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

    -- 7. 创建索引
    BEGIN
        IF p_table_method = 'append' THEN
            -- Append模式：在源表上创建索引
            -- 创建BM25全文检索索引
            EXECUTE format(
                'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(%I)',
                p_src_table || '_bm25_idx',
                p_src_schema, p_src_table, p_src_col
            );
            
            -- 创建HNSW向量索引
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
            -- Join模式：在向量表上创建索引
            IF p_max_chunk_size > 0 THEN
                -- 分块模式：对chunk_text建立BM25索引
                EXECUTE format(
                    'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(chunk_text)',
                    p_src_table || '_vector_bm25_idx',
                    p_src_schema, p_src_table || '_vector'
                );
            ELSE
                -- 不分块：对源表的内容列建立BM25索引
                EXECUTE format(
                    'CREATE INDEX IF NOT EXISTS %I ON %I.%I USING bm25(%I)',
                    p_src_table || '_bm25_idx',
                    p_src_schema, p_src_table, p_src_col
                );
            END IF;
            
            -- 创建HNSW向量索引
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

    -- 8. 返回处理结果
    IF array_length(v_error_rows, 1) IS NULL THEN
        RETURN QUERY SELECT v_task_id, true, v_processed,
                            format('Sync task completed with table: %s', p_src_table);
ELSE
        -- 限制错误信息长度，防止返回值过大
        v_error_summary := array_to_string(v_error_msgs, '; ');
        IF length(v_error_summary) > 8192 THEN
            v_error_summary := left(v_error_summary, 8192) || '... (truncated)';
END IF;
RETURN QUERY SELECT v_task_id, false, v_processed,
                        'Partial errors: ' || v_error_summary;
END IF;
END;
$$ LANGUAGE plpgsql
SECURITY INVOKER;

CREATE OR REPLACE FUNCTION ogai.search(
    p_task_name TEXT,
    p_query TEXT,
    p_return_cols TEXT DEFAULT '',
    p_limit INTEGER DEFAULT 10,
    p_where_clause TEXT DEFAULT ''
)
RETURNS TABLE(
    result_record JSONB
) AS $$
DECLARE
    v_task_record ogai.vectorize_tasks%ROWTYPE;
    v_search_query TEXT;
    v_vector_col TEXT := 'ogai_embedding';
    v_embedding_vector TEXT := '';
    v_select_fields TEXT := '';
BEGIN
SELECT * INTO v_task_record
FROM ogai.vectorize_tasks
WHERE task_name = p_task_name;

IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found: %', p_task_name;
END IF;

    -- 根据method确定使用的向量列名和查询方式
    IF v_task_record.method = 'append' THEN
        v_vector_col := 'ogai_embedding';
        -- append模式查询源表
        v_embedding_vector := format(
            'ogai_embedding(%L, %L, %L)',
            p_query,
            v_task_record.model_key,
            v_task_record.dim
        );

        IF p_return_cols IS NOT NULL AND trim(p_return_cols) IS DISTINCT FROM '' THEN
SELECT string_agg(quote_ident(trim(field)), ', ')
INTO v_select_fields
FROM unnest(string_to_array(p_return_cols, ',')) AS field
WHERE trim(field) IS DISTINCT FROM '';

IF v_select_fields IS NOT NULL AND trim(v_select_fields) IS DISTINCT FROM '' THEN
                v_search_query := format(
                    $query$
                    SELECT
                        row_to_json(t)::JSONB AS result_record
                    FROM (
                        SELECT
                            (%I <=> %s) AS similarity_score,
                            %s
                        FROM %I.%I
                        WHERE 1=1 %s
                        ORDER BY %I <=> %s
                        LIMIT %s
                    ) t
                    $query$,
                    v_vector_col,
                    v_embedding_vector,
                    v_select_fields,
                    v_task_record.src_schema,
                    v_task_record.src_table,
                    CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                         THEN ' AND ' || p_where_clause
                         ELSE '' END,
                    v_vector_col,
                    v_embedding_vector,
                    p_limit
                );
ELSE
                v_search_query := format(
                    $query$
                    SELECT
                        row_to_json(t)::JSONB AS result_record
                    FROM (
                        SELECT
                            *,
                            (%I <=> %s) AS similarity_score
                        FROM %I.%I
                        WHERE 1=1 %s
                        ORDER BY %I <=> %s
                        LIMIT %s
                    ) t
                    $query$,
                    v_vector_col,
                    v_embedding_vector,
                    v_task_record.src_schema,
                    v_task_record.src_table,
                    CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                         THEN ' AND ' || p_where_clause
                         ELSE '' END,
                    v_vector_col,
                    v_embedding_vector,
                    p_limit
                );
END IF;
ELSE
            v_search_query := format(
                $query$
                SELECT
                    row_to_json(t)::JSONB AS result_record
                FROM (
                    SELECT
                        *,
                        (%I <=> %s) AS similarity_score
                    FROM %I.%I
                    WHERE 1=1 %s
                    ORDER BY %I <=> %s
                    LIMIT %s
                ) t
                $query$,
                v_vector_col,
                v_embedding_vector,
                v_task_record.src_schema,
                v_task_record.src_table,
                CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                     THEN ' AND ' || p_where_clause
                     ELSE '' END,
                v_vector_col,
                v_embedding_vector,
                p_limit
            );
END IF;
ELSE
        -- join模式查询视图
        v_vector_col := 'ogai_embedding';
        v_embedding_vector := format(
            'ogai_embedding(%L, %L, %L)',
            p_query,
            v_task_record.model_key,
            v_task_record.dim
        );

        IF p_return_cols IS NOT NULL AND trim(p_return_cols) IS DISTINCT FROM '' THEN
SELECT string_agg(quote_ident(trim(field)), ', ')
INTO v_select_fields
FROM unnest(string_to_array(p_return_cols, ',')) AS field
WHERE trim(field) IS DISTINCT FROM '';

IF v_select_fields IS NOT NULL AND trim(v_select_fields) IS DISTINCT FROM '' THEN
                v_search_query := format(
                    $query$
                    SELECT
                        row_to_json(t)::JSONB AS result_record
                    FROM (
                        SELECT
                            (%I <=> %s) AS similarity_score,
                            %s
                        FROM %I.%I
                        WHERE 1=1 %s
                        ORDER BY %I <=> %s
                        LIMIT %s
                    ) t
                    $query$,
                    v_vector_col,
                    v_embedding_vector,
                    v_select_fields,
                    v_task_record.src_schema,
                    v_task_record.src_table || '_vector_view',
                    CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                         THEN ' AND ' || p_where_clause
                         ELSE '' END,
                    v_vector_col,
                    v_embedding_vector,
                    p_limit
                );
ELSE
                v_search_query := format(
                    $query$
                    SELECT
                        row_to_json(t)::JSONB AS result_record
                    FROM (
                        SELECT
                            *,
                            (%I <=> %s) AS similarity_score
                        FROM %I.%I
                        WHERE 1=1 %s
                        ORDER BY %I <=> %s
                        LIMIT %s
                    ) t
                    $query$,
                    v_vector_col,
                    v_embedding_vector,
                    v_task_record.src_schema,
                    v_task_record.src_table || '_vector_view',
                    CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                         THEN ' AND ' || p_where_clause
                         ELSE '' END,
                    v_vector_col,
                    v_embedding_vector,
                    p_limit
                );
END IF;
ELSE
            v_search_query := format(
                $query$
                SELECT
                    row_to_json(t)::JSONB AS result_record
                FROM (
                    SELECT
                        *,
                        (%I <=> %s) AS similarity_score
                    FROM %I.%I
                    WHERE 1=1 %s
                    ORDER BY %I <=> %s
                    LIMIT %s
                ) t
                $query$,
                v_vector_col,
                v_embedding_vector,
                v_task_record.src_schema,
                v_task_record.src_table || '_vector_view',
                CASE WHEN p_where_clause IS NOT NULL AND trim(p_where_clause) IS DISTINCT FROM ''
                     THEN ' AND ' || p_where_clause
                     ELSE '' END,
                v_vector_col,
                v_embedding_vector,
                p_limit
            );
END IF;
END IF;

    --RAISE NOTICE 'Generated SQL: %', v_search_query;
RETURN QUERY EXECUTE v_search_query;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION ogai.ai_unvectorize(
    p_task_name TEXT
) RETURNS TABLE(
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_task_record ogai.vectorize_tasks%ROWTYPE;
    v_trigger_name TEXT;
    v_vector_table TEXT;
    v_vector_view TEXT;
    v_error TEXT := '';
    v_steps_completed TEXT[] := '{}';
BEGIN
    -- 1. 查找任务
    BEGIN
        SELECT * INTO STRICT v_task_record
        FROM ogai.vectorize_tasks
        WHERE task_name = p_task_name;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        RETURN QUERY SELECT false, 'Task not found: ' || p_task_name;
        RETURN;
    END;

    -- 2. 删除触发器
    BEGIN
        v_trigger_name := format('trg_ogai_vectorize_%s', replace(p_task_name, '-', '_'));
        
        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I.%I',
            v_trigger_name,
            v_task_record.src_schema,
            v_task_record.src_table
        );
        
        v_steps_completed := array_append(v_steps_completed, 'Dropped trigger: ' || v_trigger_name);
    EXCEPTION WHEN OTHERS THEN
        v_error := v_error || format('Failed to drop trigger: %s; ', SQLERRM);
    END;

    -- 3. 删除索引
    BEGIN
        IF v_task_record.method = 'append' THEN
            -- Append模式：删除源表上的索引
            EXECUTE format('DROP INDEX IF EXISTS %I.%I',
                v_task_record.src_schema,
                v_task_record.src_table || '_bm25_idx'
            );
            EXECUTE format('DROP INDEX IF EXISTS %I.%I',
                v_task_record.src_schema,
                v_task_record.src_table || '_vector_idx'
            );
        ELSE
            -- Join模式：删除向量表上的索引
            EXECUTE format('DROP INDEX IF EXISTS %I.%I',
                v_task_record.src_schema,
                v_task_record.src_table || '_vector_bm25_idx'
            );
            EXECUTE format('DROP INDEX IF EXISTS %I.%I',
                v_task_record.src_schema,
                v_task_record.src_table || '_bm25_idx'
            );
            EXECUTE format('DROP INDEX IF EXISTS %I.%I',
                v_task_record.src_schema,
                v_task_record.src_table || '_vector_vector_idx'
            );
        END IF;
        v_steps_completed := array_append(v_steps_completed, 'Dropped indexes');
    EXCEPTION WHEN OTHERS THEN
        v_error := v_error || format('Failed to drop indexes: %s; ', SQLERRM);
    END;

    -- 4. 根据method清理资源
    IF v_task_record.method = 'append' THEN
        -- append模式：删除向量列
        BEGIN
            EXECUTE format(
                'ALTER TABLE %I.%I DROP COLUMN IF EXISTS ogai_embedding',
                v_task_record.src_schema,
                v_task_record.src_table
            );
            v_steps_completed := array_append(v_steps_completed, 'Dropped column: ogai_embedding');
        EXCEPTION WHEN OTHERS THEN
            v_error := v_error || format('Failed to drop column: %s; ', SQLERRM);
        END;
    ELSE
        -- join模式：删除向量表和视图（在用户schema下）
        v_vector_table := v_task_record.src_table || '_vector';
        v_vector_view := v_task_record.src_table || '_vector_view';
        
        -- 删除视图
        BEGIN
            EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_task_record.src_schema, v_vector_view);
            v_steps_completed := array_append(v_steps_completed, 'Dropped view: ' || v_task_record.src_schema || '.' || v_vector_view);
        EXCEPTION WHEN OTHERS THEN
            v_error := v_error || format('Failed to drop view: %s; ', SQLERRM);
        END;
        
        -- 删除向量表
        BEGIN
            EXECUTE format('DROP TABLE IF EXISTS %I.%I CASCADE', v_task_record.src_schema, v_vector_table);
            v_steps_completed := array_append(v_steps_completed, 'Dropped table: ' || v_task_record.src_schema || '.' || v_vector_table);
        EXCEPTION WHEN OTHERS THEN
            v_error := v_error || format('Failed to drop table: %s; ', SQLERRM);
        END;
    END IF;

    -- 5. 清理队列中的相关消息
    BEGIN
        DELETE FROM ogai.vectorize_queue
        WHERE message::TEXT LIKE '%' || p_task_name || '%';
        
        v_steps_completed := array_append(v_steps_completed, 'Cleaned queue messages');
    EXCEPTION WHEN OTHERS THEN
        v_error := v_error || format('Failed to clean queue: %s; ', SQLERRM);
    END;

    -- 6. 删除任务记录
    BEGIN
        DELETE FROM ogai.vectorize_tasks
        WHERE task_name = p_task_name;
        
        v_steps_completed := array_append(v_steps_completed, 'Deleted task record');
    EXCEPTION WHEN OTHERS THEN
        v_error := v_error || format('Failed to delete task: %s; ', SQLERRM);
    END;

    -- 7. 返回结果
    IF v_error = '' THEN
        RETURN QUERY SELECT 
            true, 
            'Successfully unvectorized task: ' || p_task_name || E'\n' || 
            'Steps: ' || array_to_string(v_steps_completed, '; ');
    ELSE
        RETURN QUERY SELECT 
            false, 
            'Partial errors during unvectorize: ' || v_error || E'\n' ||
            'Completed steps: ' || array_to_string(v_steps_completed, '; ');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

