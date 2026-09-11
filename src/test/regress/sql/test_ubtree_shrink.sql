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
--   9. Forward and backward index scan integrity (ASC/DESC, range, aggregates)
--  10. Partial index shrink (WHERE predicate filtering & verification)
--  11. Multi-type & NULLS sorting indexes (timestamp, numeric, NULLS FIRST)
--  12. Transaction rollback & abort safety (delete rollback, insert rollback)
--  13. Multi-round growth and shrink lifecycle & idempotency
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
-- TestCase 6: Forward and Backward Index Scan Integrity
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_scan CASCADE;
CREATE TABLE test_ubt_scan (
    id int,
    val text
) WITH (storage_type=ustore);
CREATE INDEX idx_ubt_scan_id ON test_ubt_scan USING ubtree (id);

INSERT INTO test_ubt_scan SELECT g, 'val_' || g FROM generate_series(1, 4000) g;
DELETE FROM test_ubt_scan WHERE id > 1000;
SELECT pg_sleep(1);
VACUUM test_ubt_scan;

SELECT gs_ubtree_shrink_check('idx_ubt_scan_id');
SELECT gs_ubtree_shrink('idx_ubt_scan_id', true);

SET enable_seqscan = off;
SET enable_bitmapscan = off;

-- Forward scan (ASC)
SELECT id FROM test_ubt_scan ORDER BY id ASC LIMIT 5;

-- Backward scan (DESC)
SELECT id FROM test_ubt_scan ORDER BY id DESC LIMIT 5;

-- Forward range scan
SELECT id FROM test_ubt_scan WHERE id BETWEEN 500 AND 505 ORDER BY id ASC;

-- Backward range scan
SELECT id FROM test_ubt_scan WHERE id BETWEEN 500 AND 505 ORDER BY id DESC;

-- Aggregate check
SELECT count(*), sum(id), min(id), max(id) FROM test_ubt_scan;

RESET enable_seqscan;
RESET enable_bitmapscan;
DROP TABLE test_ubt_scan CASCADE;

-- =========================================================================
-- TestCase 7: Partial Index Shrink (WHERE clause)
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_part CASCADE;
CREATE TABLE test_ubt_part (
    id int,
    status varchar(20),
    info text
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_part_active ON test_ubt_part USING ubtree (id) WHERE status = 'active';

INSERT INTO test_ubt_part
SELECT g, CASE WHEN g <= 3000 THEN 'active' ELSE 'inactive' END, 'info_' || g
FROM generate_series(1, 4000) g;

DELETE FROM test_ubt_part WHERE status = 'active' AND id > 500;
SELECT pg_sleep(1);
VACUUM test_ubt_part;

SELECT gs_ubtree_shrink_check('idx_ubt_part_active');
SELECT gs_ubtree_shrink('idx_ubt_part_active');

SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT id FROM test_ubt_part WHERE status = 'active' AND id = 250;
SELECT id FROM test_ubt_part WHERE status = 'active' AND id = 250;
SELECT count(*) FROM test_ubt_part WHERE status = 'active';
RESET enable_seqscan;
DROP TABLE test_ubt_part CASCADE;

-- =========================================================================
-- TestCase 8: Multi-Type Indexing (timestamp, numeric, NULLS)
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_types CASCADE;
CREATE TABLE test_ubt_types (
    id int,
    ts timestamp,
    amount numeric(10,2)
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_types_all ON test_ubt_types USING ubtree (ts, amount);
CREATE INDEX idx_ubt_types_nulls ON test_ubt_types USING ubtree (amount NULLS FIRST);

INSERT INTO test_ubt_types
SELECT g,
       ('2026-01-01'::timestamp + (g || ' hours')::interval),
       CASE WHEN g % 10 = 0 THEN NULL ELSE (g * 1.5)::numeric(10,2) END
FROM generate_series(1, 3000) g;

DELETE FROM test_ubt_types WHERE id > 500;
SELECT pg_sleep(1);
VACUUM test_ubt_types;

SELECT gs_ubtree_shrink('idx_ubt_types_all');
SELECT gs_ubtree_shrink('idx_ubt_types_nulls');

SET enable_seqscan = off;
-- Nulls scan verification
SELECT count(*) FROM test_ubt_types WHERE amount IS NULL;
SELECT count(*) FROM test_ubt_types WHERE amount IS NOT NULL;
SELECT count(*) FROM test_ubt_types WHERE ts > '2026-01-01'::timestamp;
RESET enable_seqscan;
DROP TABLE test_ubt_types CASCADE;

-- =========================================================================
-- TestCase 9: Transaction Rollback & Abort Safety
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_tx CASCADE;
CREATE TABLE test_ubt_tx (
    id int
) WITH (storage_type=ustore);
CREATE INDEX idx_ubt_tx_id ON test_ubt_tx USING ubtree (id);

INSERT INTO test_ubt_tx SELECT generate_series(1, 1000);

-- Transaction that deletes but rolls back
BEGIN;
DELETE FROM test_ubt_tx WHERE id > 200;
ROLLBACK;

SELECT pg_sleep(1);
VACUUM test_ubt_tx;

-- Shrink must NOT delete live data protected by rollback
SELECT gs_ubtree_shrink('idx_ubt_tx_id');
SELECT count(*) FROM test_ubt_tx;

-- Transaction that inserts but rolls back
BEGIN;
INSERT INTO test_ubt_tx SELECT generate_series(1001, 3000);
ROLLBACK;

SELECT pg_sleep(1);
VACUUM test_ubt_tx;

SELECT gs_ubtree_shrink_check('idx_ubt_tx_id');
SELECT gs_ubtree_shrink('idx_ubt_tx_id');
SELECT count(*) FROM test_ubt_tx;
DROP TABLE test_ubt_tx CASCADE;

-- =========================================================================
-- TestCase 10: Multi-Round Continuous Growth and Shrink Lifecycle
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_cycle CASCADE;
CREATE TABLE test_ubt_cycle (
    id int,
    data text
) WITH (storage_type=ustore);
CREATE INDEX idx_ubt_cycle_id ON test_ubt_cycle USING ubtree (id);

-- Cycle 1: Insert 3000, Delete 2000, Shrink
INSERT INTO test_ubt_cycle SELECT g, 'cycle1_' || g FROM generate_series(1, 3000) g;
DELETE FROM test_ubt_cycle WHERE id > 1000;
SELECT pg_sleep(1);
VACUUM test_ubt_cycle;
SELECT gs_ubtree_shrink('idx_ubt_cycle_id');
SELECT count(*) FROM test_ubt_cycle;

-- Cycle 2: Insert 2000 new records, Delete 1500, Shrink again
INSERT INTO test_ubt_cycle SELECT g, 'cycle2_' || g FROM generate_series(3001, 5000) g;
DELETE FROM test_ubt_cycle WHERE id > 3500;
SELECT pg_sleep(1);
VACUUM test_ubt_cycle;
SELECT gs_ubtree_shrink('idx_ubt_cycle_id');
SELECT count(*) FROM test_ubt_cycle;

-- Cycle 3: Immediate second shrink (idempotent)
SELECT gs_ubtree_shrink('idx_ubt_cycle_id');
SELECT count(*) FROM test_ubt_cycle;

-- Final read integrity
SET enable_seqscan = off;
SELECT count(*) FROM test_ubt_cycle WHERE id BETWEEN 500 AND 3200;
RESET enable_seqscan;

DROP TABLE test_ubt_cycle CASCADE;

-- =========================================================================
-- Clean Up All Test Objects
-- =========================================================================
DROP TABLE IF EXISTS test_ubt_shrink_tbl CASCADE;
DROP TABLE IF EXISTS test_ubt_shrink_comp CASCADE;
DROP TABLE IF EXISTS test_ubt_shrink_empty CASCADE;
DROP TABLE IF EXISTS test_btree_tbl CASCADE;
DROP TABLE IF EXISTS test_ubt_scan CASCADE;
DROP TABLE IF EXISTS test_ubt_part CASCADE;
DROP TABLE IF EXISTS test_ubt_types CASCADE;
DROP TABLE IF EXISTS test_ubt_tx CASCADE;
DROP TABLE IF EXISTS test_ubt_cycle CASCADE;
