DROP TABLE IF EXISTS test_fifo_diag;
CREATE TABLE test_fifo_diag (id int, val text) WITH (storage_type=ustore);
INSERT INTO test_fifo_diag SELECT g, 'val_' || g FROM generate_series(1, 200000) g;
CREATE INDEX idx_fifo_diag_id ON test_fifo_diag USING ubtree(id);

\echo '=== 1. Initial State ==='
SELECT pg_size_pretty(pg_relation_size('idx_fifo_diag_id')) AS initial_index_size;

DELETE FROM test_fifo_diag WHERE id <= 160000;
SELECT pg_sleep(2);
SELECT txid_current();
VACUUM test_fifo_diag;

\echo '=== 2. After VACUUM (Before Shrink) ==='
SELECT pg_size_pretty(pg_relation_size('idx_fifo_diag_id')) AS pre_shrink_index_size;
SELECT gs_ubtree_shrink_check('idx_fifo_diag_id');

\echo '=== 3. Executing gs_ubtree_shrink ==='
SELECT gs_ubtree_shrink('idx_fifo_diag_id', false);

\echo '=== 4. After Shrink ==='
SELECT pg_size_pretty(pg_relation_size('idx_fifo_diag_id')) AS post_shrink_index_size;

\echo '=== 5. Verification Queries ==='
SELECT count(*) AS remaining_count FROM test_fifo_diag;
SELECT * FROM test_fifo_diag ORDER BY id DESC LIMIT 5;
SELECT * FROM test_fifo_diag ORDER BY id ASC LIMIT 5;
SELECT * FROM test_fifo_diag WHERE id = 180000;
SELECT count(*) FROM test_fifo_diag WHERE id BETWEEN 160001 AND 170000;
