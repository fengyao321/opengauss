DROP OPERATOR IF EXISTS pg_catalog.@>(jsonb, jsonb) cascade;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_GENERAL, 3246;
CREATE OPERATOR pg_catalog.@>(
leftarg = jsonb, rightarg = jsonb, procedure = jsonb_contains,
restrict = contsel, join = contjoinsel
);
COMMENT ON OPERATOR pg_catalog.@>(jsonb, jsonb) IS 'jsonb_contains';


DROP OPERATOR IF EXISTS pg_catalog.<@(jsonb, jsonb) cascade;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_GENERAL, 3250;
CREATE OPERATOR pg_catalog.<@(
leftarg = jsonb, rightarg = jsonb, procedure = jsonb_contained,
restrict = contsel, join = contjoinsel
);
COMMENT ON OPERATOR pg_catalog.<@(jsonb, jsonb) IS 'jsonb_contained';

