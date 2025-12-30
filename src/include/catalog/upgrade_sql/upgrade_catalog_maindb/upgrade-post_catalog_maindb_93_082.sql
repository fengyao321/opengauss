DROP FUNCTION IF EXISTS pg_catalog.gs_table_shrink(text, text, text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 7997;
CREATE FUNCTION pg_catalog.gs_table_shrink(text, text, text)
RETURNS int8
LANGUAGE INTERNAL VOLATILE STRICT NOT FENCED
AS 'gs_table_shrink';

DROP FUNCTION IF EXISTS pg_catalog.gs_space_shrink_compact(text, text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 7996;
CREATE FUNCTION pg_catalog.gs_space_shrink_compact(text, text)
RETURNS int8
LANGUAGE INTERNAL VOLATILE STRICT NOT FENCED
AS 'gs_space_shrink_compact';
