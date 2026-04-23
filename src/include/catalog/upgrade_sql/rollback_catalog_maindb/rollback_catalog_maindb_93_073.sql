SET search_path TO information_schema;

DROP VIEW IF EXISTS referential_constraints CASCADE;
CREATE OR REPLACE VIEW referential_constraints AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(ncon.nspname AS sql_identifier) AS constraint_schema,
           CAST(con.conname AS sql_identifier) AS constraint_name,
           CAST(
             CASE WHEN npkc.nspname IS NULL THEN NULL
                  ELSE pg_catalog.current_database() END
             AS sql_identifier) AS unique_constraint_catalog,
           CAST(npkc.nspname AS sql_identifier) AS unique_constraint_schema,
           CAST(pkc.conname AS sql_identifier) AS unique_constraint_name,

           CAST(
             CASE con.confmatchtype WHEN 'f' THEN 'FULL'
                                    WHEN 'p' THEN 'PARTIAL'
                                    WHEN 'u' THEN 'NONE' END
             AS character_data) AS match_option,

           CAST(
             CASE con.confupdtype WHEN 'c' THEN 'CASCADE'
                                  WHEN 'n' THEN 'SET NULL'
                                  WHEN 'd' THEN 'SET DEFAULT'
                                  WHEN 'r' THEN 'RESTRICT'
                                  WHEN 'a' THEN 'NO ACTION' END
             AS character_data) AS update_rule,

           CAST(
             CASE con.confdeltype WHEN 'c' THEN 'CASCADE'
                                  WHEN 'n' THEN 'SET NULL'
                                  WHEN 'd' THEN 'SET DEFAULT'
                                  WHEN 'r' THEN 'RESTRICT'
                                  WHEN 'a' THEN 'NO ACTION' END
             AS character_data) AS delete_rule

    FROM (pg_namespace ncon
          INNER JOIN pg_catalog.pg_constraint con ON ncon.oid = con.connamespace
          INNER JOIN pg_catalog.pg_class c ON con.conrelid = c.oid AND con.contype = 'f')
         LEFT JOIN pg_catalog.pg_depend d1  -- find constraint's dependency on an index
          ON d1.objid = con.oid AND d1.classid = 'pg_constraint'::regclass
             AND d1.refclassid = 'pg_class'::regclass AND d1.refobjsubid = 0
         LEFT JOIN pg_catalog.pg_depend d2  -- find pkey/unique constraint for that index
          ON d2.refclassid = 'pg_constraint'::regclass
             AND d2.classid = 'pg_class'::regclass
             AND d2.objid = d1.refobjid AND d2.objsubid = 0
             AND d2.deptype = 'i'
         LEFT JOIN pg_catalog.pg_constraint pkc ON pkc.oid = d2.refobjid
            AND pkc.contype IN ('p', 'u')
            AND pkc.conrelid = con.confrelid
         LEFT JOIN pg_catalog.pg_namespace npkc ON pkc.connamespace = npkc.oid

    WHERE pg_catalog.pg_has_role(c.relowner, 'USAGE')
          -- SELECT privilege omitted, per SQL standard
          OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
          OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES') ;

GRANT SELECT ON referential_constraints TO PUBLIC;

RESET search_path;

DO $DO$
DECLARE
  ans boolean;
BEGIN
  SELECT CASE WHEN count(*) = 1 THEN true ELSE false END
    FROM (SELECT nspname FROM pg_catalog.pg_namespace WHERE nspname = 'dbe_perf' LIMIT 1)
    INTO ans;
  IF ans = true THEN
    DROP VIEW IF EXISTS dbe_perf.statement_wlmstat_complex_runtime;
  END IF;
END$DO$;

DROP VIEW IF EXISTS pg_catalog.gs_wlm_workload_records;
DROP VIEW IF EXISTS pg_catalog.pg_session_wlmstat;
DROP FUNCTION IF EXISTS pg_catalog.pg_stat_get_session_wlmstat(INT4);
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
    OUT srespool NAME)
RETURNS SETOF record
LANGUAGE INTERNAL
STABLE
ROWS 100
AS 'pg_stat_get_session_wlmstat';

CREATE VIEW pg_catalog.pg_session_wlmstat AS
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
            S.node_group
    FROM pg_catalog.pg_database D, pg_catalog.pg_stat_get_session_wlmstat(NULL) AS S, pg_authid AS U,
        pg_catalog.gs_wlm_session_respool(0) AS T
    WHERE S.datid = D.oid AND
          S.usesysid = U.oid AND
          T.sessionid = S.sessionid;

CREATE VIEW pg_catalog.gs_wlm_workload_records AS
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
    CREATE VIEW dbe_perf.statement_wlmstat_complex_runtime AS
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
