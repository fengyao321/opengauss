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