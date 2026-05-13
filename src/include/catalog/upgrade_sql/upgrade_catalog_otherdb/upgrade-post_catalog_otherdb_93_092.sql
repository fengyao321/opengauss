DROP FUNCTION IF EXISTS pg_catalog.pg_stat_get_session_wlmstat(INT4) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3502;
CREATE FUNCTION pg_catalog.pg_stat_get_session_wlmstat(
    IN pid INT4,
    OUT datid OID,
    OUT threadid INT8,
    OUT sessionid INT8,
    OUT threadpid INT4,
    OUT usesysid OID,
    OUT appname TEXT,
    OUT query TEXT,
    OUT priority INT8,
    OUT block_time INT8,
    OUT elapsed_time INT8,
    OUT total_cpu_time INT8,
    OUT skew_percent INT4,
    OUT statement_mem INT4,
    OUT active_points INT4,
    OUT dop_value INT4,
    OUT current_cgroup TEXT,
    OUT current_status TEXT,
    OUT enqueue_state TEXT,
    OUT attribute TEXT,
    OUT is_plana BOOL,
    OUT node_group TEXT,
    OUT srespool NAME,
    OUT rowdesc_a_store_count INT8,
    OUT rowdesc_a_hit_count INT8,
    OUT rowdesc_b_store_count INT8,
    OUT rowdesc_b_hit_count INT8)
RETURNS SETOF record
LANGUAGE INTERNAL
STABLE
ROWS 100
AS 'pg_stat_get_session_wlmstat';

CREATE OR REPLACE VIEW pg_catalog.pg_session_wlmstat AS
    SELECT
            S.datid AS datid,
            D.datname AS datname,
            S.threadid,
            S.sessionid,
            S.threadpid AS processid,
            S.usesysid,
            S.appname,
            U.rolname AS usename,
            S.priority,
            S.attribute,
            S.block_time,
            S.elapsed_time,
            S.total_cpu_time,
            S.skew_percent AS cpu_skew_percent,
            S.statement_mem,
            S.active_points,
            S.dop_value,
            S.current_cgroup AS control_group,
            S.current_status AS status,
            S.enqueue_state AS enqueue,
            CASE
                WHEN T.session_respool = 'unknown' THEN (U.rolrespool) :: name
                ELSE T.session_respool
            END AS resource_pool,
            S.query,
            S.is_plana,
            S.node_group,
            S.rowdesc_a_store_count,
            S.rowdesc_a_hit_count,
            S.rowdesc_b_store_count,
            S.rowdesc_b_hit_count
    FROM pg_catalog.pg_database D, pg_catalog.pg_stat_get_session_wlmstat(NULL) AS S, pg_authid AS U,
        pg_catalog.gs_wlm_session_respool(0) AS T
    WHERE S.datid = D.oid AND
          S.usesysid = U.oid AND
          T.sessionid = S.sessionid;

CREATE OR REPLACE VIEW pg_catalog.gs_wlm_workload_records AS
    SELECT
            P.node_name,
            S.threadid AS thread_id,
            S.threadpid AS processid,
            P.start_time AS time_stamp,
            U.rolname AS username,
            P.memory,
            P.actpts AS active_points,
            P.maxpts AS max_points,
            P.priority,
            P.resource_pool,
            S.current_status AS status,
            S.current_cgroup AS control_group,
            P.queue_type AS enqueue,
            S.query,
            P.node_group
    FROM pg_catalog.pg_stat_get_session_wlmstat(NULL) AS S, pg_authid U, pg_catalog.gs_wlm_get_workload_records(0) P
    WHERE P.query_pid = S.threadpid AND
          S.usesysid = U.oid;

DO $DO$
DECLARE
  ans boolean;
BEGIN
  SELECT CASE WHEN count(*) = 1 THEN true ELSE false END
    FROM (SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname = 'dbe_perf' LIMIT 1)
    INTO ans;
  IF ans = true THEN
    CREATE OR REPLACE VIEW dbe_perf.statement_wlmstat_complex_runtime AS
      SELECT
        S.datid AS datid,
        D.datname AS datname,
        S.threadid,
        S.threadpid AS processid,
        S.usesysid,
        S.appname,
        U.rolname AS usename,
        S.priority,
        S.attribute,
        S.block_time,
        S.elapsed_time,
        S.total_cpu_time,
        S.skew_percent AS cpu_skew_percent,
        S.statement_mem,
        S.active_points,
        S.dop_value,
        S.current_cgroup AS control_group,
        S.current_status AS status,
        S.enqueue_state AS enqueue,
        CASE
          WHEN T.session_respool = 'unknown' THEN (U.rolrespool) :: name
          ELSE T.session_respool
        END AS resource_pool,
        S.query,
        S.is_plana,
        S.node_group
      FROM pg_database D, pg_catalog.pg_stat_get_session_wlmstat(NULL) AS S, pg_authid AS U,
          pg_catalog.gs_wlm_session_respool(0) AS T
      WHERE S.datid = D.oid AND
            S.usesysid = U.oid AND
            T.threadid = S.threadid;
  END IF;
END$DO$;
