DROP FUNCTION IF EXISTS pg_catalog.jsonb_concat(jsonb, jsonb) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4301;
CREATE FUNCTION pg_catalog.jsonb_concat(
    jsonb, jsonb
) RETURNS jsonb LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonb_concat';
comment on function jsonb_concat(jsonb, jsonb) is 'implementation of || operator';

DROP OPERATOR IF EXISTS pg_catalog.||(jsonb, jsonb) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_GENERAL, 3284;
CREATE OPERATOR pg_catalog.||(
    leftarg = jsonb,
    rightarg = jsonb,
    procedure = jsonb_concat
);
COMMENT ON OPERATOR pg_catalog.||(jsonb, jsonb) IS 'concatenate';