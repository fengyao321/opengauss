DROP FUNCTION IF EXISTS pg_catalog.online_ddl_status() CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 6994;
CREATE FUNCTION pg_catalog.online_ddl_status(
    out relid                 int4,
    out hash_entry_key        text,
    out transaction_id        int8,
    out start_time            timestamp with time zone,
    out online_ddl_type       text,
    out temp_schema_name      text,
    out status                text,
    out extra_info            text
)
RETURNS SETOF record LANGUAGE INTERNAL as 'get_online_ddl_status' stable rows 64;
