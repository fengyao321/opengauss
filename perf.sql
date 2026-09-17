-- =========================================================================
-- Performance Benchmark: VACUUM FULL vs REINDEX vs gs_ubtree_shrink
-- Tests multiple data scales with timing and space measurements
-- =========================================================================
\timing on

-- =========================================================================
-- Cleanup
-- =========================================================================
DROP TABLE IF EXISTS perf_shrink CASCADE;
DROP TABLE IF EXISTS perf_vacuum CASCADE;
DROP TABLE IF EXISTS perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 1: 100K rows, delete 80%
-- =========================================================================
\echo '======================================================================'
\echo 'SCENARIO 1: 100K rows, delete 80% (tail deletion pattern)'
\echo '======================================================================'

-- --- Setup: SHRINK table ---
CREATE TABLE perf_shrink (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_shrink_id ON perf_shrink USING ubtree (id);
CREATE INDEX idx_perf_shrink_cat ON perf_shrink USING ubtree (category);

INSERT INTO perf_shrink
SELECT g, 'payload_data_' || g || repeat('x', 50), g % 100, now() - (g || ' seconds')::interval
FROM generate_series(1, 100000) g;

-- --- Setup: VACUUM FULL table (identical data) ---
CREATE TABLE perf_vacuum (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_vacuum_id ON perf_vacuum USING ubtree (id);
CREATE INDEX idx_perf_vacuum_cat ON perf_vacuum USING ubtree (category);

INSERT INTO perf_vacuum
SELECT g, 'payload_data_' || g || repeat('x', 50), g % 100, now() - (g || ' seconds')::interval
FROM generate_series(1, 100000) g;

-- --- Setup: REINDEX table (identical data) ---
CREATE TABLE perf_reindex (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_reindex_id ON perf_reindex USING ubtree (id);
CREATE INDEX idx_perf_reindex_cat ON perf_reindex USING ubtree (category);

INSERT INTO perf_reindex
SELECT g, 'payload_data_' || g || repeat('x', 50), g % 100, now() - (g || ' seconds')::interval
FROM generate_series(1, 100000) g;

-- Record initial sizes
\echo '--- Initial Index Sizes (100K rows) ---'
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum_id', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex_id', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

-- Delete 80% of data (upper range) from all three tables
DELETE FROM perf_shrink WHERE id > 20000;
DELETE FROM perf_vacuum WHERE id > 20000;
DELETE FROM perf_reindex WHERE id > 20000;

-- Wait for transaction visibility
SELECT pg_sleep(2);
SELECT txid_current();

-- VACUUM to clean dead tuples (required for shrink to detect freed pages)
VACUUM perf_shrink;
VACUUM perf_vacuum;
VACUUM perf_reindex;

\echo '--- Post-Delete / Post-VACUUM Index Sizes (before compaction) ---'
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum_id', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex_id', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

-- Check shrink stats
\echo '--- Shrink Check Stats ---'
SELECT gs_ubtree_shrink_check('idx_perf_shrink_id');

-- ===== METHOD 1: gs_ubtree_shrink (Online) =====
\echo ''
\echo '>>> METHOD 1: gs_ubtree_shrink (Online Mode) <<<'
\echo '--- Timing START: gs_ubtree_shrink on idx_perf_shrink_id ---'
SELECT gs_ubtree_shrink('idx_perf_shrink_id', false);
\echo '--- Timing END: gs_ubtree_shrink on idx_perf_shrink_id ---'

\echo '--- Timing START: gs_ubtree_shrink on idx_perf_shrink_cat ---'
SELECT gs_ubtree_shrink('idx_perf_shrink_cat', false);
\echo '--- Timing END: gs_ubtree_shrink on idx_perf_shrink_cat ---'

-- ===== METHOD 2: VACUUM FULL =====
\echo ''
\echo '>>> METHOD 2: VACUUM FULL <<<'
\echo '--- Timing START: VACUUM FULL perf_vacuum ---'
VACUUM FULL perf_vacuum;
\echo '--- Timing END: VACUUM FULL perf_vacuum ---'

-- ===== METHOD 3: REINDEX =====
\echo ''
\echo '>>> METHOD 3: REINDEX <<<'
\echo '--- Timing START: REINDEX idx_perf_reindex_id ---'
REINDEX INDEX idx_perf_reindex_id;
\echo '--- Timing END: REINDEX idx_perf_reindex_id ---'

\echo '--- Timing START: REINDEX idx_perf_reindex_cat ---'
REINDEX INDEX idx_perf_reindex_cat;
\echo '--- Timing END: REINDEX idx_perf_reindex_cat ---'

-- ===== Results: Post-Compaction Sizes =====
\echo ''
\echo '=== SCENARIO 1 RESULTS: Post-Compaction Sizes ==='
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'shrink_cat', pg_relation_size('idx_perf_shrink_cat'), pg_size_pretty(pg_relation_size('idx_perf_shrink_cat'))
UNION ALL
SELECT 'vacuum_id', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'vacuum_cat', pg_relation_size('idx_perf_vacuum_cat'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_cat'))
UNION ALL
SELECT 'reindex_id', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'))
UNION ALL
SELECT 'reindex_cat', pg_relation_size('idx_perf_reindex_cat'), pg_size_pretty(pg_relation_size('idx_perf_reindex_cat'));

-- Also check table sizes
\echo '--- Table Sizes ---'
SELECT 'perf_shrink' AS tbl, pg_relation_size('perf_shrink') AS bytes, pg_size_pretty(pg_relation_size('perf_shrink')) AS size
UNION ALL
SELECT 'perf_vacuum', pg_relation_size('perf_vacuum'), pg_size_pretty(pg_relation_size('perf_vacuum'))
UNION ALL
SELECT 'perf_reindex', pg_relation_size('perf_reindex'), pg_size_pretty(pg_relation_size('perf_reindex'));

-- Data integrity check
\echo '--- Data Integrity Check ---'
SELECT 'shrink' AS method, count(*) AS rows FROM perf_shrink
UNION ALL
SELECT 'vacuum', count(*) FROM perf_vacuum
UNION ALL
SELECT 'reindex', count(*) FROM perf_reindex;

-- Cleanup scenario 1
DROP TABLE perf_shrink CASCADE;
DROP TABLE perf_vacuum CASCADE;
DROP TABLE perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 2: 500K rows, delete 90% (heavy bloat)
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 2: 500K rows, delete 90% (heavy bloat scenario)'
\echo '======================================================================'

CREATE TABLE perf_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_shrink_id ON perf_shrink USING ubtree (id);

CREATE TABLE perf_vacuum (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_vacuum_id ON perf_vacuum USING ubtree (id);

CREATE TABLE perf_reindex (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_reindex_id ON perf_reindex USING ubtree (id);

INSERT INTO perf_shrink SELECT g, 'data_' || g FROM generate_series(1, 500000) g;
INSERT INTO perf_vacuum SELECT g, 'data_' || g FROM generate_series(1, 500000) g;
INSERT INTO perf_reindex SELECT g, 'data_' || g FROM generate_series(1, 500000) g;

\echo '--- Initial Sizes (500K rows) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

-- Delete 90% (keep first 50K)
DELETE FROM perf_shrink WHERE id > 50000;
DELETE FROM perf_vacuum WHERE id > 50000;
DELETE FROM perf_reindex WHERE id > 50000;

SELECT pg_sleep(2);
SELECT txid_current();
VACUUM perf_shrink;
VACUUM perf_vacuum;
VACUUM perf_reindex;

\echo '--- Post-Delete Sizes (500K, 90% deleted) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

SELECT gs_ubtree_shrink_check('idx_perf_shrink_id');

-- Execute compaction methods
\echo ''
\echo '>>> gs_ubtree_shrink (Online) <<<'
SELECT gs_ubtree_shrink('idx_perf_shrink_id', false);

\echo ''
\echo '>>> VACUUM FULL <<<'
VACUUM FULL perf_vacuum;

\echo ''
\echo '>>> REINDEX <<<'
REINDEX INDEX idx_perf_reindex_id;

\echo ''
\echo '=== SCENARIO 2 RESULTS ==='
SELECT 'shrink' AS method, pg_relation_size('idx_perf_shrink_id') AS idx_bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS idx_size,
       pg_relation_size('perf_shrink') AS tbl_bytes, pg_size_pretty(pg_relation_size('perf_shrink')) AS tbl_size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id')),
       pg_relation_size('perf_vacuum'), pg_size_pretty(pg_relation_size('perf_vacuum'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id')),
       pg_relation_size('perf_reindex'), pg_size_pretty(pg_relation_size('perf_reindex'));

-- Integrity check
SELECT 'shrink' AS method, count(*) FROM perf_shrink
UNION ALL SELECT 'vacuum', count(*) FROM perf_vacuum
UNION ALL SELECT 'reindex', count(*) FROM perf_reindex;

DROP TABLE perf_shrink CASCADE;
DROP TABLE perf_vacuum CASCADE;
DROP TABLE perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 3: 200K rows, scattered delete pattern (50% random delete)
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 3: 200K rows, scattered delete (every other row)'
\echo '======================================================================'

CREATE TABLE perf_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_shrink_id ON perf_shrink USING ubtree (id);

CREATE TABLE perf_vacuum (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_vacuum_id ON perf_vacuum USING ubtree (id);

CREATE TABLE perf_reindex (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_reindex_id ON perf_reindex USING ubtree (id);

INSERT INTO perf_shrink SELECT g, 'data_' || g FROM generate_series(1, 200000) g;
INSERT INTO perf_vacuum SELECT g, 'data_' || g FROM generate_series(1, 200000) g;
INSERT INTO perf_reindex SELECT g, 'data_' || g FROM generate_series(1, 200000) g;

\echo '--- Initial Sizes (200K rows) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

-- Delete every other row (scattered pattern - harder for shrink)
DELETE FROM perf_shrink WHERE id % 2 = 0;
DELETE FROM perf_vacuum WHERE id % 2 = 0;
DELETE FROM perf_reindex WHERE id % 2 = 0;

SELECT pg_sleep(2);
SELECT txid_current();
VACUUM perf_shrink;
VACUUM perf_vacuum;
VACUUM perf_reindex;

\echo '--- Post-Delete Sizes (200K, 50% scattered delete) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

SELECT gs_ubtree_shrink_check('idx_perf_shrink_id');

\echo ''
\echo '>>> gs_ubtree_shrink (Online) <<<'
SELECT gs_ubtree_shrink('idx_perf_shrink_id', false);

\echo ''
\echo '>>> VACUUM FULL <<<'
VACUUM FULL perf_vacuum;

\echo ''
\echo '>>> REINDEX <<<'
REINDEX INDEX idx_perf_reindex_id;

\echo ''
\echo '=== SCENARIO 3 RESULTS ==='
SELECT 'shrink' AS method, pg_relation_size('idx_perf_shrink_id') AS idx_bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS idx_size,
       pg_relation_size('perf_shrink') AS tbl_bytes, pg_size_pretty(pg_relation_size('perf_shrink')) AS tbl_size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id')),
       pg_relation_size('perf_vacuum'), pg_size_pretty(pg_relation_size('perf_vacuum'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id')),
       pg_relation_size('perf_reindex'), pg_size_pretty(pg_relation_size('perf_reindex'));

SELECT 'shrink' AS method, count(*) FROM perf_shrink
UNION ALL SELECT 'vacuum', count(*) FROM perf_vacuum
UNION ALL SELECT 'reindex', count(*) FROM perf_reindex;

DROP TABLE perf_shrink CASCADE;
DROP TABLE perf_vacuum CASCADE;
DROP TABLE perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 4: 1M rows, delete 95% (extreme bloat)
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 4: 1M rows, delete 95% (extreme bloat, tail deletion)'
\echo '======================================================================'

CREATE TABLE perf_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_shrink_id ON perf_shrink USING ubtree (id);

CREATE TABLE perf_vacuum (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_vacuum_id ON perf_vacuum USING ubtree (id);

CREATE TABLE perf_reindex (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_reindex_id ON perf_reindex USING ubtree (id);

\echo '--- Inserting 1M rows into 3 tables... ---'
INSERT INTO perf_shrink SELECT g, 'data_' || g FROM generate_series(1, 1000000) g;
INSERT INTO perf_vacuum SELECT g, 'data_' || g FROM generate_series(1, 1000000) g;
INSERT INTO perf_reindex SELECT g, 'data_' || g FROM generate_series(1, 1000000) g;

\echo '--- Initial Sizes (1M rows) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

-- Delete 95% (keep first 50K)
DELETE FROM perf_shrink WHERE id > 50000;
DELETE FROM perf_vacuum WHERE id > 50000;
DELETE FROM perf_reindex WHERE id > 50000;

SELECT pg_sleep(2);
SELECT txid_current();
VACUUM perf_shrink;
VACUUM perf_vacuum;
VACUUM perf_reindex;

\echo '--- Post-Delete Sizes (1M, 95% deleted) ---'
SELECT 'shrink' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'));

SELECT gs_ubtree_shrink_check('idx_perf_shrink_id');

\echo ''
\echo '>>> gs_ubtree_shrink (Online) <<<'
SELECT gs_ubtree_shrink('idx_perf_shrink_id', false);

\echo ''
\echo '>>> VACUUM FULL <<<'
VACUUM FULL perf_vacuum;

\echo ''
\echo '>>> REINDEX <<<'
REINDEX INDEX idx_perf_reindex_id;

\echo ''
\echo '=== SCENARIO 4 RESULTS ==='
SELECT 'shrink' AS method, pg_relation_size('idx_perf_shrink_id') AS idx_bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS idx_size,
       pg_relation_size('perf_shrink') AS tbl_bytes, pg_size_pretty(pg_relation_size('perf_shrink')) AS tbl_size
UNION ALL
SELECT 'vacuum', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id')),
       pg_relation_size('perf_vacuum'), pg_size_pretty(pg_relation_size('perf_vacuum'))
UNION ALL
SELECT 'reindex', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id')),
       pg_relation_size('perf_reindex'), pg_size_pretty(pg_relation_size('perf_reindex'));

SELECT 'shrink' AS method, count(*) FROM perf_shrink
UNION ALL SELECT 'vacuum', count(*) FROM perf_vacuum
UNION ALL SELECT 'reindex', count(*) FROM perf_reindex;

-- =========================================================================
-- SCENARIO 4 EXTRA: Query performance post-compaction
-- =========================================================================
\echo ''
\echo '=== Query Performance Post-Compaction ==='
SET enable_seqscan = off;

\echo '--- Index scan: shrink table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_shrink WHERE id = 25000;
\echo '--- Index scan: vacuum table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_vacuum WHERE id = 25000;
\echo '--- Index scan: reindex table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_reindex WHERE id = 25000;

\echo '--- Range scan: shrink table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT count(*) FROM perf_shrink WHERE id BETWEEN 1000 AND 10000;
\echo '--- Range scan: vacuum table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT count(*) FROM perf_vacuum WHERE id BETWEEN 1000 AND 10000;
\echo '--- Range scan: reindex table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT count(*) FROM perf_reindex WHERE id BETWEEN 1000 AND 10000;

\echo '--- Backward scan (ORDER BY id DESC LIMIT 100): shrink table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_shrink ORDER BY id DESC LIMIT 100;
\echo '--- Backward scan: vacuum table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_vacuum ORDER BY id DESC LIMIT 100;
\echo '--- Backward scan: reindex table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_reindex ORDER BY id DESC LIMIT 100;

\echo '--- Index-only scan: shrink table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT id FROM perf_shrink WHERE id BETWEEN 1000 AND 10000;
\echo '--- Index-only scan: vacuum table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT id FROM perf_vacuum WHERE id BETWEEN 1000 AND 10000;
\echo '--- Index-only scan: reindex table ---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT id FROM perf_reindex WHERE id BETWEEN 1000 AND 10000;

RESET enable_seqscan;

DROP TABLE perf_shrink CASCADE;
DROP TABLE perf_vacuum CASCADE;
DROP TABLE perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 5: 200K rows, FIFO Head / Prefix Deletion (Oldest 80%)
-- Tests page relocation from tail to head, downlink repairs, and multi-index
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 5: 200K rows, FIFO Head Deletion (Oldest 80%, Page Relocation)'
\echo '======================================================================'

CREATE TABLE perf_shrink (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_shrink_id ON perf_shrink USING ubtree (id);
CREATE INDEX idx_perf_shrink_comp ON perf_shrink USING ubtree (category, id);
CREATE INDEX idx_perf_shrink_text ON perf_shrink USING ubtree (payload);

CREATE TABLE perf_vacuum (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_vacuum_id ON perf_vacuum USING ubtree (id);
CREATE INDEX idx_perf_vacuum_comp ON perf_vacuum USING ubtree (category, id);
CREATE INDEX idx_perf_vacuum_text ON perf_vacuum USING ubtree (payload);

CREATE TABLE perf_reindex (
    id int,
    payload text,
    category int,
    ts timestamp DEFAULT now()
) WITH (storage_type=ustore);
CREATE INDEX idx_perf_reindex_id ON perf_reindex USING ubtree (id);
CREATE INDEX idx_perf_reindex_comp ON perf_reindex USING ubtree (category, id);
CREATE INDEX idx_perf_reindex_text ON perf_reindex USING ubtree (payload);

INSERT INTO perf_shrink
SELECT g, 'payload_prefix_' || g || '_' || repeat('z', 40), g % 500, now() - (g || ' seconds')::interval
FROM generate_series(1, 200000) g;

INSERT INTO perf_vacuum
SELECT g, 'payload_prefix_' || g || '_' || repeat('z', 40), g % 500, now() - (g || ' seconds')::interval
FROM generate_series(1, 200000) g;

INSERT INTO perf_reindex
SELECT g, 'payload_prefix_' || g || '_' || repeat('z', 40), g % 500, now() - (g || ' seconds')::interval
FROM generate_series(1, 200000) g;

\echo '--- Initial Sizes (200K rows, Multi-Index) ---'
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL SELECT 'shrink_comp', pg_relation_size('idx_perf_shrink_comp'), pg_size_pretty(pg_relation_size('idx_perf_shrink_comp'))
UNION ALL SELECT 'shrink_text', pg_relation_size('idx_perf_shrink_text'), pg_size_pretty(pg_relation_size('idx_perf_shrink_text'));

-- FIFO Deletion: Delete oldest 80% (Prefix / Leftmost leaf pages become empty)
DELETE FROM perf_shrink WHERE id <= 160000;
DELETE FROM perf_vacuum WHERE id <= 160000;
DELETE FROM perf_reindex WHERE id <= 160000;

SELECT pg_sleep(2);
SELECT txid_current();
VACUUM perf_shrink;
VACUUM perf_vacuum;
VACUUM perf_reindex;

\echo '--- Post-Delete Sizes (Head Deletion 80%) ---'
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL SELECT 'shrink_comp', pg_relation_size('idx_perf_shrink_comp'), pg_size_pretty(pg_relation_size('idx_perf_shrink_comp'))
UNION ALL SELECT 'shrink_text', pg_relation_size('idx_perf_shrink_text'), pg_size_pretty(pg_relation_size('idx_perf_shrink_text'));

SELECT gs_ubtree_shrink_check('idx_perf_shrink_id');
SELECT gs_ubtree_shrink_check('idx_perf_shrink_comp');
SELECT gs_ubtree_shrink_check('idx_perf_shrink_text');

\echo ''
\echo '>>> gs_ubtree_shrink on Head Deletion Indexes <<<'
SELECT gs_ubtree_shrink('idx_perf_shrink_id', false);
SELECT gs_ubtree_shrink('idx_perf_shrink_comp', false);
SELECT gs_ubtree_shrink('idx_perf_shrink_text', false);

\echo ''
\echo '>>> VACUUM FULL on Head Deletion Table <<<'
VACUUM FULL perf_vacuum;

\echo ''
\echo '>>> REINDEX on Head Deletion Indexes <<<'
REINDEX INDEX idx_perf_reindex_id;
REINDEX INDEX idx_perf_reindex_comp;
REINDEX INDEX idx_perf_reindex_text;

\echo ''
\echo '=== SCENARIO 5 RESULTS: Post-Compaction Sizes (Head Deletion) ==='
SELECT 'shrink_id' AS idx, pg_relation_size('idx_perf_shrink_id') AS bytes, pg_size_pretty(pg_relation_size('idx_perf_shrink_id')) AS size
UNION ALL SELECT 'shrink_comp', pg_relation_size('idx_perf_shrink_comp'), pg_size_pretty(pg_relation_size('idx_perf_shrink_comp'))
UNION ALL SELECT 'shrink_text', pg_relation_size('idx_perf_shrink_text'), pg_size_pretty(pg_relation_size('idx_perf_shrink_text'))
UNION ALL SELECT 'vacuum_id', pg_relation_size('idx_perf_vacuum_id'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_id'))
UNION ALL SELECT 'vacuum_comp', pg_relation_size('idx_perf_vacuum_comp'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_comp'))
UNION ALL SELECT 'vacuum_text', pg_relation_size('idx_perf_vacuum_text'), pg_size_pretty(pg_relation_size('idx_perf_vacuum_text'))
UNION ALL SELECT 'reindex_id', pg_relation_size('idx_perf_reindex_id'), pg_size_pretty(pg_relation_size('idx_perf_reindex_id'))
UNION ALL SELECT 'reindex_comp', pg_relation_size('idx_perf_reindex_comp'), pg_size_pretty(pg_relation_size('idx_perf_reindex_comp'))
UNION ALL SELECT 'reindex_text', pg_relation_size('idx_perf_reindex_text'), pg_size_pretty(pg_relation_size('idx_perf_reindex_text'));

-- Data integrity check and backward scan test
SELECT 'shrink' AS method, count(*) FROM perf_shrink
UNION ALL SELECT 'vacuum', count(*) FROM perf_vacuum
UNION ALL SELECT 'reindex', count(*) FROM perf_reindex;

SET enable_seqscan = off;
EXPLAIN (ANALYZE, COSTS OFF, TIMING ON) SELECT * FROM perf_shrink ORDER BY id DESC LIMIT 50;
RESET enable_seqscan;

DROP TABLE perf_shrink CASCADE;
DROP TABLE perf_vacuum CASCADE;
DROP TABLE perf_reindex CASCADE;

-- =========================================================================
-- SCENARIO 6: Dynamic Multi-Cycle Aging (Insert -> Delete -> Shrink 3 Rounds)
-- Tests space stabilization and fragmentation containment over time
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 6: Multi-Cycle Lifecycle (3 Rounds of Insert -> Delete -> Shrink)'
\echo '======================================================================'

CREATE TABLE perf_cycle_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_cycle_shrink_id ON perf_cycle_shrink USING ubtree (id);

CREATE TABLE perf_cycle_noshrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_cycle_noshrink_id ON perf_cycle_noshrink USING ubtree (id);

-- === Round 1: Insert 50K -> Delete oldest 30K ===
\echo '--- Round 1: Insert 1..50000, Delete 1..30000 ---'
INSERT INTO perf_cycle_shrink SELECT g, 'cycle_data_' || g FROM generate_series(1, 50000) g;
INSERT INTO perf_cycle_noshrink SELECT g, 'cycle_data_' || g FROM generate_series(1, 50000) g;

DELETE FROM perf_cycle_shrink WHERE id <= 30000;
DELETE FROM perf_cycle_noshrink WHERE id <= 30000;

SELECT pg_sleep(1);
SELECT txid_current();
VACUUM perf_cycle_shrink;
VACUUM perf_cycle_noshrink;

SELECT gs_ubtree_shrink('idx_cycle_shrink_id', false);

\echo '--- Round 1 Sizes ---'
SELECT 'cycle_shrink (R1)' AS target, pg_size_pretty(pg_relation_size('idx_cycle_shrink_id')) AS idx_size,
       pg_size_pretty(pg_relation_size('perf_cycle_shrink')) AS tbl_size
UNION ALL
SELECT 'cycle_noshrink (R1)', pg_size_pretty(pg_relation_size('idx_cycle_noshrink_id')),
       pg_size_pretty(pg_relation_size('perf_cycle_noshrink'));

-- === Round 2: Insert 50K (50001..100000) -> Delete oldest 30K (30001..60000) ===
\echo '--- Round 2: Insert 50001..100000, Delete 30001..60000 ---'
INSERT INTO perf_cycle_shrink SELECT g, 'cycle_data_' || g FROM generate_series(50001, 100000) g;
INSERT INTO perf_cycle_noshrink SELECT g, 'cycle_data_' || g FROM generate_series(50001, 100000) g;

DELETE FROM perf_cycle_shrink WHERE id <= 60000;
DELETE FROM perf_cycle_noshrink WHERE id <= 60000;

SELECT pg_sleep(1);
SELECT txid_current();
VACUUM perf_cycle_shrink;
VACUUM perf_cycle_noshrink;

SELECT gs_ubtree_shrink('idx_cycle_shrink_id', false);

\echo '--- Round 2 Sizes ---'
SELECT 'cycle_shrink (R2)' AS target, pg_size_pretty(pg_relation_size('idx_cycle_shrink_id')) AS idx_size,
       pg_size_pretty(pg_relation_size('perf_cycle_shrink')) AS tbl_size
UNION ALL
SELECT 'cycle_noshrink (R2)', pg_size_pretty(pg_relation_size('idx_cycle_noshrink_id')),
       pg_size_pretty(pg_relation_size('perf_cycle_noshrink'));

-- === Round 3: Insert 50K (100001..150000) -> Delete oldest 30K (60001..90000) ===
\echo '--- Round 3: Insert 100001..150000, Delete 60001..90000 ---'
INSERT INTO perf_cycle_shrink SELECT g, 'cycle_data_' || g FROM generate_series(100001, 150000) g;
INSERT INTO perf_cycle_noshrink SELECT g, 'cycle_data_' || g FROM generate_series(100001, 150000) g;

DELETE FROM perf_cycle_shrink WHERE id <= 90000;
DELETE FROM perf_cycle_noshrink WHERE id <= 90000;

SELECT pg_sleep(1);
SELECT txid_current();
VACUUM perf_cycle_shrink;
VACUUM perf_cycle_noshrink;

SELECT gs_ubtree_shrink('idx_cycle_shrink_id', false);

\echo ''
\echo '=== SCENARIO 6 FINAL RESULTS: Multi-Cycle Comparison ==='
SELECT 'cycle_shrink (Final)' AS target, 
       pg_relation_size('idx_cycle_shrink_id') AS idx_bytes, pg_size_pretty(pg_relation_size('idx_cycle_shrink_id')) AS idx_size,
       (SELECT count(*) FROM perf_cycle_shrink) AS remaining_rows
UNION ALL
SELECT 'cycle_noshrink (Final)', 
       pg_relation_size('idx_cycle_noshrink_id'), pg_size_pretty(pg_relation_size('idx_cycle_noshrink_id')),
       (SELECT count(*) FROM perf_cycle_noshrink);

DROP TABLE perf_cycle_shrink CASCADE;
DROP TABLE perf_cycle_noshrink CASCADE;

-- =========================================================================
-- SCENARIO 7: Online (false) vs Offline (true) Shrink Mode Comparison
-- Tests execution speed and compaction parity under Middle Interval Cavity
-- =========================================================================
\echo ''
\echo '======================================================================'
\echo 'SCENARIO 7: Online vs Offline Shrink (Middle Interval Cavity 70%)'
\echo '======================================================================'

CREATE TABLE perf_online_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_online_shrink_id ON perf_online_shrink USING ubtree (id);

CREATE TABLE perf_offline_shrink (
    id int,
    payload text
) WITH (storage_type=ustore);
CREATE INDEX idx_offline_shrink_id ON perf_offline_shrink USING ubtree (id);

INSERT INTO perf_online_shrink SELECT g, 'data_cavity_' || g FROM generate_series(1, 100000) g;
INSERT INTO perf_offline_shrink SELECT g, 'data_cavity_' || g FROM generate_series(1, 100000) g;

-- Delete middle interval 70% (15001 to 85000)
DELETE FROM perf_online_shrink WHERE id BETWEEN 15001 AND 85000;
DELETE FROM perf_offline_shrink WHERE id BETWEEN 15001 AND 85000;

SELECT pg_sleep(1);
SELECT txid_current();
VACUUM perf_online_shrink;
VACUUM perf_offline_shrink;

\echo '--- Pre-Shrink Sizes (Middle 70% deleted) ---'
SELECT 'online' AS mode, pg_size_pretty(pg_relation_size('idx_online_shrink_id')) AS idx_size
UNION ALL
SELECT 'offline', pg_size_pretty(pg_relation_size('idx_offline_shrink_id'));

\echo '--- Timing START: Online Shrink (is_offline = false) ---'
SELECT gs_ubtree_shrink('idx_online_shrink_id', false);
\echo '--- Timing END: Online Shrink ---'

\echo '--- Timing START: Offline Shrink (is_offline = true) ---'
SELECT gs_ubtree_shrink('idx_offline_shrink_id', true);
\echo '--- Timing END: Offline Shrink ---'

\echo ''
\echo '=== SCENARIO 7 RESULTS: Online vs Offline Comparison ==='
SELECT 'online (false)' AS mode, 
       pg_relation_size('idx_online_shrink_id') AS idx_bytes, 
       pg_size_pretty(pg_relation_size('idx_online_shrink_id')) AS idx_size,
       (SELECT count(*) FROM perf_online_shrink) AS rows_intact
UNION ALL
SELECT 'offline (true)', 
       pg_relation_size('idx_offline_shrink_id'), 
       pg_size_pretty(pg_relation_size('idx_offline_shrink_id')),
       (SELECT count(*) FROM perf_offline_shrink);

DROP TABLE perf_online_shrink CASCADE;
DROP TABLE perf_offline_shrink CASCADE;

\echo ''
\echo '======================================================================'
\echo 'ALL SCENARIOS COMPLETE'
\echo '======================================================================'


