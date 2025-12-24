DROP CAST IF EXISTS (jsonb AS bool);
DROP CAST IF EXISTS (jsonb AS int1);
DROP CAST IF EXISTS (jsonb AS int2);
DROP CAST IF EXISTS (jsonb AS int4);
DROP CAST IF EXISTS (jsonb AS int8);
DROP CAST IF EXISTS (jsonb AS numeric);
DROP CAST IF EXISTS (jsonb AS float4);
DROP CAST IF EXISTS (jsonb AS float8);
DROP CAST IF EXISTS (jsonb AS "date");
DROP CAST IF EXISTS (jsonb AS time);
DROP CAST IF EXISTS (jsonb AS timestamp);

DROP FUNCTION IF EXISTS pg_catalog.jsonb_bool(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_int1(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_int2(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_int4(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_int8(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_numeric(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_float4(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_float8(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_date(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_time(jsonb);
DROP FUNCTION IF EXISTS pg_catalog.jsonb_timestamp(jsonb);

SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3365;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_bool(jsonb) RETURNS bool
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_bool';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3366;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_int1(jsonb) RETURNS int1
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_int1';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3367;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_int2(jsonb) RETURNS int2
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_int2';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3368;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_int4(jsonb) RETURNS int4
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_int4';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3369;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_int8(jsonb) RETURNS int8
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_int8';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3370;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_numeric(jsonb) RETURNS numeric
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_numeric';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3371;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_float4(jsonb) RETURNS float4
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_float4';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3372;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_float8(jsonb) RETURNS float8
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_float8';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3373;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_date(jsonb) RETURNS "date"
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_date';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3374;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_time(jsonb) RETURNS time
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_time';
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 3375;
CREATE OR REPLACE FUNCTION pg_catalog.jsonb_timestamp(jsonb) RETURNS timestamp
LANGUAGE internal STRICT IMMUTABLE AS 'jsonb_timestamp';

CREATE CAST (jsonb AS bool) WITH FUNCTION pg_catalog.jsonb_bool (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS int1) WITH FUNCTION pg_catalog.jsonb_int1 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS int2) WITH FUNCTION pg_catalog.jsonb_int2 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS int4) WITH FUNCTION pg_catalog.jsonb_int4 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS int8) WITH FUNCTION pg_catalog.jsonb_int8 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS numeric) WITH FUNCTION pg_catalog.jsonb_numeric (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS float4) WITH FUNCTION pg_catalog.jsonb_float4 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS float8) WITH FUNCTION pg_catalog.jsonb_float8 (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS "date") WITH FUNCTION pg_catalog.jsonb_date (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS time) WITH FUNCTION pg_catalog.jsonb_time (jsonb) AS ASSIGNMENT;
CREATE CAST (jsonb AS timestamp) WITH FUNCTION pg_catalog.jsonb_timestamp (jsonb) AS ASSIGNMENT;