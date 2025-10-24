-- varchar to blob
DROP CAST IF EXISTS (varchar AS blob);

DROP FUNCTION IF EXISTS pg_catalog.varchar_blob(varchar);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 2950;
CREATE FUNCTION pg_catalog.varchar_blob(varchar) RETURNS blob LANGUAGE INTERNAL IMMUTABLE STRICT AS 'texttoraw';
COMMENT ON FUNCTION pg_catalog.varchar_blob(varchar) is 'varchar_blob';

CREATE CAST (varchar AS blob) WITH FUNCTION pg_catalog.varchar_blob(varchar) AS ASSIGNMENT;
