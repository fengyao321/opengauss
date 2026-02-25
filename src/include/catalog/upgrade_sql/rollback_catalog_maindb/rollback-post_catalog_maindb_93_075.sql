DROP OPERATOR IF EXISTS pg_catalog.@>(jsonb, jsonb) cascade;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_GENERAL, 3246;
CREATE OPERATOR pg_catalog.@>(
leftarg = jsonb, rightarg = jsonb, procedure = jsonb_contains,
restrict = contsel, join = contjoinsel
);
COMMENT ON OPERATOR pg_catalog.@>(jsonb, jsonb) IS 'contains';

set d_format_behavior_compat_options = 'enable_abs';
set b_format_behavior_compat_options = '';
set enable_set_variable_b_format = off;
DROP OPERATOR IF EXISTS pg_catalog.<@(jsonb, jsonb) cascade;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_GENERAL, 3250;
CREATE OPERATOR pg_catalog.<@(
leftarg = jsonb, rightarg = jsonb, procedure = jsonb_contained,
negator=operator(pg_catalog.@>),
restrict = contsel, join = contjoinsel
);
COMMENT ON OPERATOR pg_catalog.<@(jsonb, jsonb) IS 'contained';
