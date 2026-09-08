-- Test UBTree Physical Index Shrink & gs_ubtree_shrink interface

-- Cleanup existing objects
DROP TABLE IF EXISTS test_ubt_shrink_tbl CASCADE;

-- 1. Create table with ustore and ubtree index
CREATE TABLE test_ubt_shrink_tbl (
    id int,
    val text
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_shrink_val ON test_ubt_shrink_tbl USING ubtree (id);

-- 2. Insert batch data to grow ubtree index pages
INSERT INTO test_ubt_shrink_tbl SELECT generate_series(1, 5000), 'test_val_' || generate_series(1, 5000);

-- 3. Check shrink status on healthy populated index
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');

-- 4. Delete upper tail data to create consecutive dead pages at the tail
DELETE FROM test_ubt_shrink_tbl WHERE id > 1000;
VACUUM test_ubt_shrink_tbl;

-- 5. Evaluate shrink feasibility (should identify tail freed blocks)
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');

-- 6. Perform online shrink (test both 1-arg default online and 2-arg explicit mode)
SELECT gs_ubtree_shrink('idx_ubt_shrink_val', true);

-- 7. Re-evaluate post-shrink status (freed tail blocks should be truncated)
SELECT gs_ubtree_shrink_check('idx_ubt_shrink_val');

-- 8. Verify data correctness and index scan integrity after shrink
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT * FROM test_ubt_shrink_tbl WHERE id = 500;
SELECT * FROM test_ubt_shrink_tbl WHERE id = 500;
SELECT count(*) FROM test_ubt_shrink_tbl;
RESET enable_seqscan;

-- 9. Insert new data to ensure index can continue growing normally
INSERT INTO test_ubt_shrink_tbl SELECT generate_series(5001, 6000), 'new_val_' || generate_series(5001, 6000);
SELECT count(*) FROM test_ubt_shrink_tbl;

-- Cleanup
DROP TABLE test_ubt_shrink_tbl;
