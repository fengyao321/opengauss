DO $$
DECLARE
ans boolean;
BEGIN
    select case when count(*)=1 then true else false end as ans from (select * from pg_type where typname = 'jsonb' limit 1) into ans;
    if ans = true then
        DROP OPERATOR IF EXISTS pg_catalog.||(jsonb, jsonb) CASCADE;
        DROP FUNCTION IF EXISTS pg_catalog.jsonb_concat(jsonb, jsonb) CASCADE;
    end if;
END$$;