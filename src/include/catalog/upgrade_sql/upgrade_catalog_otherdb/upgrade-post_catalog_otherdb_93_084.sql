CREATE OR REPLACE VIEW DBE_PERF.pg_indexes_verbose_enhanced AS
WITH index_raw AS (
    SELECT
        i.indrelid,
        i.indexrelid,
        array_length(i.indkey, 1) as len,
        array(select unnest(i.indkey)) AS key_array,
        c.relname AS indexname,
        tc.relname AS tablename,
        n.nspname AS schemaname,
        am.amname
    FROM
        pg_index i
        JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
        JOIN pg_catalog.pg_class tc ON tc.oid = i.indrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = tc.relnamespace
        JOIN pg_catalog.pg_am am ON am.oid = c.relam
),
overlap AS (
    SELECT
        a.indrelid,
        a.indexrelid,
        json_agg(
            json_build_object(
                'index_name', b.indexname,
                'amname', b.amname,
                'columns', (
                  SELECT array_agg(attname ORDER BY attnum) FROM pg_catalog.pg_attribute WHERE attrelid = b.indexrelid
                )
            )
        ) AS overlap_info
    FROM
        index_raw a
        JOIN index_raw b ON a.indrelid = b.indrelid
                        AND a.indexrelid != b.indexrelid
    WHERE
        b.len >= a.len
        AND
        b.key_array[1:(a.len)] = a.key_array
    GROUP BY
        a.indrelid,
        a.indexrelid
)
SELECT
    i.indrelid,
    i.indexrelid,
    i.tablename,
    i.schemaname,
    i.indexname,
    i.amname,
    (
        SELECT array_agg(attname ORDER BY attnum) FROM pg_catalog.pg_attribute WHERE attrelid = i.indexrelid
    ) AS index_columns,
    s.idx_scan,
    s.idx_tup_read,
    s.idx_tup_fetch,
    o.overlap_info
FROM
    index_raw i
    LEFT JOIN overlap o ON i.indexrelid = o.indexrelid
    LEFT JOIN pg_catalog.pg_stat_all_indexes s ON s.indexrelid = i.indexrelid;

CREATE OR REPLACE VIEW DBE_PERF.pg_indexes_verbose AS
WITH index_raw AS (
    SELECT
        i.indrelid,
        i.indexrelid,
        array_length(i.indkey, 1) as len,
        array(select unnest(i.indkey)) AS key_array,
        c.relname AS indexname,
        tc.relname AS tablename,
        n.nspname AS schemaname,
        am.amname
    FROM
        pg_index i
        JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid
        JOIN pg_catalog.pg_class tc ON tc.oid = i.indrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = tc.relnamespace
        JOIN pg_catalog.pg_am am ON am.oid = c.relam
),
overlap AS (
    SELECT
        a.indrelid,
        a.indexrelid,
        json_agg(
            json_build_object(
                'index_name', b.indexname,
                'amname', b.amname
            )
        ) AS overlap_info
    FROM
        index_raw a
        JOIN index_raw b ON a.indrelid = b.indrelid
                        AND a.indexrelid != b.indexrelid
    WHERE
        b.len >= a.len
        AND
        b.key_array[1:(a.len)] = a.key_array
    GROUP BY
        a.indrelid,
        a.indexrelid
)
SELECT
    i.indrelid,
    i.indexrelid,
    i.tablename,
    i.schemaname,
    i.indexname,
    i.amname,
    s.idx_scan,
    s.idx_tup_read,
    s.idx_tup_fetch,
    o.overlap_info
FROM
    index_raw i
    LEFT JOIN overlap o ON i.indexrelid = o.indexrelid
    LEFT JOIN pg_catalog.pg_stat_all_indexes s ON s.indexrelid = i.indexrelid
WHERE
    i.schemaname <> 'pg_catalog'
    and i.schemaname <> 'db4ai'
    and i.schemaname <> 'information_schema'
    and i.schemaname !~ '^pg_toast'
    and i.tablename not like 'matviewmap\_%'
    and i.tablename not like 'mlog\_%'
    and pg_catalog.pg_table_is_visible(i.indrelid)
ORDER BY
    i.indrelid, i.indexrelid;
