-- ============================================================================
-- openGauss Ustore Bridge Index Phase 3: Stress, Edge Cases & Full-Text Search
-- Target Feature: Multi-Index Coexistence, GIN Full-Text Search, Multi-Page Split,
--                 Anti-Phantom Churn, and Transaction Rollback Isolation
-- ============================================================================

\echo '>>> [START] Ustore Bridge Index Phase 3 Stress & Edge Suite Running...'
SET client_min_messages = WARNING;

-- ----------------------------------------------------------------------------
-- Section 1: GIN Full-Text Search (tsvector / tsquery) on Ustore
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-01] Testing GIN Full-Text Search (tsvector) on Ustore...'
DROP TABLE IF EXISTS t_fts_bridge CASCADE;
CREATE TABLE t_fts_bridge (
    id INT,
    title TEXT,
    tsv TSVECTOR
) WITH (storage_type = ustore);

CREATE INDEX idx_fts_gin ON t_fts_bridge USING gin(tsv);

INSERT INTO t_fts_bridge VALUES (1, 'openGauss database kernel', to_tsvector('english', 'openGauss database kernel storage engine'));
INSERT INTO t_fts_bridge VALUES (2, 'cloud distributed database', to_tsvector('english', 'cloud distributed database high availability'));
INSERT INTO t_fts_bridge VALUES (3, 'bridge index router', to_tsvector('english', 'bridge index physical router btree engine'));

SET enable_seqscan = off;
SET enable_bitmapscan = on;

-- Verify execution plan uses Bitmap Index Scan
EXPLAIN (COSTS OFF) SELECT id, title FROM t_fts_bridge WHERE tsv @@ to_tsquery('english', 'openGauss & kernel');
SELECT id, title FROM t_fts_bridge WHERE tsv @@ to_tsquery('english', 'openGauss & kernel');

EXPLAIN (COSTS OFF) SELECT id, title FROM t_fts_bridge WHERE tsv @@ to_tsquery('english', 'router | cloud');
SELECT id, title FROM t_fts_bridge WHERE tsv @@ to_tsquery('english', 'router | cloud') ORDER BY id;

-- ----------------------------------------------------------------------------
-- Section 2: Bridge Router Multi-Page Leaf Split & Binary Search Stress
--            (Insert 2000 rows > 582 entries/page, forcing multiple splits)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-02] Testing Multi-Page Leaf Split (>582 entries) & Router Traversal...'
DROP TABLE IF EXISTS t_router_split CASCADE;
CREATE TABLE t_router_split (
    id INT,
    val INT,
    tags INT[]
) WITH (storage_type = ustore);

CREATE INDEX idx_split_gin ON t_router_split USING gin(tags);

-- Insert 2000 rows in batches to trigger multiple leaf page splits in Bridge Router
INSERT INTO t_router_split 
SELECT g, g * 10, ARRAY[g % 50, (g % 50) + 100] 
FROM generate_series(1, 2000) AS g;

-- Query boundary points across page 0, page 1, page 2, page 3
-- Tag 25 should appear in rows where g % 50 = 25 (e.g., 25, 75, 125, ..., 1975 -> 40 rows)
SELECT count(*) FROM t_router_split WHERE tags @> ARRAY[25];

-- Query boundary keys at the beginning and end of the dataset
SELECT id, val FROM t_router_split WHERE tags @> ARRAY[0, 100] AND id IN (50, 582, 583, 1164, 1165, 2000) ORDER BY id;

-- ----------------------------------------------------------------------------
-- Section 3: Multi-Index Coexistence on Single Ustore Table
--            (UBTree + Hash + GiST + GIN simultaneously)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-03] Testing Single Table with 4 Indexes: UBTree + Hash + GiST + GIN...'
DROP TABLE IF EXISTS t_multi_idx CASCADE;
CREATE TABLE t_multi_idx (
    id INT,
    token TEXT,
    pos POINT,
    categories INT[]
) WITH (storage_type = ustore);

CREATE INDEX idx_m_ubtree ON t_multi_idx USING ubtree(id);
CREATE INDEX idx_m_hash   ON t_multi_idx USING hash(token);
CREATE INDEX idx_m_gist   ON t_multi_idx USING gist(pos);
CREATE INDEX idx_m_gin    ON t_multi_idx USING gin(categories);

\d+ t_multi_idx

INSERT INTO t_multi_idx VALUES (1, 'ALPHA', point(10, 20), ARRAY[1, 100]);
INSERT INTO t_multi_idx VALUES (2, 'BETA',  point(30, 40), ARRAY[2, 200]);
INSERT INTO t_multi_idx VALUES (3, 'GAMMA', point(50, 60), ARRAY[3, 100]);

-- Test UBTree query
SELECT id, token FROM t_multi_idx WHERE id = 2;

-- Test Hash query
SELECT id, token FROM t_multi_idx WHERE token = 'GAMMA';

-- Test GiST query
SELECT id, token FROM t_multi_idx WHERE pos <@ box '(35,45),(25,35)';

-- Test GIN query
SELECT id, token FROM t_multi_idx WHERE categories @> ARRAY[100] ORDER BY id;

-- ----------------------------------------------------------------------------
-- Section 4: GIN Transaction Rollback Isolation (Zero Dirty Reads)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-04] Testing GIN Transaction Rollback Isolation...'
BEGIN;
INSERT INTO t_multi_idx VALUES (999, 'GHOST', point(99, 99), ARRAY[999]);
SELECT id, token FROM t_multi_idx WHERE categories @> ARRAY[999];
ROLLBACK;

-- Verify phantom entry is not visible after rollback
SELECT count(*) FROM t_multi_idx WHERE categories @> ARRAY[999];

-- ----------------------------------------------------------------------------
-- Section 5: High-Frequency Slot Churn Anti-Phantom Verification
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-05] Testing High-Frequency Churn and Slot Reuse...'
DROP TABLE IF EXISTS t_churn_test CASCADE;
CREATE TABLE t_churn_test (
    id INT,
    tags INT[]
) WITH (storage_type = ustore);

CREATE INDEX idx_churn_gin ON t_churn_test USING gin(tags);

INSERT INTO t_churn_test SELECT g, ARRAY[g] FROM generate_series(1, 100) AS g;

-- Delete odd records
DELETE FROM t_churn_test WHERE id % 2 = 1;

-- Force vacuum to clean deleted dead slots for reuse
VACUUM t_churn_test;

-- Insert new records with distinct tags into potentially reused slots
INSERT INTO t_churn_test SELECT g + 1000, ARRAY[g + 1000] FROM generate_series(1, 50) AS g;

-- Verify deleted tags are NOT found
SELECT count(*) FROM t_churn_test WHERE tags @> ARRAY[1];
SELECT count(*) FROM t_churn_test WHERE tags @> ARRAY[99];

-- Verify new tags ARE found
SELECT count(*) FROM t_churn_test WHERE tags @> ARRAY[1001];
SELECT count(*) FROM t_churn_test WHERE tags @> ARRAY[1050];

-- ----------------------------------------------------------------------------
-- Section 6: NULL and Empty Array Edge Cases
-- ----------------------------------------------------------------------------
\echo '>>> [TC-ADV-06] Testing NULL and Empty Array Edge Cases in GIN...'
INSERT INTO t_churn_test VALUES (8888, ARRAY[]::int[]);
INSERT INTO t_churn_test VALUES (9999, NULL);

SELECT count(*) FROM t_churn_test WHERE tags IS NULL;
SELECT id FROM t_churn_test WHERE id IN (8888, 9999) ORDER BY id;

-- ----------------------------------------------------------------------------
-- Clean up
-- ----------------------------------------------------------------------------
DROP TABLE t_fts_bridge CASCADE;
DROP TABLE t_router_split CASCADE;
DROP TABLE t_multi_idx CASCADE;
DROP TABLE t_churn_test CASCADE;
RESET enable_seqscan;
RESET enable_bitmapscan;

\echo '>>> [FINISH] Phase 3 Stress & Edge Suite Executed Successfully!'
