--
-- pgstat_opt_concurrent_reset
--

setup
{
  DROP TABLE IF EXISTS t_pgstat_iso;
  CREATE TABLE t_pgstat_iso(id int primary key, val int);
  DROP FUNCTION IF EXISTS f_pgstat_iso(int);
  CREATE OR REPLACE FUNCTION f_pgstat_iso(i int) RETURNS int AS $$
  BEGIN
    RETURN i + 1;
  END;
  $$ LANGUAGE plpgsql;
}

teardown
{
  DROP TABLE t_pgstat_iso;
  DROP FUNCTION f_pgstat_iso(int);
}

session "s1"
setup { BEGIN; SET track_counts = on; }
step "s1i" { INSERT INTO t_pgstat_iso VALUES (1,1); }
step "s1c" { COMMIT; }

session "s2"
setup { BEGIN; SET track_counts = on; }
step "s2i" { INSERT INTO t_pgstat_iso VALUES (2,2); }
step "s2c" { COMMIT; }

session "s3"
setup { SET track_counts = on; SET track_functions = all; }
step "s3call" { DO $$ BEGIN PERFORM f_pgstat_iso(1); END $$; }
step "s3resetdb" { DO $$ BEGIN PERFORM pg_stat_reset(); END $$; }
step "s3resettab" { DO $$ BEGIN PERFORM pg_stat_reset_single_table_counters('t_pgstat_iso'::regclass); END $$; }
step "s3resetfunc" { DO $$ BEGIN PERFORM pg_stat_reset_single_function_counters('f_pgstat_iso(int)'::regprocedure); END $$; }
step "s3assert" {
  DO $$
  DECLARE
    v_rows int;
    v_tab_ins bigint;
    v_func_calls bigint;
  BEGIN
    SELECT count(*) INTO v_rows FROM t_pgstat_iso;
    IF v_rows <> 2 THEN
      RAISE EXCEPTION 'unexpected row count in t_pgstat_iso: %, expected 2', v_rows;
    END IF;

    SELECT COALESCE((SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='t_pgstat_iso'), 0)
      INTO v_tab_ins;
    IF v_tab_ins < 0 THEN
      RAISE EXCEPTION 'unexpected negative n_tup_ins: %', v_tab_ins;
    END IF;

    SELECT COALESCE((SELECT calls FROM pg_stat_user_functions WHERE funcname='f_pgstat_iso'), 0)
      INTO v_func_calls;
    IF v_func_calls < 0 THEN
      RAISE EXCEPTION 'unexpected negative function calls: %', v_func_calls;
    END IF;
  END;
  $$;
}

permutation "s1i" "s2i" "s3call" "s3resetdb" "s3resettab" "s3resetfunc" "s1c" "s2c" "s3assert"
