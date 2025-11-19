do $$
BEGIN
IF working_version_num() < 92975 OR working_version_num() >= 93000 then
DROP FUNCTION IF EXISTS pg_catalog.scale(numeric) CASCADE;
DROP FUNCTION IF EXISTS pg_catalog.make_timestamp(int4, int4, int4, int4, int4, float8) CASCADE;
DROP FUNCTION IF EXISTS pg_catalog.array_position(anyarray, int4) CASCADE;
END IF;
END$$;