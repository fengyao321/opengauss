create schema test_d_ddl;
set current_schema to test_d_ddl;

-- test drop trigger
create table animals (id int, name char(30));
create table food (id int, foodtype varchar(32), remark varchar(32), time_flag timestamp);

CREATE OR REPLACE FUNCTION insert_food_fun1 RETURNS TRIGGER AS
$$
BEGIN
    insert into food(id, foodtype, remark, time_flag) values (1, 'bamboo', 'healthy', now());
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER animals_trigger1 AFTER INSERT ON animals
FOR EACH ROW
EXECUTE PROCEDURE insert_food_fun1();

CREATE OR REPLACE FUNCTION insert_food_fun2 RETURNS TRIGGER AS
$$
BEGIN
    insert into food(id, foodtype, remark, time_flag) values (2, 'water', 'healthy', now());
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER animals_trigger2 AFTER INSERT ON animals
FOR EACH ROW
EXECUTE PROCEDURE insert_food_fun2();

select tgname from pg_trigger;
select count(*) from food;
insert into animals(id, name) values (1, 'panda');
select * from animals;
select count(*) from food;

delete from animals;
delete from food;
drop trigger animals_trigger1;
drop trigger if exists animals_trigger2;
select tgname from pg_trigger;

-- test <>
create table test1(id int, name varchar(10));
insert into test1 values(1, 'test1');
insert into test1 values(2, 'test2');
select * from test1 where id <> 3;
select * from test1 where id < > 3;
select * from test1 where id <    > 3;

-- test nvarchar(max)
create table test2(col1 int, col2 nvarchar(max), col3 nvarchar(50), col4 nvarchar,
col5 nvarchar2(max), col6 nvarchar2(50), col7 nvarchar2);

select * from information_schema.columns where table_name = 'test2' and table_schema = 'test_d_ddl' order by column_name;

insert into test2 values(1, 'abcd', 'abcd', 'a', 'abcd', 'abcd', 'a');
select * from test2;
insert into test2(col4) values('abcd'); --error, length is 1
insert into test2(col7) values('abcd'); --error, length is 1

create table test3(id nchar(max));

select '123'::nvarchar(max);
select '123'::nvarchar;
select '123'::nvarchar(1);
select '123'::nvarchar2(max);
select '123'::nvarchar2;
select '123'::nvarchar2(1);

select pg_typeof('123'::nvarchar2(max));
select pg_typeof('123'::nvarchar2);
select pg_typeof('123'::nvarchar2(1));
select pg_typeof('123'::nvarchar2(50));

create table test3(col1 nvarchar, col2 nvarchar(1), col3 nvarchar(50), col4 nvarchar(max));
create table test4(col1 nvarchar2, col2 nvarchar2(1), col3 nvarchar2(50), col4 nvarchar2(max));

\d test3
\d test4

\d+ test3
\d+ test4

select * from pg_get_tabledef('test3');
select * from pg_get_tabledef('test4');

create view view1 as select 'asdf'::nvarchar2(max);
create view view2 as select 'asdf'::nvarchar2(max)::nvarchar;
create view view3 as select 'asdf'::nvarchar2(max)::nvarchar(1);
\d+ view1
\d+ view2
\d+ view3
select * from pg_get_viewdef('view1');
select * from pg_get_viewdef('view2');
select * from pg_get_viewdef('view3');
select * from view1;
select * from view2;
select * from view3;

set d_format_behavior_compat_options = 'enable_sbr_identifier';
drop table if exists t1;
CREATE TABLE t1(id [int]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [int2]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [int4]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [int8]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [tinyint]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [smallint]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [bigint]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [binary_integer]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [float]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [float4]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [real]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [float8]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [double precision]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [binary_double]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [numeric]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [decimal]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [dec]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [bpchar]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [char]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [char](30));
\d+ t1
drop table t1;

CREATE TABLE t1(id [varchar]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [varchar](30));
\d+ t1
drop table t1;

CREATE TABLE t1(id [nvarchar2]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [nvarchar2](30));
\d+ t1
drop table t1;

CREATE TABLE t1(id [nvarchar]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [nvarchar](30));
\d+ t1
drop table t1;

CREATE TABLE t1(id [abstime]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [reltime]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [date]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [time]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [timestamptz]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [timestamp]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [timetz]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [bit]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [interval]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [uuid]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [bool]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [json]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [unknown]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [jsonb]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [clob]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [blob]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [money]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [name]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [oid]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [bytea]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [varbinary]);
\d+ t1
drop table t1;

CREATE TABLE t1(id [sql_variant]);
\d+ t1
drop table t1;

drop schema test_d_ddl cascade;
