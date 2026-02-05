
DROP TYPE IF EXISTS pg_catalog._jsonpath;
DROP TYPE IF EXISTS pg_catalog.jsonpath;

SET LOCAL inplace_upgrade_next_system_object_oids = IUO_TYPE, 4072, 4073, b;
CREATE TYPE pg_catalog.jsonpath;

DROP FUNCTION IF EXISTS pg_catalog.jsonpath_in(cstring) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4051;
CREATE FUNCTION pg_catalog.jsonpath_in (
    cstring
) RETURNS jsonpath LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonpath_in';

DROP FUNCTION IF EXISTS pg_catalog.jsonpath_out(jsonpath) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4053;
CREATE FUNCTION pg_catalog.jsonpath_out (
    jsonpath
) RETURNS cstring LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonpath_out';

DROP FUNCTION IF EXISTS pg_catalog.jsonpath_send(jsonpath) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4054;
CREATE FUNCTION pg_catalog.jsonpath_send (
    jsonpath
) RETURNS bytea LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonpath_send';

DROP FUNCTION IF EXISTS pg_catalog.jsonpath_recv(internal) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4052;
CREATE FUNCTION pg_catalog.jsonpath_recv (
    internal
) RETURNS jsonpath LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonpath_recv';

CREATE TYPE pg_catalog.jsonpath (
    INPUT = jsonpath_in,
    OUTPUT = jsonpath_out,
    RECEIVE = jsonpath_recv,
    SEND = jsonpath_send,
    STORAGE = EXTENDED,
    CATEGORY = 'C'
);
COMMENT ON TYPE pg_catalog.jsonpath IS 'JSON path';

DROP FUNCTION IF EXISTS pg_catalog.jsonb_path_exists(target jsonb, path jsonpath, vars jsonb, silent boolean);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4055;
CREATE FUNCTION pg_catalog.jsonb_path_exists (
    target jsonb, path jsonpath,
    vars jsonb DEFAULT '{}'::jsonb,
    silent boolean DEFAULT false
) RETURNS boolean LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonb_path_exists';

DROP FUNCTION IF EXISTS pg_catalog.jsonb_path_query_first (target jsonb, path jsonpath, vars jsonb, silent boolean);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 4056;
CREATE FUNCTION pg_catalog.jsonb_path_query_first (
    target jsonb, path jsonpath,
    vars jsonb DEFAULT '{}'::jsonb,
    silent boolean DEFAULT false
) RETURNS jsonb LANGUAGE INTERNAL IMMUTABLE STRICT as 'jsonb_path_query_first';