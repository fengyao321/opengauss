-- ============================================================================
-- openGauss Ustore Bridge Index Phase 1 (Hash & GiST) Automated Test Suite
-- Target Feature: Ustore Bridge Index (Phase 1 MVP)
-- Reference: bridgeindex/phase1_test_specification.md
-- ============================================================================

\echo '>>> [START] Ustore Bridge Index Phase 1 Test Suite Running...'
SET client_min_messages = WARNING;

-- ----------------------------------------------------------------------------
-- Section 1: DDL & Metadata Verification (TC-01, TC-02, TC-03)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-01] Testing CREATE TABLE (ustore) + Hash Index and Companion Table...'
DROP TABLE IF EXISTS t_bridge_ddl_test CASCADE;
CREATE TABLE t_bridge_ddl_test (
    id INT,
    user_name VARCHAR(64),
    score NUMERIC
) WITH (storage_type = ustore);

CREATE INDEX idx_b_hash ON t_bridge_ddl_test USING hash(user_name);

-- Check companion table and UBTree indexes in pg_class (mask dynamic OID for regression testing)
SELECT regexp_replace(c.relname, 'pg_bridge_[0-9]+', 'pg_bridge_<oid>') AS relname, c.relkind, am.amname
FROM pg_class c
LEFT JOIN pg_am am ON c.relam = am.oid
WHERE c.relname LIKE 'pg_bridge_' || (SELECT oid FROM pg_class WHERE relname = 't_bridge_ddl_test') || '%'
ORDER BY 1;

\echo '>>> [TC-02] Testing CREATE TABLE (ustore) + GiST Spatial Index...'
DROP TABLE IF EXISTS t_bridge_gist_test CASCADE;
CREATE TABLE t_bridge_gist_test (
    id INT,
    geo_point POINT
) WITH (storage_type = ustore);

CREATE INDEX idx_b_gist ON t_bridge_gist_test USING gist(geo_point);
\d+ t_bridge_gist_test

\echo '>>> [TC-03] Testing Invalid AM Defense (USING btree on ustore)...'
-- Should raise error: btree index is not supported for ustore, please use ubtree instead
CREATE INDEX idx_fail_btree ON t_bridge_ddl_test USING btree(id);

-- ----------------------------------------------------------------------------
-- Section 2: DML Insert and Hash IndexScan Point Query (TC-04)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-04] Testing Hash IndexScan Point Query & Two-Phase Dereference...'
DROP TABLE IF EXISTS t_hash_scan CASCADE;
CREATE TABLE t_hash_scan (
    id INT,
    code TEXT,
    info VARCHAR(100)
) WITH (storage_type = ustore);

CREATE INDEX idx_hs_code ON t_hash_scan USING hash(code);

INSERT INTO t_hash_scan VALUES (1, 'ALPHA', 'first record');
INSERT INTO t_hash_scan VALUES (2, 'BETA',  'second record');
INSERT INTO t_hash_scan VALUES (3, 'GAMMA', 'third record');
INSERT INTO t_hash_scan VALUES (4, 'DELTA', 'fourth record');

SET enable_seqscan = off;
SET enable_indexscan = on;

-- Verify query plan
EXPLAIN (COSTS OFF) SELECT * FROM t_hash_scan WHERE code = 'BETA';

-- Verify execution results
SELECT * FROM t_hash_scan WHERE code = 'BETA';
SELECT * FROM t_hash_scan WHERE code = 'DELTA';
SELECT * FROM t_hash_scan WHERE code = 'NON_EXISTENT';

-- ----------------------------------------------------------------------------
-- Section 3: GiST Spatial Range Query (TC-05)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-05] Testing GiST Spatial Query & Bounding Box Inclusion...'
DROP TABLE IF EXISTS t_gist_scan CASCADE;
CREATE TABLE t_gist_scan (
    id INT,
    city VARCHAR(50),
    location POINT
) WITH (storage_type = ustore);

CREATE INDEX idx_gs_loc ON t_gist_scan USING gist(location);

INSERT INTO t_gist_scan VALUES (101, 'Beijing',  point(116.40, 39.90));
INSERT INTO t_gist_scan VALUES (102, 'Shanghai', point(121.47, 31.23));
INSERT INTO t_gist_scan VALUES (103, 'Chengdu',  point(104.06, 30.67));
INSERT INTO t_gist_scan VALUES (104, 'Tokyo',    point(139.69, 35.68));

EXPLAIN (COSTS OFF) 
SELECT id, city FROM t_gist_scan 
WHERE location <@ box(point(100.0, 20.0), point(125.0, 45.0));

SELECT id, city FROM t_gist_scan 
WHERE location <@ box(point(100.0, 20.0), point(125.0, 45.0))
ORDER BY id;

-- ----------------------------------------------------------------------------
-- Section 4: MVCC & In-Place Update (TC-06, TC-07)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-06] Testing In-Place Update on Non-Indexed Attribute...'
UPDATE t_hash_scan SET info = 'beta updated in place' WHERE code = 'BETA';
SELECT * FROM t_hash_scan WHERE code = 'BETA';

\echo '>>> [TC-07] Testing Update on Indexed Column (Key Change)...'
UPDATE t_hash_scan SET code = 'OMEGA' WHERE id = 3;

-- Old key should return 0 rows
SELECT * FROM t_hash_scan WHERE code = 'GAMMA';
-- New key should return the row
SELECT * FROM t_hash_scan WHERE code = 'OMEGA';

-- ----------------------------------------------------------------------------
-- Section 5: Transaction Abort & Rollback (TC-08, TC-09)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-08] Testing INSERT Rollback (Zero Dirty Reads)...'
BEGIN;
INSERT INTO t_hash_scan VALUES (999, 'PHANTOM', 'uncommitted test');
SELECT * FROM t_hash_scan WHERE code = 'PHANTOM';
ROLLBACK;

-- Must return 0 rows
SELECT * FROM t_hash_scan WHERE code = 'PHANTOM';

\echo '>>> [TC-09] Testing DELETE Rollback...'
BEGIN;
DELETE FROM t_hash_scan WHERE code = 'ALPHA';
SELECT * FROM t_hash_scan WHERE code = 'ALPHA';
ROLLBACK;

-- Must return original row
SELECT * FROM t_hash_scan WHERE code = 'ALPHA';

-- ----------------------------------------------------------------------------
-- Section 6: Anti-Phantom Row on Physical Slot Reuse (TC-10)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-10] Testing Slot Reuse Anti-Phantom Verification...'
DROP TABLE IF EXISTS t_slot_reuse CASCADE;
CREATE TABLE t_slot_reuse (
    id INT,
    token TEXT,
    payload CHAR(100)
) WITH (storage_type = ustore);

CREATE INDEX idx_sr_token ON t_slot_reuse USING hash(token);

INSERT INTO t_slot_reuse VALUES (1, 'KEY_AAA', 'payload_1');
DELETE FROM t_slot_reuse WHERE token = 'KEY_AAA';

-- Prune page slot
VACUUM t_slot_reuse;

-- Insert unrelated record into the freed slot
INSERT INTO t_slot_reuse VALUES (2, 'KEY_BBB', 'payload_2');

-- Old key query MUST return 0 rows
SELECT * FROM t_slot_reuse WHERE token = 'KEY_AAA';

-- New key query MUST return 1 row
SELECT * FROM t_slot_reuse WHERE token = 'KEY_BBB';

-- ----------------------------------------------------------------------------
-- Section 7: NULL Values & Boundary Verification (TC-11)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-11] Testing NULL Value Handling...'
INSERT INTO t_hash_scan VALUES (5, NULL, 'null token test');
SELECT * FROM t_hash_scan WHERE code IS NULL;

-- ----------------------------------------------------------------------------
-- Section 8: Cascade Drop Cleanup (TC-12)
-- ----------------------------------------------------------------------------
\echo '>>> [TC-12] Testing DROP TABLE CASCADE and Companion Clean up...'
DROP TABLE t_bridge_ddl_test CASCADE;
DROP TABLE t_bridge_gist_test CASCADE;
DROP TABLE t_hash_scan CASCADE;
DROP TABLE t_gist_scan CASCADE;
DROP TABLE t_slot_reuse CASCADE;

\echo '>>> [COMPLETE] All Bridge Index Phase 1 Test Cases Executed.'
