create schema test_jsonb_typecast;
set current_schema to 'test_jsonb_typecast';

-- test: jsonb/json to bool
select cast('{"is_manager":true}'::json->'is_manager' as boolean) as is_manager; -- error
select cast('{"is_manager":true}'::jsonb->'is_manager' as boolean) as is_manager;

-- test: null
select jsonb_bool(NULL),jsonb_bool('');
select jsonb_bool('{"A":""}'::jsonb);

-- test: jsonb unquote and unescape
select '{"is_manager":"true"}'::jsonb->'is_manager' as origin, cast('{"is_manager":"true"}'::jsonb->'is_manager' as boolean) as unquote;
select '{"age":"34"}'::jsonb->'age' as origin, cast('{"age":"34"}'::jsonb->'age' as int) as unquote;
select '{"sign_in":"2025-12-31 8:01:05"}'::jsonb->'sign_in' as origin, cast ('{"sign_in":"2025-12-31 8:01:05"}'::jsonb->'sign_in' as timestamp);

-- test: jsonb to other types
select cast('{"A":true}'::jsonb->'A' as bool), cast('{"A":0}'::jsonb->'A' as bool);
select cast('{"A":123}'::jsonb->'A' as int1),cast('{"A":32767}'::jsonb->'A' as int2),
        cast('{"A":12345678}'::jsonb->'A' as int4),cast('{"A":1234567890}'::jsonb->'A' as int8);
select cast('{"A":123.456}'::jsonb->'A' as numeric),cast('{"A":123.456}'::jsonb->'A' as numeric(6,2)),
        cast('{"A":123.456}'::jsonb->'A' as float4),cast('{"A":123.456}'::jsonb->'A' as float8);
select cast('{"A":"2025-12-31 12:03:56.123005"}'::jsonb->'A' as pg_catalog.date),
        cast('{"A":"2025-12-31 12:03:56.123005"}'::jsonb->'A' as time(5)),
        cast('{"A":"2025-12-31 12:03:56.123005"}'::jsonb->'A' as timestamp(4));
-- test: use in query
create table tbl_jsb(jsb jsonb);
insert into tbl_jsb values('{"name":"Alice","age":25,"is_manager":"false","sign_in":"2025-12-31 7:58:59"}'),
('{"name":"Bob","age":"24","is_manager":false,"sign_in":"2025-12-31 8:02:00"}'),
('{"name":"Catherine","age":32,"is_manager":true,"sign_in":"2025-12-31 8:15:23"}'),
('{"name":"Djikstra","age":45,"is_manager":"true","sign_in":"2025-12-31 7:30:12"}');

select jsb->'name' AS name from tbl_jsb where cast(jsb->'is_manager' as boolean) = true;
select jsb->'name' AS name, cast(jsb->'age' as int1) as age from tbl_jsb where cast(jsb->'age' as int) > 30;
select jsb->'name' AS name, cast(jsb->'sign_in' as time) as last_sign_in from tbl_jsb where cast(jsb->'sign_in' as time)>'8:00:00';

-- test: cast assignment/implicity
select ('{"A":"true"}'::jsonb->'A') = ('true'::boolean) AS implicity;
select cast('{"A":"true"}'::jsonb->'A' AS bool) = ('true'::boolean) AS explicity;
create table tbl_ass_jsb(a bool);
insert into tbl_ass_jsb values('{"A":false}'::jsonb->'A'),('{"B":"true"}'::jsonb->'B');
select * from tbl_ass_jsb;

drop table tbl_ass_jsb;
drop table tbl_jsb;
reset current_schema;
drop schema test_jsonb_typecast cascade;