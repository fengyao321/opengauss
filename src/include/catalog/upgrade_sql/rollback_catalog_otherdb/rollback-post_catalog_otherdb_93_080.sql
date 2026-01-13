do $$
DECLARE
ans boolean;
BEGIN
    for ans in select case when count(*)=1 then true else false end as ans from (select extname from pg_extension where extname='shark')
    LOOP
        if ans = true then
            ALTER EXTENSION shark UPDATE TO '2.0';
        end if;
        exit;
    END LOOP;
END$$;

DROP FUNCTION IF EXISTS pg_catalog.pg_sequence_all_parameters(
    sequence_name text, OUT start_value int16, OUT minimum_value int16, OUT maximum_value int16,
    OUT increment int16, OUT cycle_option boolean, OUT cache_size int16, OUT last_value int16,
    OUT is_called boolean, OUT log_cnt bigint, OUT uuid bigint, OUT last_used_value int16,
    OUT is_exhausted boolean);