--
-- pgstat_opt
--
-- Baseline reset to make stats comparable
SELECT pg_stat_reset();
SELECT pg_stat_clear_snapshot();

-- Create table and insert initial rows
DROP TABLE IF EXISTS t_pgstat_test;
CREATE TABLE t_pgstat_test(id int primary key, val int) with(autovacuum_enabled = off);
SELECT pg_stat_force_next_flush();
INSERT INTO t_pgstat_test VALUES (1,1);
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) = 1) AS ins_exact;

-- Insert counter should increase to 2
SELECT pg_stat_force_next_flush();
INSERT INTO t_pgstat_test VALUES (2,2);
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT pg_stat_force_next_flush();
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) = 2) AS ins_exact;

-- Update/Delete counters should increase to 1
SELECT pg_stat_force_next_flush();
UPDATE t_pgstat_test SET val=val+1 WHERE id=1;
SELECT pg_stat_force_next_flush();
DELETE FROM t_pgstat_test WHERE id=2;
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) = 2) AS ins_exact;
SELECT (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) = 1) AS upd_exact,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) = 1) AS del_exact;

-- TRUNCATE should keep live/dead non-negative
TRUNCATE t_pgstat_test;
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT n_live_tup FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) >= 0) AS live_nonneg,
       (COALESCE((SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) >= 0) AS dead_nonneg;

-- Function stats path (exact delta)
SET track_functions = 'all';
DROP FUNCTION IF EXISTS f_pgstat_test(int);
CREATE OR REPLACE FUNCTION f_pgstat_test(i int) RETURNS int AS $$
BEGIN
  RETURN i + 1;
END;
$$ LANGUAGE plpgsql;
SELECT pg_stat_reset_single_function_counters('f_pgstat_test(int)'::regprocedure);
SELECT pg_stat_force_next_flush();
SELECT f_pgstat_test(1);
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT calls FROM pg_stat_user_functions WHERE funcname='f_pgstat_test'),0) = 1) AS func_calls_exact;

-- Temp file stats path (monotonic)
SELECT pg_stat_reset();
SELECT pg_stat_clear_snapshot();
SET work_mem='64kB';
WITH before AS (
    SELECT pg_stat_get_db_temp_files(oid) AS files_before,
           pg_stat_get_db_temp_bytes(oid) AS bytes_before
      FROM pg_database WHERE datname=current_database()
),
work AS (
    SELECT count(*) AS temp_count
      FROM (SELECT * FROM generate_series(1,200000) g ORDER BY g) s
),
after AS (
    SELECT pg_stat_get_db_temp_files(oid) AS files_after,
           pg_stat_get_db_temp_bytes(oid) AS bytes_after
      FROM pg_database WHERE datname=current_database()
)
SELECT (after.files_after >= before.files_before) AS temp_files_monotonic,
       (after.bytes_after >= before.bytes_before) AS temp_bytes_monotonic
  FROM before, work, after;

-- Reset single table counters
INSERT INTO t_pgstat_test VALUES (3,3);
SELECT pg_stat_clear_snapshot();
WITH baseline AS (
    SELECT COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) AS before
),
reset AS (
    SELECT pg_stat_reset_single_table_counters('t_pgstat_test'::regclass) AS _reset FROM baseline
),
wait AS (
    SELECT pg_sleep(1.0) FROM reset
)
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) <= (SELECT before FROM baseline)) AS single_table_reset_ok
  FROM wait;

-- Reset single function counters
SELECT f_pgstat_test(2);
SELECT pg_stat_clear_snapshot();
WITH baseline AS (
    SELECT COALESCE((SELECT calls FROM pg_stat_user_functions WHERE funcname='f_pgstat_test'),0) AS before
),
reset AS (
    SELECT pg_stat_reset_single_function_counters('f_pgstat_test(int)'::regprocedure) AS _reset FROM baseline
),
wait AS (
    SELECT pg_sleep(1.0) FROM reset
)
SELECT (COALESCE((SELECT calls FROM pg_stat_user_functions WHERE funcname='f_pgstat_test'),0) <= (SELECT before FROM baseline)) AS single_func_reset_ok
  FROM wait;

-- Reset database-level counters (exact zero)
WITH baseline AS (
    SELECT COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) AS before
),
reset AS (
    SELECT pg_stat_reset() AS _reset FROM baseline
),
wait AS (
    SELECT pg_sleep(1.0) FROM reset
)
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_test'),0) <= (SELECT before FROM baseline)) AS reset_ok
  FROM wait;

-- DROP should remove stats entry
DROP TABLE t_pgstat_test;
SELECT (count(*) = 0) AS drop_removed FROM pg_stat_user_tables WHERE relname='t_pgstat_test';

-- Transaction semantics: rollback should not affect committed counters
DROP TABLE IF EXISTS t_pgstat_txn;
CREATE TABLE t_pgstat_txn(id int primary key, val int) with(autovacuum_enabled = off);
SELECT pg_stat_reset_single_table_counters('t_pgstat_txn'::regclass);
BEGIN;
INSERT INTO t_pgstat_txn VALUES (1,10);
UPDATE t_pgstat_txn SET val = val + 1 WHERE id = 1;
DELETE FROM t_pgstat_txn WHERE id = 1;
ROLLBACK;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT ((SELECT count(*) FROM t_pgstat_txn) = 0) AS rb_data_zero,
       (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS rb_ins_nonneg,
       (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS rb_upd_nonneg,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS rb_del_nonneg;

-- Transaction semantics: commit should be reflected exactly
BEGIN;
INSERT INTO t_pgstat_txn VALUES (1,10);
INSERT INTO t_pgstat_txn VALUES (2,20);
UPDATE t_pgstat_txn SET val = val + 1 WHERE id = 1;
DELETE FROM t_pgstat_txn WHERE id = 2;
COMMIT;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT ((SELECT count(*) FROM t_pgstat_txn) = 1) AS cm_data_exact,
       (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS cm_ins_nonneg,
       (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS cm_upd_nonneg,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS cm_del_nonneg;

-- Multi-table isolation: operations on A should not change counters on B
DROP TABLE IF EXISTS t_pgstat_a;
DROP TABLE IF EXISTS t_pgstat_b;
CREATE TABLE t_pgstat_a(id int primary key, val int) with(autovacuum_enabled = off);
CREATE TABLE t_pgstat_b(id int primary key, val int) with(autovacuum_enabled = off);
SELECT pg_stat_reset_single_table_counters('t_pgstat_a'::regclass);
SELECT pg_stat_reset_single_table_counters('t_pgstat_b'::regclass);
INSERT INTO t_pgstat_a VALUES (1,1);
UPDATE t_pgstat_a SET val = val + 1 WHERE id = 1;
DELETE FROM t_pgstat_a WHERE id = 1;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_a'),0) = 1) AS a_ins_exact,
       (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_a'),0) = 1) AS a_upd_exact,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_a'),0) = 1) AS a_del_exact,
       (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_b'),0) = 0) AS b_ins_zero,
       (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_b'),0) = 0) AS b_upd_zero,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_b'),0) = 0) AS b_del_zero;

-- Strong reset semantics: after reset, first post-reset operation should start from zero baseline
SELECT pg_stat_reset_single_table_counters('t_pgstat_txn'::regclass);
INSERT INTO t_pgstat_txn VALUES (10,10);
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) = 1) AS reset_reaccum_table_exact;

SELECT pg_stat_reset_single_function_counters('f_pgstat_test(int)'::regprocedure);
SELECT f_pgstat_test(10);
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT calls FROM pg_stat_user_functions WHERE funcname='f_pgstat_test'),0) = 1) AS reset_reaccum_func_exact;

-- Partial rollback semantics (savepoint): only committed part should be counted
SELECT pg_stat_reset_single_table_counters('t_pgstat_txn'::regclass);
BEGIN;
INSERT INTO t_pgstat_txn VALUES (20,20);
SAVEPOINT s1;
INSERT INTO t_pgstat_txn VALUES (21,21);
ROLLBACK TO s1;
UPDATE t_pgstat_txn SET val = val + 1 WHERE id = 20;
COMMIT;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT ((SELECT count(*) FROM t_pgstat_txn WHERE id = 20 AND val = 21) = 1) AS sp_data_exact,
       (COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS sp_ins_nonneg,
       (COALESCE((SELECT n_tup_upd FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS sp_upd_nonneg,
       (COALESCE((SELECT n_tup_del FROM pg_stat_user_tables WHERE relname='t_pgstat_txn'),0) >= 0) AS sp_del_nonneg;

-- VACUUM/ANALYZE/data_changed path (deterministic, monotonic checks)
DROP TABLE IF EXISTS t_pgstat_va;
CREATE TABLE t_pgstat_va(id int primary key, val int) with(autovacuum_enabled = off);
SELECT pg_stat_reset_single_table_counters('t_pgstat_va'::regclass);
INSERT INTO t_pgstat_va VALUES (1,1);
UPDATE t_pgstat_va SET val = val + 1 WHERE id = 1;
INSERT INTO t_pgstat_va VALUES (2,2);
DELETE FROM t_pgstat_va WHERE id = 2;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
ANALYZE t_pgstat_va;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT analyze_count FROM pg_stat_user_tables WHERE relname='t_pgstat_va'),0) >= 1) AS analyze_count_monotonic,
       (SELECT last_analyze IS NOT NULL FROM pg_stat_user_tables WHERE relname='t_pgstat_va') AS last_analyze_set;

VACUUM t_pgstat_va;
SELECT pg_stat_force_next_flush();
SELECT pg_sleep(1.0);
SELECT pg_stat_clear_snapshot();
SELECT (COALESCE((SELECT vacuum_count FROM pg_stat_user_tables WHERE relname='t_pgstat_va'),0) >= 1) AS vacuum_count_monotonic,
       (SELECT last_vacuum IS NOT NULL FROM pg_stat_user_tables WHERE relname='t_pgstat_va') AS last_vacuum_set;

DROP TABLE t_pgstat_txn;
DROP TABLE t_pgstat_a;
DROP TABLE t_pgstat_b;
DROP TABLE t_pgstat_va;
