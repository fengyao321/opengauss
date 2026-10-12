-- ============================================================================
-- openGauss Ustore Bridge Index Phase 2 (GIN & Anti-Phantom) Automated Test Suite
-- Target Feature: GIN Index Support on Ustore Tables via Bridge Architecture
-- ============================================================================

\echo '>>> [START] Ustore GIN Bridge Index Test Suite Running...'
SET client_min_messages = WARNING;

-- ----------------------------------------------------------------------------
-- Section 1: DDL & Metadata Verification for GIN on Ustore
-- ----------------------------------------------------------------------------
\echo '>>> [TC-GIN-01] Testing CREATE TABLE (ustore) + GIN Array Index...'
DROP TABLE IF EXISTS t_gin_test CASCADE;
CREATE TABLE t_gin_test (
    id INT,
    doc TEXT,
    tags INT[]
) WITH (storage_type = ustore);

CREATE INDEX idx_gin_tags ON t_gin_test USING gin(tags);

\d+ t_gin_test

-- ----------------------------------------------------------------------------
-- Section 2: Data Population and GIN Inverted Search
-- ----------------------------------------------------------------------------
\echo '>>> [TC-GIN-02] Populating data and testing GIN Array Containment Scan (@>)...'
INSERT INTO t_gin_test VALUES (1, 'database kernel', ARRAY[10, 20]);
INSERT INTO t_gin_test VALUES (2, 'cloud storage',   ARRAY[20, 30]);
INSERT INTO t_gin_test VALUES (3, 'bridge index',    ARRAY[10, 30, 40]);
INSERT INTO t_gin_test VALUES (4, 'memory buffer',   ARRAY[50, 60]);

SET enable_seqscan = off;
SET enable_bitmapscan = on;

EXPLAIN (COSTS OFF) SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[20] ORDER BY id;
SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[20] ORDER BY id;

\echo '>>> [TC-GIN-03] Testing GIN Array Overlap Search (&&)...'
EXPLAIN (COSTS OFF) SELECT id, doc FROM t_gin_test WHERE tags && ARRAY[30, 50] ORDER BY id;
SELECT id, doc FROM t_gin_test WHERE tags && ARRAY[30, 50] ORDER BY id;

-- ----------------------------------------------------------------------------
-- Section 3: In-Place Updates, Deletes, and Anti-Phantom Verification
-- ----------------------------------------------------------------------------
\echo '>>> [TC-GIN-04] Testing Non-Key UPDATE on Ustore with GIN Index...'
UPDATE t_gin_test SET doc = 'cloud distributed storage' WHERE id = 2;
SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[20] ORDER BY id;

\echo '>>> [TC-GIN-05] Testing Key UPDATE (tags modified) on Ustore...'
UPDATE t_gin_test SET tags = ARRAY[20, 70] WHERE id = 1;
SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[10] ORDER BY id;
SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[70] ORDER BY id;

\echo '>>> [TC-GIN-06] Testing DELETE on Ustore and verifying index filtering...'
DELETE FROM t_gin_test WHERE id = 3;
SELECT id, doc FROM t_gin_test WHERE tags @> ARRAY[40] ORDER BY id;

-- ----------------------------------------------------------------------------
-- Clean up
-- ----------------------------------------------------------------------------
DROP TABLE t_gin_test CASCADE;
RESET enable_seqscan;
RESET enable_bitmapscan;
\echo '>>> [FINISH] Ustore GIN Bridge Index Test Suite Completed Successfully!'
