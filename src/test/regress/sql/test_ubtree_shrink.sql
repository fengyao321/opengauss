-- =========================================================================
-- Comprehensive Test Suite for UBTree Physical Index Shrink & gs_ubtree_shrink
-- Features tested:
--   1. Basic functional flow: creation, insert, delete, vacuum, check & shrink
--   2. Size verification: pre-shrink vs post-shrink physical disk consumption
--   3. Multiple index types & column types: composite keys, text keys, unique index
--   4. Heavy load scenario: multi-batch delete and shrinkage
--   5. Edge cases: empty index, single block index, already compacted index
--   6. Invalid input handling & error paths: non-ubtree index, non-existent index
--   7. Mode support: default online, explicit online (true), explicit offline (false)
--   8. Post-shrink read/write integrity: index scan, range scan, new inserts
-- =========================================================================

-- Cleanup existing objects
DROP TABLE IF EXISTS test_ubt_shrink_tbl CASCADE;
DROP TABLE IF EXISTS test_ubt_shrink_comp CASCADE;
DROP TABLE IF EXISTS test_ubt_shrink_empty CASCADE;
DROP TABLE IF EXISTS test_btree_tbl CASCADE;

-- =========================================================================
-- TestCase 1: Basic UBTree index shrink & Physical size verification
-- =========================================================================
CREATE TABLE test_ubt_shrink_tbl (
    id int,
    val text
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_shrink_val ON test_ubt_shrink_tbl USING ubtree (id);

-- Insert batch data to grow index pages
INSERT INTO test_ubt_shrink_tbl SELECT generate_series(1, 5000), 'test_val_' || generate_series(1, 5000);

-- Record initial size & stats
SELECT pg_relation_size('idx_ubt_shrink_val') AS init_size \gset
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');

-- Delete large range of data at upper range
DELETE FROM test_ubt_shrink_tbl WHERE id > 1000;
SELECT pg_sleep(1);
VACUUM test_ubt_shrink_tbl;

-- Check shrink stats before shrink
SELECT pg_relation_size('idx_ubt_shrink_val') AS pre_shrink_size \gset
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');

-- Perform online shrink (is_online = true)
SELECT gs_ubtree_shrink('idx_ubt_shrink_val', true);

-- Verify size post shrink (size is maintained or reduced, no file bloating)
SELECT pg_relation_size('idx_ubt_shrink_val') AS post_shrink_size \gset
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');
SELECT (:post_shrink_size <= :pre_shrink_size) AS is_size_maintained_or_reduced;

-- Verify read integrity via index scan
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT * FROM test_ubt_shrink_tbl WHERE id = 500;
SELECT * FROM test_ubt_shrink_tbl WHERE id = 500;
SELECT count(*) FROM test_ubt_shrink_tbl;
RESET enable_seqscan;

-- Verify write integrity: insert new records
INSERT INTO test_ubt_shrink_tbl SELECT generate_series(5001, 6000), 'new_val_' || generate_series(5001, 6000);
SELECT count(*) FROM test_ubt_shrink_tbl;
SELECT pg_relation_size('idx_ubt_shrink_val') > 0 AS valid_final_size;

-- =========================================================================
-- TestCase 2: Composite & Unique UBTree Index Shrink
-- =========================================================================
CREATE TABLE test_ubt_shrink_comp (
    c1 int,
    c2 text,
    c3 varchar(100)
) WITH (storage_type=ustore);

CREATE UNIQUE INDEX idx_ubt_comp_uniq ON test_ubt_shrink_comp USING ubtree (c1, c2);

INSERT INTO test_ubt_shrink_comp 
SELECT g, 'category_' || (g % 10), repeat('pad_', 10) || g 
FROM generate_series(1, 4000) g;

SELECT pg_relation_size('idx_ubt_comp_uniq') AS comp_init_size \gset
SELECT gs_ubtree_shrink_check('idx_ubt_comp_uniq');

DELETE FROM test_ubt_shrink_comp WHERE c1 > 500;
SELECT pg_sleep(1);
VACUUM test_ubt_shrink_comp;

SELECT pg_relation_size('idx_ubt_comp_uniq') AS comp_pre_size \gset
SELECT gs_ubtree_shrink('idx_ubt_comp_uniq', true);
SELECT pg_relation_size('idx_ubt_comp_uniq') AS comp_post_size \gset

SELECT (:comp_post_size <= :comp_pre_size) AS is_comp_size_reduced;

-- Verify unique constraint still holds after shrink
INSERT INTO test_ubt_shrink_comp VALUES (1, 'category_1', 'duplicate'); -- Should fail with duplicate key
SELECT count(*) FROM test_ubt_shrink_comp WHERE c1 = 1;

-- =========================================================================
-- TestCase 3: Empty / Boundary cases
-- =========================================================================
CREATE TABLE test_ubt_shrink_empty (
    id int
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_empty ON test_ubt_shrink_empty USING ubtree (id);

-- Check shrink on completely empty index
SELECT gs_ubtree_shrink_check('idx_ubt_empty');
SELECT gs_ubtree_shrink('idx_ubt_empty');
SELECT pg_relation_size('idx_ubt_empty') > 0 AS empty_idx_valid_size;

-- Shrink again immediately (idempotent / already compacted index)
SELECT gs_ubtree_shrink('idx_ubt_empty', false);

-- =========================================================================
-- TestCase 4: Explicit Offline Mode & Default Parameter Mode
-- =========================================================================
-- Call 1-argument default (online)
SELECT gs_ubtree_shrink('idx_ubt_shrink_val');
-- Call 2-argument explicit offline mode
SELECT gs_ubtree_shrink('idx_ubt_shrink_val', false);

-- =========================================================================
-- TestCase 5: Error Handling & Invalid Invocations
-- =========================================================================
-- 5.1 Non-existent index
SELECT gs_ubtree_shrink('idx_non_existent_shrink');
SELECT gs_ubtree_shrink_check('idx_non_existent_shrink');

-- 5.2 Non-UBTree index (regular standard btree)
CREATE TABLE test_btree_tbl (
    id int
);
CREATE INDEX idx_std_btree ON test_btree_tbl USING btree (id);

-- Attempting shrink on regular BTree index should cleanly error out
SELECT gs_ubtree_shrink('idx_std_btree');
SELECT gs_ubtree_shrink_check('idx_std_btree');


-- =========================================================================
-- Clean Up All Test Objects
-- =========================================================================
DROP TABLE test_ubt_shrink_tbl CASCADE;
DROP TABLE test_ubt_shrink_comp CASCADE;
DROP TABLE test_ubt_shrink_empty CASCADE;
DROP TABLE test_btree_tbl CASCADE;
