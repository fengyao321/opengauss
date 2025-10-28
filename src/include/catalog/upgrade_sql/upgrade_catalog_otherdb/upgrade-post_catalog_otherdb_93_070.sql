do $$
DECLARE
ans boolean;
BEGIN
    for ans in select case when count(*)=1 then true else false end as ans from (select extname from pg_extension where extname='shark')
    LOOP
        if ans = true then
            ALTER EXTENSION shark UPDATE TO '3.0';
        end if;
        exit;
    END LOOP;
END$$;
