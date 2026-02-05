DO $$
DECLARE
ans1 boolean;
ans2 boolean;
BEGIN
    select case when count(*)=1 then true else false end as ans from (select * from pg_type where typname = 'jsonpath' limit 1) into ans1;
    select case when count(*)=1 then true else false end as ans from (select * from pg_type where typname = 'jsonb' limit 1) into ans2;
    if ans1 = true and ans2 = true then
        DROP FUNCTION IF EXISTS pg_catalog.jsonb_path_exists(target jsonb, path jsonpath, vars jsonb, silent boolean);
        DROP FUNCTION IF EXISTS pg_catalog.jsonb_path_query_first (target jsonb, path jsonpath, vars jsonb, silent boolean);
    end if;
END$$;

DROP FUNCTION IF EXISTS pg_catalog.jsonpath_in(cstring) CASCADE;
DROP FUNCTION IF EXISTS pg_catalog.jsonpath_recv(internal) CASCADE;

DO $$
DECLARE
ans boolean;
BEGIN
    select case when count(*)=1 then true else false end as ans from (select * from pg_type where typname = 'jsonpath' limit 1) into ans;
    if ans = true then
        DROP FUNCTION IF EXISTS pg_catalog.jsonpath_out(jsonpath);
        DROP FUNCTION IF EXISTS pg_catalog.jsonpath_send(jsonpath);
    end if;
END$$;

DROP TYPE IF EXISTS pg_catalog._jsonpath;
DROP TYPE IF EXISTS pg_catalog.jsonpath;