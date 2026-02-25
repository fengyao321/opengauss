-- Rollback pg_lsn type and related I/O functions
-- This rollback script removes the pg_lsn type and its I/O functions

DO $$
DECLARE
ans boolean;
BEGIN
    -- Check if pg_lsn type exists
    select case when count(*)=1 then true else false end as ans 
    from (select * from pg_type where typname = 'pg_lsn' limit 1) into ans;
    
    if ans = true then
        DROP FUNCTION IF EXISTS pg_catalog.pg_lsn_send(pg_lsn) CASCADE;
        DROP FUNCTION IF EXISTS pg_catalog.pg_lsn_recv(internal) CASCADE;
        DROP FUNCTION IF EXISTS pg_catalog.pg_lsn_out(pg_lsn) CASCADE;
        DROP FUNCTION IF EXISTS pg_catalog.pg_lsn_in(cstring) CASCADE;
    end if;
END$$;

DROP TYPE IF EXISTS pg_catalog._pg_lsn CASCADE;
DROP TYPE IF EXISTS pg_catalog.pg_lsn CASCADE;
