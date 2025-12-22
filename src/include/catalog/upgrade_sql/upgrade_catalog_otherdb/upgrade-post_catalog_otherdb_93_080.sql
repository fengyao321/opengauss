DROP FUNCTION IF EXISTS pg_catalog.pg_sequence_all_parameters(
    sequence_name text, OUT start_value int16, OUT minimum_value int16, OUT maximum_value int16,
    OUT increment int16, OUT cycle_option boolean, OUT cache_size int16, OUT last_value int16,
    OUT is_called boolean, OUT log_cnt bigint, OUT uuid bigint, OUT last_used_value int16,
    OUT is_exhausted boolean);

SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8930;
CREATE OR REPLACE FUNCTION pg_catalog.pg_sequence_all_parameters(
    sequence_name text, OUT start_value int16, OUT minimum_value int16, OUT maximum_value int16,
    OUT increment int16, OUT cycle_option boolean, OUT cache_size int16, OUT last_value int16,
    OUT is_called boolean, OUT log_cnt bigint, OUT uuid bigint, OUT last_used_value int16,
    OUT is_exhausted boolean)
RETURNS record
LANGUAGE internal
STABLE STRICT NOT FENCED NOT SHIPPABLE
AS $function$pg_sequence_all_parameters$function$;

COMMENT ON FUNCTION pg_catalog.pg_sequence_all_parameters(
    sequence_name text, OUT start_value int16, OUT minimum_value int16, OUT maximum_value int16,
    OUT increment int16, OUT cycle_option boolean, OUT cache_size int16, OUT last_value int16,
    OUT is_called boolean, OUT log_cnt bigint, OUT uuid bigint, OUT last_used_value int16,
    OUT is_exhausted boolean) IS 'sequence all parameters';

SET LOCAL inplace_upgrade_next_system_object_oids = IUO_CATALOG, false, true, 0, 0, 0, 0;
