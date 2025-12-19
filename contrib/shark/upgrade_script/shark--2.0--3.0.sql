CREATE OR REPLACE FUNCTION sys.newid() RETURNS uuid LANGUAGE C VOLATILE as '$libdir/shark', 'uuid_generate';

create or replace function sys.get_sequence_start_value(in sequence_name character varying)
returns bigint as
$BODY$
declare
  v_res bigint;
begin
  execute 'select start_value from '|| sequence_name into v_res;
  return v_res;
end;
$BODY$
language plpgsql STABLE STRICT;

create or replace function sys.get_sequence_increment_value(in sequence_name character varying)
returns bigint as
$BODY$
declare
  v_res bigint;
begin
  execute 'select increment_by from '|| sequence_name into v_res;
  return v_res;
end;
$BODY$
language plpgsql STABLE STRICT;

create or replace function sys.get_sequence_last_value(in sequence_name character varying)
returns bigint as
$BODY$
declare
  v_res bigint;
  is_called bool;
begin
  execute 'select is_called from '|| sequence_name into is_called;
  if is_called = 'f' then 
    return NULL;
  end if;
  execute 'select last_value from '|| sequence_name into v_res;
  return v_res;
end;
$BODY$
language plpgsql STABLE STRICT;

drop view if exists sys.columns;
create or replace view sys.columns as
select
  a.attrelid as object_id,
  a.attname as name,
  cast(a.attnum as int) as column_id,
  a.atttypid as system_type_id,
  a.atttypid as user_type_id,
  sys.tsql_type_max_length_helper(t.typname, a.attlen, a.atttypmod) as max_length,
  sys.ts_numeric_precision_helper(t.typname, a.atttypmod) as precision,
  sys.ts_numeric_scale_helper(t.typname, a.atttypmod) as scale,
  coll.collname as collation_name,
  cast(case a.attnotnull when 't' then 0 else 1 end as bit) as is_nullable,
  cast(0 as bit) as is_ansi_padded,
  cast(0 as bit) as is_rowguidcol,
  cast(case when right(pg_get_serial_sequence(quote_ident(s.nspname)||'.'||quote_ident(c.relname), a.attname),
                        13) = '_seq_identity' then 1 else 0 end as bit) as is_identity,
  cast(case when (d.adgencol = 's' or d.adgencol = 'p') then 1 else 0 end as bit) as is_computed,
  cast(0 as bit) as is_filestream,
  sys.ts_is_publication_helper(a.attrelid) as is_replicated,
  cast(0 as bit) as is_non_sql_subscribed,
  cast(0 as bit) as is_merge_published,
  cast(0 as bit) as is_dts_replicated,
  cast(0 as bit) as is_xml_document,
  cast(0 as oid) as xml_collection_id,
  d.oid as default_object_id,
  cast(0 as int) as rule_object_id,
  cast(0 as bit) as is_sparse,
  cast(0 as bit) as is_column_set,
  cast(0 as tinyint) as generated_always_type,
  cast('NOT_APPLICABLE' as nvarchar(60)) as generated_always_type_desc,
  cast(case e.encryption_type when 2 then 1 else 2 end as int) as encryption_type,
  cast(case e.encryption_type when 2 then 'RANDOMIZED' else 'DETERMINISTIC' end as nvarchar(64)) as encryption_type_desc,
  cast((select value from gs_column_keys_args where column_key_id = e.column_key_id and key = 'ALGORITHM') as name) as encryption_algorithm_name,
  e.column_key_id as column_encryption_key_id,
  cast(null as name) as column_encryption_key_database_name,
  cast(0 as bit) as is_hidden,
  cast(0 as bit) as is_masked,
  cast(null as int) as graph_type,
  cast(null as nvarchar(60)) as graph_type_desc
from pg_attribute a
inner join pg_class c on c.oid = attrelid
inner join pg_namespace s on s.oid = c.relnamespace
inner join pg_type t on t.oid = a.atttypid
left join pg_attrdef d on a.attrelid = d.adrelid and a.attnum = d.adnum
left join pg_collation coll on coll.oid = a.attcollation
left join gs_encrypted_columns e on e.rel_id = a.attrelid and e.column_name = a.attname
where not a.attisdropped and a.attnum > 0
and c.relkind in ('r', 'v', 'm', 'f')
and has_column_privilege(quote_ident(s.nspname) ||'.'||quote_ident(c.relname), a.attname, 'SELECT')
and s.nspname not in ('information_schema', 'pg_catalog', 'dbe_pldeveloper', 'coverage', 'dbe_perf', 'cstore', 'db4ai');

create or replace view sys.identity_columns as
select
  a.attrelid as object_id,
  a.attname as name,
  cast(a.attnum as int) as column_id,
  a.atttypid as system_type_id,
  a.atttypid as user_type_id,
  sys.tsql_type_max_length_helper(t.typname, a.attlen, a.atttypmod) as max_length,
  sys.ts_numeric_precision_helper(t.typname, a.atttypmod) as precision,
  sys.ts_numeric_scale_helper(t.typname, a.atttypmod) as scale,
  coll.collname as collation_name,
  cast(case a.attnotnull when 't' then 0 else 1 end as bit) as is_nullable,
  cast(0 as bit) as is_ansi_padded,
  cast(0 as bit) as is_rowguidcol,
  cast(case when right(pg_get_serial_sequence(quote_ident(s.nspname)||'.'||quote_ident(c.relname), a.attname),
                        13) = '_seq_identity' then 1 else 0 end as bit) as is_identity,
  cast(case when (d.adgencol = 's' or d.adgencol = 'p') then 1 else 0 end as bit) as is_computed,
  cast(0 as bit) as is_filestream,
  sys.ts_is_publication_helper(a.attrelid) as is_replicated,
  cast(0 as bit) as is_non_sql_subscribed,
  cast(0 as bit) as is_merge_published,
  cast(0 as bit) as is_dts_replicated,
  cast(0 as bit) as is_xml_document,
  cast(0 as oid) as xml_collection_id,
  d.oid as default_object_id,
  cast(0 as int) as rule_object_id,
  cast(0 as bit) as is_sparse,
  cast(0 as bit) as is_column_set,
  cast(0 as tinyint) as generated_always_type,
  cast('NOT_APPLICABLE' as nvarchar(60)) as generated_always_type_desc,
  cast(case e.encryption_type when 2 then 1 else 2 end as int) as encryption_type,
  cast(case e.encryption_type when 2 then 'RANDOMIZED' else 'DETERMINISTIC' end as nvarchar(64)) as encryption_type_desc,
  cast((select value from gs_column_keys_args where column_key_id = e.column_key_id and key = 'ALGORITHM') as name) as encryption_algorithm_name,
  e.column_key_id as column_encryption_key_id,
  cast(null as name) as column_encryption_key_database_name,
  cast(0 as bit) as is_hidden,
  cast(0 as bit) as is_masked,
  cast(null as int) as graph_type,
  cast(null as nvarchar(60)) as graph_type_desc,
  cast(sys.get_sequence_start_value(pg_get_serial_sequence(quote_ident(s.nspname)||'.'||quote_ident(c.relname), a.attname)) AS SQL_VARIANT) as seed_value,
  cast(sys.get_sequence_increment_value(pg_get_serial_sequence(quote_ident(s.nspname)||'.'||quote_ident(c.relname), a.attname)) AS SQL_VARIANT) as increment_value,
  cast(sys.get_sequence_last_value(pg_get_serial_sequence(quote_ident(s.nspname)||'.'||quote_ident(c.relname), a.attname)) AS SQL_VARIANT) as last_value,
  cast(0 as bit) as is_not_for_replication
from pg_attribute a
inner join pg_class c on c.oid = attrelid
inner join pg_namespace s on s.oid = c.relnamespace
inner join pg_type t on t.oid = a.atttypid
left join pg_attrdef d on a.attrelid = d.adrelid and a.attnum = d.adnum
left join pg_collation coll on coll.oid = a.attcollation
left join gs_encrypted_columns e on e.rel_id = a.attrelid and e.column_name = a.attname
where not a.attisdropped and a.attnum > 0
and c.relkind in ('r', 'v', 'm', 'f')
and has_column_privilege(quote_ident(s.nspname) ||'.'||quote_ident(c.relname), a.attname, 'SELECT')
and s.nspname not in ('information_schema', 'pg_catalog', 'dbe_pldeveloper', 'coverage', 'dbe_perf', 'cstore', 'db4ai')
and is_identity = 1::bit;

CREATE OR REPLACE VIEW sys.server_principals
AS SELECT
CAST(Role.rolname AS NAME) AS name,
CAST(Role.oid AS INT) AS principal_id,
CAST(CAST(Role.oid as INT) AS sys.varbinary(85)) AS sid,
CAST(
   CASE
    WHEN 
      Role.rolauditadmin = true OR 
      Role.rolsystemadmin = true OR 
      Role.rolmonitoradmin = true OR 
      Role.roloperatoradmin = true OR 
      Role.rolpolicyadmin = true THEN 'R'
    WHEN
      Role.rolcanlogin = true THEN 'S'
    ELSE
      NULL
   END
   AS CHAR(1)) AS type,
CAST(
    CASE
      WHEN 
        Role.rolauditadmin = true OR 
        Role.rolsystemadmin = true OR 
        Role.rolmonitoradmin = true OR 
        Role.roloperatoradmin = true OR 
        Role.rolpolicyadmin = true THEN 'SERVER_ROLE'
      WHEN
        Role.rolcanlogin = true THEN 'SQL_LOGIN'
      ELSE
        NULL
   END
    AS NVARCHAR2(60)) AS type_desc,
CAST(
    CASE
      WHEN Role.rolcanlogin = true THEN 0
      ELSE 1
    END
    AS INT) AS is_disbaled,
CAST(NULL AS TIMESTAMP) AS create_date,
CAST(NULL AS TIMESTAMP) AS modify_date,
CAST(NULL AS NAME) AS default_database_name,
CAST('english' AS NAME) AS default_language_name,
CAST(-1 AS INT) AS creadential_id,
CAST(-1 AS INT) AS owning_principal_id,
CAST(-1 AS INT) AS is_fixed_role
FROM pg_catalog.pg_roles AS Role;

-- datepart
CREATE OR REPLACE FUNCTION sys.datepart(cstring, int)
RETURNS integer
language c
immutable strict NOT FENCED NOT SHIPPABLE
AS '$libdir/shark', $function$datepartint$function$;

CREATE OR REPLACE FUNCTION sys.datepart(text, text) RETURNS integer LANGUAGE SQL STABLE as 'select sys.datepart($1::cstring, $2::timestamp without time zone)';

-- sys.foreign_key_columns
CREATE OR REPLACE VIEW sys.foreign_key_columns AS
SELECT
  con.oid AS constraint_object_id,
  CAST((generate_series(1, ARRAY_LENGTH(con.conkey, 1))) AS INT) AS constraint_column_id,
  con.conrelid AS parent_object_id,
  CAST((UNNEST(con.conkey)) AS INT) AS parent_column_id,
  con.confrelid AS referenced_object_id,
  CAST((UNNEST(con.confkey)) AS INT) AS referenced_column_id
FROM pg_constraint con
INNER JOIN pg_class c ON c.oid = con.conrelid
INNER JOIN pg_namespace s ON s.oid = con.connamespace
WHERE con.contype = 'f'
AND s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'));

-- sys.foreign_keys
CREATE OR REPLACE VIEW sys.foreign_keys AS
SELECT
  con.conname AS name,
  con.oid AS object_id,
  CAST(NULL AS INT) AS principal_id,
  con.connamespace AS schema_id,
  con.conrelid AS parent_object_id,
  CAST('F' AS CHAR(2)) AS type,
  CAST('FOREIGN_KEY_CONSTRAINT' AS NVARCHAR(60)) AS type_desc,
  CAST(NULL AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(0 AS BIT) AS is_published,
  CAST(0 AS BIT) AS is_schema_published,
  con.confrelid AS referenced_object_id,
  con.conindid AS key_index_id,
  CAST(CAST(con.condisable AS INT) AS BIT) AS is_disabled,
  CAST(0 AS BIT) AS is_not_for_replication,
  CAST(CAST(NOT con.convalidated AS INT) AS BIT) AS is_not_trusted,
  CAST(
    (CASE con.confdeltype
      WHEN 'a' THEN 0
      WHEN 'r' THEN 0
      WHEN 'c' THEN 1
      WHEN 'n' THEN 2
      WHEN 'd' THEN 3
      ELSE -1
    END)
    AS TINYINT) AS delete_referential_action,
  CAST(
    (CASE con.confdeltype
      WHEN 'a' THEN 'NO_ACTION'
      WHEN 'r' THEN 'NO_ACTION'
      WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET_NULL'
      WHEN 'd' THEN 'SET_DEFAULT'
      ELSE ''
    END)
    AS NVARCHAR(60)) AS delete_referential_action_desc,
  CAST(
    (CASE con.confupdtype
      WHEN 'a' THEN 0
      WHEN 'r' THEN 0
      WHEN 'c' THEN 1
      WHEN 'n' THEN 2
      WHEN 'd' THEN 3
      ELSE -1
    END)
    AS TINYINT) AS update_referential_action,
  CAST(
    (CASE con.confupdtype
      WHEN 'a' THEN 'NO_ACTION'
      WHEN 'r' THEN 'NO_ACTION'
      WHEN 'c' THEN 'CASCADE'
      WHEN 'n' THEN 'SET_NULL'
      WHEN 'd' THEN 'SET_DEFAULT'
      ELSE ''
    END)
    AS NVARCHAR(60)) update_referential_action_desc,
  CAST(1 AS BIT) AS is_system_named
FROM pg_constraint con
INNER JOIN pg_class c ON c.oid = con.conrelid
INNER JOIN pg_namespace s ON s.oid = con.connamespace
WHERE con.contype = 'f'
AND s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'));

-- sys.key_constraints
CREATE OR REPLACE VIEW sys.key_constraints AS
SELECT
  con.conname AS name,
  con.oid AS object_id,
  CAST(null AS INT) AS principal_id,
  con.connamespace AS schema_id,
  con.conrelid AS parent_object_id,
  CAST(CASE con.contype
        WHEN 'p' THEN 'PK'
        WHEN 'u' THEN 'UQ'
        ELSE ''
      END AS CHAR(2)) AS type,
  CAST(CASE con.contype
        WHEN 'p' THEN 'PRIMARY_KEY_CONSTRAINT'
        WHEN 'u' THEN 'UNIQUE_CONSTRAINT'
        ELSE ''
      END AS NVARCHAR(60)) AS type_desc,
  CAST(NULL AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(0 AS BIT) AS is_published,
  CAST(0 AS BIT) AS is_schema_published,
  con.conindid AS unique_index_id,
  CAST(
    (CASE WHEN con.contype = 'p' AND con.conname = format('%s_pkey', c.relname) THEN 1
      WHEN con.contype = 'u' AND con.conname = format('%s_%s_key', c.relname,
        array_to_string(ARRAY(
           SELECT attname
           FROM pg_attribute att
           WHERE att.attrelid = con.conrelid
             AND att.attnum = ANY(con.conkey)
           ORDER BY array_position(con.conkey, att.attnum)
       ), '_')) THEN 1
      ELSE 0
    END)
    AS BIT) AS is_system_named,
  CAST(CAST(NOT con.condisable AS INT) AS BIT) AS is_enforced
FROM pg_constraint con
INNER JOIN pg_class c ON c.oid = con.conrelid
INNER JOIN pg_namespace s ON s.oid = con.connamespace
WHERE con.contype IN ('p', 'u')
AND s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'));

-- sys.sysforeignkeys
CREATE OR REPLACE VIEW sys.sysforeignkeys AS
SELECT
  con.oid AS constid,
  con.conrelid AS fkeyid,
  con.confrelid AS rkeyid,
  CAST((UNNEST(con.conkey)) AS SMALLINT) AS fkey,
  CAST((UNNEST(con.confkey)) AS SMALLINT) AS rkey,
  CAST((generate_series(1, ARRAY_LENGTH(con.conkey, 1))) AS SMALLINT) AS keyno
FROM pg_constraint con
INNER JOIN pg_class c ON c.oid = con.conrelid
INNER JOIN pg_namespace s ON s.oid = con.connamespace
WHERE con.contype = 'f'
AND s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'));

-- sys.synonyms
CREATE OR REPLACE VIEW sys.synonyms AS
SELECT
  syn.synname AS name,
  syn.oid AS object_id,
  CAST(CASE s.nspowner WHEN syn.synowner THEN NULL ELSE syn.synowner END AS OID) AS principal_id,
  syn.synnamespace AS schema_id,
  CAST(NULL AS OID) AS parent_object_id,
  CAST('SN' AS char(2)) AS type,
  CAST('Synonym' AS nvarchar(60)) AS type_desc,
  CAST(NULL AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS bit) AS is_ms_shipped,
  CAST(0 AS bit) AS is_published,
  CAST(0 AS bit) AS is_schema_published,
  CAST(quote_ident(syn.synobjschema)||'.'||quote_ident(syn.synobjname) AS NVARCHAR(1035)) AS base_object_name
FROM pg_synonym syn
INNER JOIN pg_namespace s ON s.oid = syn.synnamespace
WHERE s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql');

-- sys.all_views
CREATE OR REPLACE VIEW sys.all_views AS
SELECT
  t.relname AS name,
  t.oid AS object_id,
  CAST(CASE s.nspowner WHEN t.relowner THEN NULL ELSE t.relowner END AS OID) AS principal_id,
  s.oid AS schema_id,
  CAST(0 AS OID) AS parent_object_id,
  CAST('V' AS CHAR(2)) AS type,
  CAST('VIEW' AS NVARCHAR(60)) AS type_desc,
  CAST(o.ctime AS TIMESTAMP) AS create_date,
  CAST(o.mtime AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(0 AS BIT) AS is_published,
  CAST(0 AS BIT) AS is_schema_published,
  CAST(0 AS BIT) AS is_replicated,
  CAST(0 AS BIT) AS has_replication_filter,
  CAST(0 AS BIT) AS has_opaque_metadata,
  CAST(0 AS BIT) AS has_unchecked_ASsembly_data,
  CAST(CASE WHEN sys.tsql_relation_reloptions_helper(t.reloptions, 'check_option') is NULL THEN 0 ELSE 1 END AS BIT) AS with_check_option,
  CAST(0 AS BIT) AS is_date_correlation_view,
  CAST(0 AS BIT) AS is_tracked_by_cdc
FROM pg_class t
INNER JOIN pg_namespace s ON t.relnamespace = s.oid
LEFT JOIN pg_object o ON o.object_oid = t.oid
WHERE t.relkind IN ('v', 'm')
AND (pg_catalog.pg_has_role(t.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(t.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(t.oid, 'SELECT, INSERT, UPDATE, REFERENCES'));

-- sys.trigger_events
CREATE OR REPLACE VIEW sys.trigger_events AS
SELECT
  pt.oid AS object_id,
  CAST(t_events.type AS INT) AS type,
  CAST(t_events.type_desc AS NVARCHAR(60)) AS type_desc,
  CAST(0 AS BIT) AS is_first,
  CAST(0 AS BIT) AS is_last,
  CAST(NULL AS INT) AS event_group_type,
  CAST(NULL AS NVARCHAR(60)) AS event_group_type_desc,
  CAST(1 AS BIT) AS is_trigger_event
FROM pg_trigger pt
    CROSS JOIN LATERAL (
        SELECT * FROM (
            VALUES
                (1, 'INSERT', 4),
                (2, 'UPDATE', 16),
                (3, 'DELETE', 8),
                (4, 'TRUNCATE', 32)
        ) AS v(type, type_desc, bitmask)
        WHERE (pt.tgtype & bitmask) != 0
    ) AS t_events
INNER JOIN pg_class c ON pt.tgrelid = c.oid
WHERE pg_catalog.pg_has_role(c.relowner, 'USAGE')
OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES')
UNION ALL
SELECT
  pet.oid AS object_id,
  CAST(et_events.type AS INT) AS type,
  CAST(et_events.type_desc AS NVARCHAR(60)) AS type_desc,
  CAST(0 AS BIT) AS is_first,
  CAST(0 AS BIT) AS is_last,
  CAST(NULL AS INT) AS event_group_type,
  CAST(NULL AS NVARCHAR(60)) AS event_group_type_desc,
  CAST(1 AS BIT) AS is_trigger_event
FROM pg_event_trigger pet
    CROSS JOIN LATERAL (
        SELECT * FROM (
            VALUES
                (5, 'DDL_COMMAND_START'),
                (6, 'DDL_COMMAND_END'),
                (7, 'TABLE_REWRITE'),
                (8, 'SQL_DROP')
        ) AS v(type, type_desc)
        WHERE pet.evtevent = lower(type_desc)
    ) AS et_events
ORDER BY object_id, type;

-- sys.triggers
CREATE OR REPLACE VIEW sys.triggers AS
SELECT
  pt.tgname AS name,
  pt.oid AS object_id,
  CAST(1 AS TINYINT) AS parent_class,
  CAST('OBJECT_OR_COLUMN' AS NVARCHAR(60)) AS parent_class_desc,
  pt.tgrelid AS parent_id,
  CAST('TR' AS CHAR(2)) AS type,
  CAST('SQL_TRIGGER' AS NVARCHAR(60)) AS type_desc,
  CAST(pt.tgtime AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(
    CASE
      WHEN pt.tgenabled = 'D' THEN 1
      ELSE 0
    END AS BIT
  )	AS is_disabled,
  CAST(0 AS BIT) AS is_not_for_replication,
  CAST(
    CASE
        WHEN (pt.tgtype >> 6 & 1) = 1 THEN 1
        WHEN (pt.tgtype >> 1 & 1) = 1 THEN 2
        ELSE 0
    END AS TINYINT
  ) AS is_instead_of_trigger
FROM pg_trigger pt
INNER JOIN pg_class c ON pt.tgrelid = c.oid
WHERE pg_catalog.pg_has_role(c.relowner, 'USAGE')
OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES')
UNION ALL
SELECT
  pet.evtname AS name,
  pet.oid AS object_id,
  CAST(0 AS TINYINT) AS parent_class,
  CAST('DDL' AS NVARCHAR(60)) AS parent_class_desc,
  CAST(0 AS OID) AS parent_id,
  CAST('TR' AS CHAR(2)) AS type,
  CAST('SQL_TRIGGER' AS NVARCHAR(60)) AS type_desc,
  CAST(NULL AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(
    CASE
      WHEN pet.evtenabled = 'D' THEN 1
      ELSE 0
    END AS BIT
  )	AS is_disabled,
  CAST(0 AS BIT) AS is_not_for_replication,
  CAST(0 AS TINYINT) AS is_instead_of_trigger
FROM pg_event_trigger pet;

-- sys.configurations
CREATE OR REPLACE VIEW sys.configurations AS
SELECT
  CAST(NULL AS INT) AS configuration_id,
  CAST(s.name AS NVARCHAR(35)) AS name,
  CAST(s.setting AS SQL_VARIANT) AS value,
  CAST(s.min_val AS SQL_VARIANT) AS minimum,
  CAST(s.max_val AS SQL_VARIANT) AS maximum,
  CAST(s.setting AS SQL_VARIANT) AS value_in_use,
  CAST(s.short_desc AS NVARCHAR(255)) AS description,
  CAST(
    CASE
      WHEN s.context = 'postmaster' or s.context = 'internal' THEN 0
      ELSE 1
    END AS BIT
  ) AS is_dynamic,
  CAST(0 AS BIT) AS is_advanced
FROM pg_settings s;

-- sys.syscurconfigs
CREATE OR REPLACE VIEW sys.syscurconfigs AS
SELECT
  CAST(s.setting AS SQL_VARIANT) AS value,
  CAST(NULL AS SMALLINT) AS config,
  CAST(s.short_desc AS NVARCHAR(255)) AS comment,
  CAST(
    CASE
      WHEN s.context = 'postmaster' OR s.context = 'internal' THEN 0
      ELSE 1
    END AS SMALLINT
  ) AS status
FROM pg_settings s;

-- sys.sysconfigures
CREATE OR REPLACE VIEW sys.sysconfigures AS
SELECT
  CAST(s.setting AS SQL_VARIANT) AS value,
  CAST(NULL AS INT) AS config,
  CAST(s.short_desc AS NVARCHAR(255)) AS comment,
  CAST(
    CASE
      WHEN s.context = 'postmaster' OR s.context = 'internal' THEN 0
      ELSE 1
    END AS SMALLINT
  ) AS status
FROM pg_settings s;

-- sys.check_constraints
CREATE OR REPLACE VIEW sys.check_constraints AS
SELECT
  con.conname AS name,
  con.oid AS object_id,
  CAST(NULL AS INT) AS principal_id,
  con.connamespace AS schema_id,
  con.conrelid AS parent_object_id,
  CAST('C' AS char(2)) AS type,
  CAST('CHECK_CONSTRAINT' AS NVARCHAR(60)) AS type_desc,
  CAST(NULL AS TIMESTAMP) AS create_date,
  CAST(NULL AS TIMESTAMP) AS modify_date,
  CAST(0 AS BIT) AS is_ms_shipped,
  CAST(0 AS BIT) AS is_published,
  CAST(0 AS BIT) AS is_schema_published,
  CAST(CAST(con.condisable AS INT) AS BIT) AS is_disabled,
  CAST(0 AS BIT) AS is_not_for_replication,
  CAST(CAST(NOT con.convalidated AS INT) AS BIT) AS is_not_trusted,
  CAST(CASE WHEN ARRAY_LENGTH(con.conkey, 1) != 1 THEN 0 ELSE con.conkey[1] END AS INT) AS parent_column_id,
  con.consrc AS definition,
  CAST(1 AS BIT) AS uses_database_collation,
  CAST(1 AS BIT) AS is_system_named
FROM pg_constraint con
INNER JOIN pg_class c ON c.oid = con.conrelid
INNER JOIN pg_namespace s ON s.oid = con.connamespace
WHERE con.contype = 'c'
AND s.nspname NOT IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES'));

-- sys.index_columns
CREATE OR REPLACE VIEW sys.index_columns AS
SELECT
  i.indrelid AS object_id,
  i.indexrelid AS index_id,
  CAST(idx AS INT) AS index_column_id,
  CAST(i.indkey[idx - 1] AS INT) AS column_id,
  CAST(
    (CASE
      WHEN index_column_id <= i.indnkeyatts THEN index_column_id
      ELSE 0
    END)
    AS TINYINT) AS key_ordinal,
  CAST(0 AS TINYINT) AS partition_ordinal,
  CAST(
    (CASE
      WHEN i.indoption[index_column_id - 1] & 1 = 1 THEN 1
      ELSE 0
    END)
    AS BIT) AS is_descending_key,
  CAST(
    (CASE
      WHEN idx > i.indnkeyatts THEN 1
      ELSE 0
    END)
    AS BIT) AS is_included_column
FROM
    pg_index i
    INNER JOIN pg_class c ON i.indrelid = c.oid and c.parttype = 'n'
    INNER JOIN pg_namespace nsp ON nsp.oid = c.relnamespace
    INNER JOIN generate_series(1, array_length(i.indkey, 1)) AS idx ON TRUE
WHERE
    pg_catalog.pg_has_role(c.relowner, 'USAGE')
    OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
    OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES')
UNION ALL
SELECT
  i.indrelid AS object_id,
  i.indexrelid AS index_id,
  CAST(idx AS INT) AS index_column_id,
  CAST(i.indkey[idx - 1] AS INT) AS column_id,
  CAST(
    (CASE
      WHEN index_column_id <= i.indnkeyatts THEN index_column_id
      ELSE 0
    END)
    AS TINYINT) AS key_ordinal,
  CAST(
    (CASE
      WHEN array_position(string_to_array(pp.partkey::TEXT, ' ')::int2[], i.indkey[idx - 1]) IS NULL THEN 0
      ELSE array_position(string_to_array(pp.partkey::TEXT, ' ')::int2[], i.indkey[idx - 1])
    END)
    AS TINYINT) AS partition_ordinal,
  CAST(
    (CASE
      WHEN i.indoption[index_column_id - 1] & 1 = 1 THEN 1
      ELSE 0
    END)
    AS BIT) AS is_descending_key,
  CAST(
    (CASE
      WHEN idx > i.indnkeyatts AND i.indkey[idx - 1] > 0 THEN 1
      ELSE 0
    END)
    AS BIT) AS is_included_column
FROM
    pg_index i
    INNER JOIN pg_class c ON i.indrelid = c.oid and c.parttype != 'n'
    INNER JOIN pg_namespace nsp ON nsp.oid = c.relnamespace
    INNER JOIN pg_partition pp ON pp.parentid = c.oid AND pp.relname = c.relname
    INNER JOIN generate_series(1, array_length(i.indkey, 1)) AS idx ON TRUE
WHERE
    pg_catalog.pg_has_role(c.relowner, 'USAGE')
    OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
    OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES');

-- sys.system_objects
CREATE OR REPLACE VIEW sys.system_objects AS
SELECT o.* FROM sys.all_objects o
INNER JOIN pg_namespace s ON o.schema_id = s.oid
AND s.nspname IN ('information_schema', 'pg_catalog', 'sys', 'information_schema_tsql')
UNION ALL
SELECT
  t.relname AS name,
  t.oid AS object_id,
  CAST(CASE s.nspowner WHEN t.relowner THEN NULL ELSE t.relowner END AS OID) AS principal_id,
  s.oid AS schema_id,
  CAST(0 AS OID) AS parent_object_id,
  CAST('V' AS CHAR(2)) AS type,
  CAST('VIEW' AS NVARCHAR(60)) AS type_desc,
  CAST(o.ctime AS TIMESTAMP) AS create_date,
  CAST(o.mtime AS TIMESTAMP) AS modify_date,
  CAST(0 AS bit) AS is_ms_shipped,
  CAST(0 AS bit) AS is_published,
  CAST(0 AS bit) AS is_schema_published
FROM pg_class t
INNER JOIN pg_namespace s ON t.relnamespace = s.oid
LEFT JOIN pg_object o ON o.object_oid = t.oid
WHERE t.relkind IN ('v', 'm')
AND s.nspname = 'dbe_perf'
AND (pg_catalog.pg_has_role(t.relowner, 'USAGE')
  OR pg_catalog.has_table_privilege(t.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  OR pg_catalog.has_any_column_privilege(t.oid, 'SELECT, INSERT, UPDATE, REFERENCES'));

-- sys.database_principals
CREATE OR REPLACE VIEW sys.database_principals AS
SELECT
rolname AS name,
oid AS principal_id,
CAST('R' AS CHAR(1)) AS type,
CAST('DATABASE_ROLE' AS NVARCHAR(60)) AS type_desc,
CAST(NULL AS NAME) AS default_schema_name,
CAST(NULL AS TIMESTAMP) AS create_date,
CAST(NULL AS TIMESTAMP) AS modify_date,
10 AS owning_principal_id,
CAST(CAST(oid AS INT) AS VARBINARY(85)) AS SID,
CAST(CASE WHEN oid < 16384 THEN 1 ELSE 0 END AS BIT) AS is_fixed_role,
0 as authentication_type,
CAST('NONE' AS NVARCHAR(60)) as authentication_type_desc,
CAST(NULL AS NAME) AS default_language_name,
CAST(NULL AS INT) AS default_language_lcid,
CAST(0 AS BIT) AS allow_encrypted_value_modifications
from pg_roles;

-- sys.sysprocesses
CREATE OR REPLACE VIEW sys.sysprocesses AS
SELECT
  blocked_activity.pid AS spid,
  CAST(NULL AS SMALLINT) AS kpid,
  (SELECT blocking_activity.pid
     FROM pg_locks blocked
     JOIN pg_locks blocking
       ON blocking.locktype = blocked.locktype
      AND blocking.database IS NOT DISTINCT FROM blocked.database
      AND blocking.relation IS NOT DISTINCT FROM blocked.relation
      AND blocking.page IS NOT DISTINCT FROM blocked.page
      AND blocking.tuple IS NOT DISTINCT FROM blocked.tuple
      AND blocking.virtualxid IS NOT DISTINCT FROM blocked.virtualxid
      AND blocking.transactionid IS NOT DISTINCT FROM blocked.transactionid
      AND blocking.classid IS NOT DISTINCT FROM blocked.classid
      AND blocking.objid IS NOT DISTINCT FROM blocked.objid
      AND blocking.objsubid IS NOT DISTINCT FROM blocked.objsubid
      AND blocking.pid != blocked.pid
      AND blocking.granted = true
      AND blocked.granted = false
     JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking.pid
     WHERE blocked.pid = blocked_activity.pid
     LIMIT 1
  ) AS blocked,
  CAST(NULL AS VARBINARY(2)) AS waittype,
  CAST(0 AS BIGINT) AS waittime,
  CAST(NULL AS NCHAR(32)) AS lastwaittype,
  CAST(NULL AS NCHAR(256)) AS waitresource,
  blocked_activity.datid AS dbid,
  blocked_activity.usesysid AS uid,
  0 AS cpu,
  CAST(0 AS BIGINT) AS physical_io,
  0 AS memusage,
  blocked_activity.backend_start AS login_time,
  blocked_activity.query_start AS last_batch,
  CAST(0 AS SMALLINT) AS ecid,
  CAST(0 AS SMALLINT) AS open_tran,
  CAST(blocked_activity.state AS NCHAR(30)) AS status,
  CAST(CAST(blocked_activity.usesysid AS INT) AS VARBINARY(86)) AS sid,
  CAST(blocked_activity.client_hostname AS NCHAR(128)) AS hostname,
  CAST(blocked_activity.application_name AS NCHAR(128)) AS program_name,
  CAST(NULL AS NCHAR(10)) AS hostprocess,
  blocked_activity.query AS cmd,
  CAST(NULL AS NCHAR(128)) AS nt_domain,
  CAST(NULL AS NCHAR(128)) AS nt_username,
  CAST(NULL AS NCHAR(12)) AS net_address,
  CAST(NULL AS NCHAR(12)) AS net_library,
  CAST(blocked_activity.usename AS NCHAR(128)) AS loginname,
  CAST(NULL AS VARBINARY(128)) AS context_info,
  CAST(NULL AS VARBINARY(20)) AS sql_handle,
  0 AS stmt_start,
  0 AS stmt_end,
  blocked_activity.query_id AS request_id
FROM pg_stat_activity blocked_activity;
