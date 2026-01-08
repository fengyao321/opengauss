create schema sharksysfunc;

set search_path to 'sharksysfunc';

CREATE TABLE students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    age INT DEFAULT 0,
    grade DECIMAL(5, 2)
);

CREATE VIEW student_grades AS
SELECT name, grade
FROM students;

CREATE OR REPLACE FUNCTION calculate_total_grade()
RETURNS DECIMAL(10, 2) AS $$
DECLARE
    total_grade DECIMAL(10, 2) := 0;
BEGIN
    SELECT SUM(grade) INTO total_grade FROM students;
    RETURN total_grade;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE insert_student(
    student_name VARCHAR(100),
    student_age INT,
    student_grade DECIMAL(5, 2)
) AS
BEGIN
    INSERT INTO students (name, age, grade) VALUES (student_name, student_age, student_grade);
END;
/

CREATE OR REPLACE FUNCTION update_total_grade()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Total grade updated: %', calculate_total_grade();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_total_grade
AFTER INSERT OR UPDATE OR DELETE ON students
FOR EACH STATEMENT EXECUTE PROCEDURE update_total_grade();

CREATE TYPE test_type1 AS (a int, b text);
create table test_serial(c1 serial);

create table check_table(c1 int, c2 int, CONSTRAINT constraint_name22 CHECK (c1 > 1));

select object_name(object_id('students', 'U'));
select object_name(object_id('students_pkey', 'PK'));
select object_name(object_id('student_grades', 'V'));
select object_name(object_id('calculate_total_grade', 'FN'));
select object_name(object_id('insert_student', 'P'));
select object_name(object_id('trigger_update_total_grade', 'TR'));
select object_name(object_id('sharksysfunc.students'));
select object_name(object_id('contrib_regression.sharksysfunc.students'));
select object_name(object_id('students', ''));
select object_name(object_id('students','s'));
select object_name(object_id('students','S'));
select object_name(object_id('students','u'));
select object_name(object_id('students',' u'));
select object_name(object_id('students','v'));
select object_name(object_id('students','u '));
select object_name(object_id('sys.objects'));
select object_name(object_id('test_type1'));
select object_name(object_id('test_serial'));
select object_name(object_id('test_serial_c1_seq'));
select object_name(0);
select object_name(1);
select object_name(-1);
select object_name(888);

-- cross database
DO $$
DECLARE
    database_oid oid;
	results nvarchar(128);
BEGIN
    SELECT oid INTO database_oid FROM pg_database WHERE datname = current_database();
    select object_name(object_id('students', 'U'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
    select object_name(object_id('students_pkey', 'PK'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
    select object_name(object_id('student_grades', 'V'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_name(object_id('calculate_total_grade', 'FN'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_name(object_id('insert_student', 'P'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_name(object_id('trigger_update_total_grade', 'TR'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
END $$;

select object_name(object_id('students_pkey', 'PK'), 11);
select object_name(object_id('student_grades', 'V'), 11);
select object_name(object_id('calculate_total_grade', 'FN'), 11);
select object_name(object_id('insert_student', 'P'), 11);
select object_name(object_id('trigger_update_total_grade', 'TR'), 11);

-- test input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100)
);

insert into test_type_table_column_name values (1, 1, 1, 1, 1, 1, 1, b'1', 1, 1, 1, 1, 1);

select 
    object_name(int1_col), 
	object_name(int2_col), 
	object_name(int4_col), 
	object_name(int8_col), 
	object_name(float4_col), 
	object_name(float8_col), 
	object_name(numeric_col), 
	object_name(bit1_col), 
	object_name(boolean_col),
	object_name(char_col), 
	object_name(varchar_col), 
	object_name(nvarchar_col), 
	object_name(varbinary_col)
from test_type_table_column_name;

-- sys.object_schema_name 函数
select object_schema_name(object_id('students', 'U'));
select object_schema_name(object_id('students_pkey', 'PK'));
select object_schema_name(object_id('student_grades', 'V'));
select object_schema_name(object_id('calculate_total_grade', 'FN'));
select object_schema_name(object_id('insert_student', 'P'));
select object_schema_name(object_id('trigger_update_total_grade', 'TR'));
select object_schema_name(object_id('sharksysfunc.students'));
select object_schema_name(object_id('contrib_regression.sharksysfunc.students'));
select object_schema_name(object_id('students', ''));
select object_schema_name(object_id('students','s'));
select object_schema_name(object_id('students','S'));
select object_schema_name(object_id('students','u'));
select object_schema_name(object_id('students',' u'));
select object_schema_name(object_id('students','v'));
select object_schema_name(object_id('students','u '));
select object_schema_name(object_id('sys.objects'));
select object_schema_name(0);
select object_schema_name(1);
select object_schema_name(-1);
select object_schema_name(888);


-- cross database
DO $$
DECLARE
    database_oid oid;
	results nvarchar(128);
BEGIN
    SELECT oid INTO database_oid FROM pg_database WHERE datname = current_database();
    select object_schema_name(object_id('students', 'U'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
    select object_schema_name(object_id('students_pkey', 'PK'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
    select object_schema_name(object_id('student_grades', 'V'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_schema_name(object_id('calculate_total_grade', 'FN'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_schema_name(object_id('insert_student', 'P'), database_oid) into results;
    RAISE NOTICE 'results: %', results;
	select object_schema_name(object_id('trigger_update_total_grade', 'TR'), database_oid) into results;
	RAISE NOTICE 'results: %', results;
END $$;

select object_schema_name(object_id('students_pkey', 'PK'), 11);
select object_schema_name(object_id('student_grades', 'V'), 11);
select object_schema_name(object_id('calculate_total_grade', 'FN'), 11);
select object_schema_name(object_id('insert_student', 'P'), 11);
select object_schema_name(object_id('trigger_update_total_grade', 'TR'), 11);



select 
    object_schema_name(int1_col), 
	object_schema_name(int2_col), 
	object_schema_name(int4_col), 
	object_schema_name(int8_col), 
	object_schema_name(float4_col), 
	object_schema_name(float8_col), 
	object_schema_name(numeric_col), 
	object_schema_name(bit1_col), 
	object_schema_name(boolean_col),
	object_schema_name(char_col), 
	object_schema_name(varchar_col), 
	object_schema_name(nvarchar_col), 
	object_schema_name(varbinary_col)
from test_type_table_column_name;


-- sys.object_definition 函数
select object_definition(object_id('students', 'U'));
select object_definition(object_id('students_pkey', 'PK'));
select object_definition(object_id('student_grades', 'V'));
select object_definition(object_id('calculate_total_grade', 'FN'));
select object_definition(object_id('insert_student', 'P'));
select object_definition(object_id('trigger_update_total_grade', 'TR'));
select object_definition(object_id('sharksysfunc.students'));
select object_definition(object_id('contrib_regression.sharksysfunc.students'));
select object_definition(object_id('students', ''));
select object_definition(object_id('students','s'));
select object_definition(object_id('students','S'));
select object_definition(object_id('students','u'));
select object_definition(object_id('students',' u'));
select object_definition(object_id('students','v'));
select object_definition(object_id('students','u '));
select object_definition(object_id('sys.objects'));
select object_definition(object_id('constraint_name22'));
select object_definition(0);
select object_definition(1);
select object_definition(-1);
select object_definition(888);

select 
    object_definition(int1_col), 
	object_definition(int2_col), 
	object_definition(int4_col), 
	object_definition(int8_col), 
	object_definition(float4_col), 
	object_definition(float8_col), 
	object_definition(numeric_col), 
	object_definition(bit1_col), 
	object_definition(boolean_col),
	object_definition(char_col), 
	object_definition(varchar_col), 
	object_definition(nvarchar_col), 
	object_definition(varbinary_col)
from test_type_table_column_name;



-- sys.objectpropertyex
select objectpropertyex(object_id('students', 'U'), 'BaseType');
select objectpropertyex(object_id('students_pkey', 'PK'), 'BaseType');
select objectpropertyex(object_id('student_grades', 'V'), 'BaseType');
select objectpropertyex(object_id('calculate_total_grade', 'FN'), 'BaseType');
select objectpropertyex(object_id('insert_student', 'P'), 'BaseType');
select objectpropertyex(object_id('trigger_update_total_grade', 'TR'), 'BaseType');
select objectpropertyex(object_id('sharksysfunc.students'), 'BaseType');
select objectpropertyex(object_id('contrib_regression.sharksysfunc.students'), 'BaseType');
select objectpropertyex(object_id('students', ''), 'BaseType');
select objectpropertyex(object_id('students','s'), 'BaseType');
select objectpropertyex(object_id('students','S'), 'BaseType');
select objectpropertyex(object_id('students','u'), 'BaseType');
select objectpropertyex(object_id('students',' u'), 'BaseType');
select objectpropertyex(object_id('students','v'), 'BaseType');
select objectpropertyex(object_id('students','u '), 'BaseType');
select objectpropertyex(object_id('sys.objects'), 'BaseType');
select objectpropertyex(0, 'BaseType');
select objectpropertyex(1, 'BaseType');
select objectpropertyex(-1, 'BaseType');
select objectpropertyex(888, 'BaseType');
select objectpropertyex(object_id('students', 'U'), 'BASETYPE');
select objectpropertyex(object_id('students', 'U'), 'basetype');
select objectpropertyex(object_id('students', 'U'), 'BASETYPE       ');
select objectpropertyex(object_id('students', 'U'), 'BaseType');
select objectpropertyex(object_id('students', 'U'), 'BaseType');
select objectpropertyex(object_id('students', 'U'), 'amaoagou');
select objectpropertyex(NULL, 'BASETYPE');
select objectpropertyex(object_id('students', 'U'), NULL);

select 
    objectpropertyex(int1_col, 'BaseType'), 
	objectpropertyex(int2_col, 'BaseType'), 
	objectpropertyex(int4_col, 'BaseType'), 
	objectpropertyex(int8_col, 'BaseType'), 
	objectpropertyex(float4_col, 'BaseType'), 
	objectpropertyex(float8_col, 'BaseType'), 
	objectpropertyex(numeric_col, 'BaseType'), 
	objectpropertyex(bit1_col, 'BaseType'), 
	objectpropertyex(char_col, 'BaseType'), 
	objectpropertyex(varchar_col, 'BaseType'), 
	objectpropertyex(nvarchar_col,'BaseType'), 
	objectpropertyex(varbinary_col, 'BaseType')
from test_type_table_column_name;

select 
    objectpropertyex(object_id('students', 'U'), int1_col), 
	objectpropertyex(object_id('students', 'U'), int2_col), 
	objectpropertyex(object_id('students', 'U'), int4_col), 
	objectpropertyex(object_id('students', 'U'), int8_col), 
	objectpropertyex(object_id('students', 'U'), float4_col), 
	objectpropertyex(object_id('students', 'U'), float8_col), 
	objectpropertyex(object_id('students', 'U'), numeric_col), 
	objectpropertyex(object_id('students', 'U'), bit1_col), 
	objectpropertyex(object_id('students', 'U'), char_col), 
	objectpropertyex(object_id('students', 'U'), varchar_col), 
	objectpropertyex(object_id('students', 'U'), nvarchar_col), 
	objectpropertyex(object_id('students', 'U'), varbinary_col)
from test_type_table_column_name;


-- permission
create user u_no_permission identified by 'Test@123';
alter session set session authorization u_no_permission password 'Test@123';
select objectpropertyex(object_id('students', 'U'), 'BaseType');
RESET SESSION AUTHORIZATION;
drop user u_no_permission cascade;

drop TRIGGER trigger_update_total_grade;
drop view sharksysfunc.student_grades;
drop function if exists calculate_total_grade();
drop function if exists insert_student(character varying,integer,numeric);
drop function if exists update_total_grade();
drop type if exists test_type1;
drop table if exists test_serial;
drop table if exists test_type_table_column_name;
drop table if exists students;
drop table if exists check_table;



--  sys.col_length
CREATE TABLE col_length_t1(c1 VARCHAR(40), c2 NVARCHAR(40) );  
SELECT COL_LENGTH('col_length_t1','c1') AS 'VarChar',   COL_LENGTH('col_length_t1','c2') AS 'NVarChar';   --expect 40 80


CREATE TABLE col_length_t2(
    col_char CHAR(20),
    col_varchar VARCHAR(30),
    col_varbinary VARBINARY(40)
);

SELECT COL_LENGTH('col_length_t2', 'col_char');
SELECT COL_LENGTH('col_length_t2', 'col_varchar');
SELECT COL_LENGTH('col_length_t2', 'col_varbinary');
SELECT COL_LENGTH('sharksysfunc.col_length_t2', 'col_char');
SELECT COL_LENGTH('sharksysfunc.col_length_t2', 'col_varchar');
SELECT COL_LENGTH('sharksysfunc.col_length_t2', 'col_varbinary');


create table test_type_table_column_name
(
    int1_col tinyint,
    int2_col smallint,
    int4_col integer,
    int8_col bigint,
    float4_col float4,
    float8_col float8,
    numeric_col decimal(20, 6),
    bit1_col bit(1),
    datetime_col timestamp without time zone,
    smalldatetime_col smalldatetime,
    date_col date,
    time_col time,
    boolean_col boolean,
    char_col char(100),
    varchar_col varchar(100), 
    nvarchar_col nvarchar(10),
    varbinary_col varbinary(100),
    text_col text,
    col_char_10 CHAR(10),
    col_varchar_20 VARCHAR(20),
    col_varbinary_15 VARBINARY(15),
    col_nchar_8 NCHAR(8),
    col_nvarchar_16 NVARCHAR(16),
    col_sql_variant SQL_VARIANT,
    col_varcharmax VARCHAR(255),
    col_nvarcharmax NVARCHAR(255),
    col_varbinarymax VARBINARY(255),
    col_bit BIT,
    col_decimal_1 DECIMAL(10,5),
    col_numeric_1 NUMERIC(3,0)
);

insert into test_type_table_column_name values (1, 1, 1, 1, 1, 1, 1, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10',
  1, '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1', '1');

SELECT COL_LENGTH('test_type_table_column_name', 'int1_col');
SELECT COL_LENGTH('test_type_table_column_name', 'int2_col');
SELECT COL_LENGTH('test_type_table_column_name', 'int4_col');
SELECT COL_LENGTH('test_type_table_column_name', 'int8_col');
SELECT COL_LENGTH('test_type_table_column_name', 'float4_col');
SELECT COL_LENGTH('test_type_table_column_name', 'float8_col');
SELECT COL_LENGTH('test_type_table_column_name', 'numeric_col');
SELECT COL_LENGTH('test_type_table_column_name', 'bit1_col');
SELECT COL_LENGTH('test_type_table_column_name', 'datetime_col');
SELECT COL_LENGTH('test_type_table_column_name', 'smalldatetime_col');
SELECT COL_LENGTH('test_type_table_column_name', 'date_col');
SELECT COL_LENGTH('test_type_table_column_name', 'time_col');
SELECT COL_LENGTH('test_type_table_column_name', 'boolean_col');
SELECT COL_LENGTH('test_type_table_column_name', 'char_col');
SELECT COL_LENGTH('test_type_table_column_name', 'varchar_col');
SELECT COL_LENGTH('test_type_table_column_name', 'nvarchar_col');
SELECT COL_LENGTH('test_type_table_column_name', 'varbinary_col');
SELECT COL_LENGTH('test_type_table_column_name', 'text_col');
SELECT COL_LENGTH('test_type_table_column_name', 'col_char_10');
SELECT COL_LENGTH('test_type_table_column_name', 'col_varchar_20');
SELECT COL_LENGTH('test_type_table_column_name', 'col_varbinary_15');
SELECT COL_LENGTH('test_type_table_column_name', 'col_nchar_8');
SELECT COL_LENGTH('test_type_table_column_name', 'col_nvarchar_16');
SELECT COL_LENGTH('test_type_table_column_name', 'col_sql_variant');
SELECT COL_LENGTH('test_type_table_column_name', 'col_varcharmax');
SELECT COL_LENGTH('test_type_table_column_name', 'col_nvarcharmax');
SELECT COL_LENGTH('test_type_table_column_name', 'col_varbinarymax');
SELECT COL_LENGTH('test_type_table_column_name', 'col_bit');
SELECT COL_LENGTH('test_type_table_column_name', 'col_decimal_1');
SELECT COL_LENGTH('test_type_table_column_name', 'col_numeric_1');


CREATE TYPE compfoo1 AS (f1 int);
CREATE TYPE compfoo2 AS (f1 float8);

CREATE TABLE col_length_t3(
    col_compfoo1 compfoo1,
    col_compfoo2 compfoo2
);

SELECT COL_LENGTH('col_length_t3', 'col_compfoo1');
SELECT COL_LENGTH('col_length_t3', 'col_compfoo2');

SELECT COL_LENGTH('col_length_t3', 'compfoo1');
SELECT COL_LENGTH('col_length_t3', 'compfoo2');

-- diff input type
SELECT COL_LENGTH('test_type_table_column_name'::varchar, 'int1_col'::varchar);
SELECT COL_LENGTH('test_type_table_column_name'::char(10), 'int1_col'::char(10));

SELECT COL_LENGTH(int1_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(int2_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(int4_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(int8_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(float4_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(float8_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(numeric_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(datetime_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(smalldatetime_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(date_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(time_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(char_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(varchar_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(nvarchar_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(varbinary_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(text_col, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH(col_nvarchar_16, 'test1') from test_type_table_column_name;
SELECT COL_LENGTH('test1', int1_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', int2_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', int4_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', int8_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', float4_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', float8_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', numeric_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', datetime_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', smalldatetime_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', date_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', time_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', char_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', varchar_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', nvarchar_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', varbinary_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', text_col) from test_type_table_column_name;
SELECT COL_LENGTH('test1', col_nvarchar_16) from test_type_table_column_name;

drop table if exists test_type_table_column_name;

-- sys.COL_NAME
create table test_colname_1(c1 int, c2 int);
select COL_NAME(OBJECT_ID('test_colname_1'), -1);
select COL_NAME(OBJECT_ID('test_colname_1'), 0);
select COL_NAME(OBJECT_ID('test_colname_1'), 1);
select COL_NAME(OBJECT_ID('test_colname_1'), 2);
select COL_NAME(OBJECT_ID('test_colname_1'), 3);
select COL_NAME(OBJECT_ID('test_colname_1'), 4);
select COL_NAME(OBJECT_ID('test_colname_1'), 'abc');
select COL_NAME(OBJECT_ID('test_colname_1'), NULL);
select COL_NAME(OBJECT_ID('test_colname_1'), 4);
select COL_NAME(OBJECT_ID('amapagou'), 4);
select COL_NAME('0x1A', 3);
select COL_NAME(7, 'column_name');
select COL_NAME('0x2F', 'another_column');
select COL_NAME('0xAB', '0x8C');
select COL_NAME('sample_table', 'some_column');


-- diff input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100)
);

insert into test_type_table_column_name values (1, 1, 1, 1, 1, 1, 1, b'1', 1, 1, 1, 1, 1);


select 
  COL_NAME(int1_col, 1),
  COL_NAME(int2_col, 1),
  COL_NAME(int4_col, 1),
  COL_NAME(int8_col, 1),
  COL_NAME(float4_col, 1),
  COL_NAME(float8_col, 1),
  COL_NAME(numeric_col, 1),
  COL_NAME(bit1_col, 1),
  COL_NAME(char_col, 1),
  COL_NAME(varchar_col, 1),
  COL_NAME(nvarchar_col, 1),
  COL_NAME(varbinary_col, 1)
from test_type_table_column_name;


select 
  COL_NAME(1, int1_col),
  COL_NAME(1, int2_col),
  COL_NAME(1, int4_col),
  COL_NAME(1, int8_col),
  COL_NAME(1, float4_col),
  COL_NAME(1, float8_col),
  COL_NAME(1, numeric_col),
  COL_NAME(1, bit1_col),
  COL_NAME(1, char_col),
  COL_NAME(1, varchar_col),
  COL_NAME(1, nvarchar_col),
  COL_NAME(1, varbinary_col)
from test_type_table_column_name; 

drop table if exists test_type_table_column_name;

create table test11(c1 int, c2 int, c3 int, c4 int, c5 int);
select object_id('test11');
select COL_NAME(object_id('test11'), 1);
alter table test11 drop column c1;
select COL_NAME(object_id('test11'), 1);
select COL_NAME(object_id('test11'), 2);
drop table test11;


-- sys.columnproperty
CREATE TABLE t_column_property(
  cp1 CHAR(1) NOT NULL, 
  cp2 CHAR(129), 
  cp3 CHAR(4000) NOT NULL,
  cp4 VARCHAR(1),
  cp5 VARCHAR(129) NOT NULL,
  cp6 VARCHAR(4000),
  cp7 INT,
  cp8 INT NOT NULL);

SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'charmaxlen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'allowsnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'allowsnull');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'iscomputed');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'iscomputed');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'columnid');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'columnid');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'ishidden');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'ishidden');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'isidentity');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'ordinal');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'ordinal');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'precision');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'scale');  
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp2', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp3', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp5', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp7', 'amaoagou');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp8', 'amaoagou');    

CREATE TABLE t_column_property2 (cp1 INT IDENTITY, cp2 VARCHAR(200), cp3 INT);
SELECT sys.columnproperty(OBJECT_ID('t_column_property2'), 'cp1', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property2'), 'cp2', 'isidentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property2'), 'cp3', 'isidentity');


CREATE TABLE t_column_property3 (cp1 float(4), cp2 float(8), cp3 numeric(20, 10), cp5 int2, cp6 int4, cp7 int8);
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp1', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp2', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp3', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp4', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp5', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp6', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp7', 'precision');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp1', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp2', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp3', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp4', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp5', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp6', 'scale');
SELECT sys.columnproperty(OBJECT_ID('t_column_property3'), 'cp7', 'scale');

SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1', 'allowsnull ');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp1 ', 'allowsnull  ');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cP1', 'AllowSnull');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'Cp4', 'CharmaxLen ');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp25', 'IsIdentity');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp6', ' charmaxlen ');

ALTER TABLE t_column_property DROP COLUMN cp4;
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'cp4', 'CharmaxLen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'Cp4', 'CharmaxLen');
SELECT sys.columnproperty(OBJECT_ID('t_column_property'), 'Cp4', 'CharmaxLen ');

drop table col_length_t1;
drop table col_length_t2;
drop table col_length_t3;
drop table test_colname_1;
drop table t_column_property;
drop table t_column_property2;
drop table t_column_property3;
drop TYPE compfoo1;
drop TYPE compfoo2;


-- sys.year 函数
select YEAR(NULL);
SELECT YEAR('2010-04-30T01:01:01.1234567-07:00');
SELECT YEAR(0);   -- expect 1900
SELECT YEAR(1);   -- expect 1900
SELECT YEAR(2020);   -- expect 1905
SELECT YEAR('2025-10-10');
SELECT YEAR('2025/10/10');
SELECT YEAR('2025.10.10');
SELECT YEAR('20251010');
SELECT YEAR('2025-10-10 14:30:59');
SELECT YEAR('2025-10-10 23:59:59.999');
SELECT YEAR('2025-10-10 00:00:00.000');
SELECT YEAR(CAST('0001-01-01' AS DATE));
SELECT YEAR(CAST('1753-01-01' AS timestamp));
SELECT YEAR(CAST('1900-01-01' AS SMALLDATETIME));
SELECT YEAR(CAST('9999-12-31' AS DATE));
SELECT YEAR(CAST('9999-12-31 23:59:59.997' AS timestamp));
SELECT YEAR(CAST('2079-06-06' AS SMALLDATETIME));
SELECT YEAR('2020-02-29');
SELECT YEAR('2019-02-28');
SELECT YEAR('1900-02-28');
SELECT YEAR('1900-01-01');
SELECT YEAR('0001-01-01');
SELECT YEAR(CURRENT_TIMESTAMP);
SELECT YEAR('abc');  -- error expect
SELECT YEAR(333);

-- different data type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10');

select year(int1_col), year(int2_col), year(int4_col), year(int8_col), year(float4_col), year(float8_col), year(numeric_col), year(bit1_col), year(datetime_col), year(smalldatetime_col), year(date_col), year(boolean_col), year(char_col), year(varchar_col), year(nvarchar_col), year(text_col) from test_type_table_column_name;

drop table if exists test_type_table_column_name;

-- sys.month
SELECT MONTH('2007-04-30T01:01:01.1234567');   -- expect:  4
SELECT MONTH(0);                               -- expect:  1
SELECT MONTH(88);                              -- expect:  3
SELECT MONTH('2023-05-15');                    -- expect:  5
SELECT MONTH('2023/12/31');                    -- expect:  12
SELECT MONTH('2023-01-01');                    -- expect:  1
SELECT MONTH('2023-08-20 14:30:45');           -- expect:  8
SELECT MONTH('2023-02-28 23:59:59');           -- expect:  2
SELECT MONTH('03/10/2023');                    -- expect:  3
SELECT MONTH('2023年06月01日');                -- expect:  error
SELECT MONTH('2023-01-01');                    -- expect:  1
SELECT MONTH('2023-12-31');                    -- expect:  12
SELECT MONTH('2023-01-31');                    -- expect:  1
SELECT MONTH('2023-12-01');                    -- expect:  12
SELECT MONTH('2024-02-29');                    -- expect:  2
SELECT MONTH('2023-02-28');                    -- expect:  2
SELECT MONTH('1753-01-01');                    -- expect:  1
SELECT MONTH('9999-12-31');                    -- expect:  12
SELECT MONTH(NULL);                            -- expect:  NULL
SELECT MONTH('2023-13-01');                    -- expect:  error
SELECT MONTH('2023-02-30');                    -- expect:  error
SELECT MONTH('abc');                           -- expect:  error

-- different input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025-10-10', '2025-10-10', '2025-10-10', '2025', '2025-10-10');

SELECT 
    MONTH(int1_col),
	MONTH(int2_col),
	MONTH(int4_col),
	MONTH(int8_col),
	MONTH(float4_col),
	MONTH(float8_col),
	MONTH(numeric_col),
	MONTH(bit1_col),
	MONTH(datetime_col),
	MONTH(smalldatetime_col),
	MONTH(date_col),
	MONTH(time_col),
	MONTH(char_col),
	MONTH(varchar_col),
	MONTH(nvarchar_col),
	MONTH(text_col)
from test_type_table_column_name;

drop table if exists test_type_table_column_name;

-- sys.day
SELECT day('2007-04-30T01:01:01.1234567');   -- expect:  30
SELECT day(0);                               -- expect:  1
SELECT day(88);                              -- expect:  30

SELECT day('2023-05-15');                    -- expect:  15
SELECT day('2023/12/31');                    -- expect:  31
SELECT day('2023-01-01');                    -- expect:  1

SELECT day('2023-08-20 14:30:45');           -- expect:  20
SELECT day('2023-02-28 23:59:59');           -- expect:  28
SELECT day('03/10/2023');                    -- expect:  10

SELECT day('2023年06月01日');                -- expect:  error
SELECT day('2023-01-01');                    -- expect:  1
SELECT day('2023-12-31');                    -- expect:  31

SELECT day('2023-01-31');                    -- expect:  31
SELECT day('2023-12-01');                    -- expect:  1
SELECT day('2024-02-29');                    -- expect:  29

SELECT day('2023-02-28');                    -- expect:  28
SELECT day('1753-01-01');                    -- expect:  1
SELECT day('9999-12-31');                    -- expect:  31

SELECT day(NULL);                            -- expect:  NULL
SELECT day('2023-13-01');                    -- expect:  error
SELECT day('2023-02-30');                    -- expect:  error

SELECT day('abc');                           -- expect:  error


-- different input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025-10-10', '2025-10-10', '2025-10-10', '2025', '2025-10-10');

SELECT 
    day(int1_col),
	day(int2_col),
	day(int4_col),
	day(int8_col),
	day(float4_col),
	day(float8_col),
	day(numeric_col),
	day(bit1_col),
	day(datetime_col),
	day(smalldatetime_col),
	day(date_col),
	day(char_col),
	day(varchar_col),
	day(nvarchar_col),
	day(text_col)
from test_type_table_column_name;

drop table if exists test_type_table_column_name;


-- sys.isdate
SELECT ISDATE('2023-10-05');          -- 1
SELECT ISDATE('2023/10/05');          -- 1
SELECT ISDATE('2023.10.05');          -- 1
		 
SELECT ISDATE('10-05-2023');          -- 1
SELECT ISDATE('10/05/2023');          -- 1
SELECT ISDATE('10.05.2023');          -- 1
		 
SELECT ISDATE('05-10-2023');          -- 1
SELECT ISDATE('05/10/2023');          -- 1
SELECT ISDATE('05.10.2023');          -- 1
		 
SELECT ISDATE('2023-10-05 14:30:00');       -- 1
SELECT ISDATE('2023-10-05T14:30:00');       -- 1
SELECT ISDATE('2023/10/05 14:30:00.123');   -- 1
		 
SELECT ISDATE('10-05-2023 09:00 AM');       -- 1
SELECT ISDATE('10/05/2023 03:30 PM');       -- 1
		 
SELECT ISDATE('14:30:00');                  -- 1 
SELECT ISDATE('09:00 AM');                  -- 1 
SELECT ISDATE('03:30 PM');                  -- 1 
SELECT ISDATE('14:30:00.123');              -- 1 
		 
SELECT ISDATE('20231005');                       -- 1
SELECT ISDATE('2023-10-05 14:30');               -- 1
SELECT ISDATE('2023-10-05 14:30:00.1234567');    -- 0
		 
SELECT ISDATE('2023-13-05');          -- 0
SELECT ISDATE('2023-10-32');          -- 0
SELECT ISDATE('2023/13/05');          -- 0
		 
SELECT ISDATE('2023/10/32');          -- 0
SELECT ISDATE('2023-02-29');          -- 0
SELECT ISDATE('2020-02-30');          -- 0
		 
SELECT ISDATE('2023-10-05 14:60:00');   -- 0
SELECT ISDATE('2023-10-05 25:00:00');   -- 0
SELECT ISDATE('2023-10-05 14:30:60');   -- 0 
		 
SELECT ISDATE('2023-10-05 14:30:00.12345678');   -- 0
SELECT ISDATE('2023/10/05 14:30:00,123');        -- 0
SELECT ISDATE('2023年10月05日');                 -- 0
		 
SELECT ISDATE('2023-10-05 下午3点30分');        -- 0
SELECT ISDATE('abc');                           -- 0
SELECT ISDATE('2023-10-05a');                   -- 0
		 
SELECT ISDATE('2023-10-05 14:30:00a');            -- 0
SELECT ISDATE('2023-10-');                        -- 0
SELECT ISDATE('10-05-2023 14:30:00 PM');          -- 1 
		 
SELECT ISDATE('1752-09-14');                      -- 0
SELECT ISDATE('1753-01-00');                      -- 0
SELECT ISDATE('9999-12-31 23:59:59');             -- 1
		 
SELECT ISDATE('9999-12-31 24:00:00');             -- 0
SELECT ISDATE('10000-01-01');                     -- 0
		 
SELECT ISDATE(20231005);    -- 1
SELECT ISDATE(20231305);    -- 0
SELECT ISDATE(20231032);    -- 0
		 
SELECT ISDATE(143000);      -- 0
SELECT ISDATE(146000);      -- 0

-- sys.eomonth
select EOMONTH('12/1/2024'::date);           --expect: 2024-12-31
select EOMONTH('12/1/2024'::varchar);        --expect: 2024-12-31
select EOMONTH('12/1/2024'::date, 1);        --expect: 2025-01-31
select EOMONTH('12/1/2024'::date, -1);       --expect: 2024-11-30

SELECT EOMONTH('2023-03-15');                --expect: 2023-03-31
SELECT EOMONTH('2023-04-15');                --expect: 2023-04-30
SELECT EOMONTH('2023-02-10');                --expect: 2023-02-28
SELECT EOMONTH('2024-02-10');                --expect: 2024-02-29
SELECT EOMONTH('2023-05-01');                --expect: 2023-05-31
SELECT EOMONTH('2023-06-30');                --expect: 2023-06-30
SELECT EOMONTH('2023-07-20 14:30:00');       --expect: 2023-07-31
SELECT EOMONTH('1753-01-01');                --expect: 1753-01-31
SELECT EOMONTH('9999-12-31');                --expect: 9999-12-31
SELECT EOMONTH('2000-02-15');                --expect: 2000-02-29
SELECT EOMONTH('2023-12-05');                --expect: 2023-12-31
SELECT EOMONTH('2023-12-05');                --expect: 2023-12-31
SELECT EOMONTH('2023-11-10', 2);             --expect: 2024-01-31
SELECT EOMONTH('2024-01-10', -1);            --expect: 2023-12-31
SELECT EOMONTH('2023-05-20', 100);           --expect: 2031-09-30
SELECT EOMONTH('2023-05-20', -100);          --expect: 2015-01-31
SELECT EOMONTH('2023/13/01');                --expect: error
SELECT EOMONTH('2023-02-30');                --expect: error
SELECT EOMONTH('hello world');               --expect: error
SELECT EOMONTH(20230515);                    --expect: error
SELECT EOMONTH(NULL);                        --expect: NULL
SELECT EOMONTH('2023-05-15', 1.5);           --expect: 2023-06-30
SELECT EOMONTH('2023-05-15', 1.6);           --expect: 2023-06-30
SELECT EOMONTH('2023-05-15', -1.5);           --expect: 2023-04-30
SELECT EOMONTH('2023-05-15', -1.6);           --expect: 2023-04-30
SELECT EOMONTH('2023-05-15', -2.1);           --expect: 2023-03-31
SELECT EOMONTH('1753-01-01', -1);            --expect: 1752-12-31
SELECT EOMONTH('9999-12-31', 1);             --expect: error


-- different input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025', '2025', '2025', '2025', '2025');

SELECT EOMONTH(datetime_col, 2) from test_type_table_column_name; 
SELECT EOMONTH(smalldatetime_col, 2) from test_type_table_column_name; 
SELECT EOMONTH(date_col, 2) from test_type_table_column_name; 
SELECT EOMONTH(datetime_col, 2.2) from test_type_table_column_name; 
SELECT EOMONTH(smalldatetime_col, 2.2) from test_type_table_column_name; 
SELECT EOMONTH(date_col, 2.2) from test_type_table_column_name; 


drop table if exists test_type_table_column_name;

-- sys.sysdatetime
select sysdatetime();

-- sys.square
SELECT square(CAST(12 AS int));
SELECT square(CAST(12.4 AS float));
SELECT square(CAST(12.4 AS real));
SELECT square(CAST(12.4 AS bigint));
SELECT square(CAST(12.4 AS smallint));
SELECT square(CAST(12.4 AS tinyint));
SELECT square(CAST(12.4 AS decimal));
SELECT square(CAST(12.4 AS numeric));

create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '10', '10', '10', '10', '10');

SELECT 
    square(int1_col),
	square(int2_col),
	square(int4_col),
	square(int8_col),
	square(float4_col),
	square(float8_col),
	square(numeric_col),
	square(bit1_col),
	square(char_col),
	square(varchar_col),
	square(nvarchar_col),
	square(text_col)
from test_type_table_column_name;

drop table if exists test_type_table_column_name;

--  sys.isnumeric
CREATE TABLE test_is_numeric_table (
    bigint_type bigint,
    int_type int,
    smallint_type smallint,
    tinyint_type tinyint,
    bit_type bit,
    decimal_type decimal(5,2),
    numeric_type numeric(10,5),
    float_type float,
    real_type real,
    money_type money,
    float8_type float8,
    boolean_col boolean,
    char_col char(100),
    varchar_col varchar(100), 
    nvarchar_col nvarchar(10),
    varbinary_col varbinary(100),
    text_col text
);

INSERT INTO test_is_numeric_table VALUES (
    9223372036854775806,
    45000,
    -32767,
    100,
    b'1',
    123,
    12345.12,
    1.79E+30,
    -3.40E+38, 
    237891.22,
    77.58,
	1,  -- bool
	'1',
	'1',
	'1',
	'1',
	'1'
);

SELECT ISNUMERIC(bigint_type) FROM test_is_numeric_table;       --expect: 1
SELECT ISNUMERIC(int_type) FROM test_is_numeric_table;          --expect: 1
SELECT ISNUMERIC(smallint_type) FROM test_is_numeric_table;     --expect: 1
SELECT ISNUMERIC(tinyint_type) FROM test_is_numeric_table;      --expect: 1
SELECT ISNUMERIC(bit_type) FROM test_is_numeric_table;          --expect: 1
SELECT ISNUMERIC(decimal_type) FROM test_is_numeric_table;      --expect: 1
SELECT ISNUMERIC(numeric_type) FROM test_is_numeric_table;      --expect: 1
SELECT ISNUMERIC(float_type) FROM test_is_numeric_table;        --expect: 1
SELECT ISNUMERIC(real_type) FROM test_is_numeric_table;         --expect: 1
SELECT ISNUMERIC(money_type) FROM test_is_numeric_table;        --expect: 1
SELECT ISNUMERIC(float8_type) FROM test_is_numeric_table;       --expect: 1
SELECT ISNUMERIC(boolean_col) FROM test_is_numeric_table;       --expect: 1
SELECT ISNUMERIC(char_col) FROM test_is_numeric_table;          --expect: 1
SELECT ISNUMERIC(varchar_col) FROM test_is_numeric_table;       --expect: 1
SELECT ISNUMERIC(nvarchar_col) FROM test_is_numeric_table;      --expect: 1
SELECT ISNUMERIC(varbinary_col) FROM test_is_numeric_table;     --expect: 1
SELECT ISNUMERIC(text_col) FROM test_is_numeric_table;          --expect: 1

select isnumeric(1234567890);       --expect: 1
select isnumeric('28903');          --expect: 1
select isnumeric('+');              --expect: 1
select isnumeric('+ ');             --expect: 1

select isnumeric('$24,23.43');       --expect: 1
select isnumeric('+ 1');             --expect: 1
select isnumeric('$+1.1234');        --expect: 1

select isnumeric('+$1.1234');        --expect: 1
select isnumeric(' $ + 1.1234');     --expect: 1
select isnumeric(' + $ 1.1234');     --expect: 1

select isnumeric('abcdefghijklmnop');   --expect: 0
select isnumeric('24.89.43');           --expect: 0
select isnumeric('24,2.3.43');          --expect: 0

select isnumeric('+-');                 --expect: 0
select isnumeric('23$');                --expect: 0
select isnumeric(null);                 --expect: 0

select isnumeric(' ');                  --expect: 0
select isnumeric('1 .1234');            --expect: 0
select isnumeric('+1 .1234');           --expect: 0

select isnumeric('$1 .1234');                                       --expect: 0
select isnumeric('9999999999999999999999999999999999999999');       --expect: 1
select isnumeric('10000000000000000000000000000000000000000');      --expect: 1

select isnumeric('-9999999999999999999999999999999999999999');      --expect: 1
select isnumeric('999999999999999999999999999999999999999.99999');  --expect: 1

select isnumeric('1' + REPLICATE('0', 38));      --expect: 1
select isnumeric('1' + REPLICATE('0', 100));     --expect: 1
select isnumeric('0.' + REPLICATE('9', 38));     --expect: 1

select isnumeric('1E+38');     --expect: 1
select isnumeric('1E+100');    --expect: 1
select isnumeric('1E-100');    --expect: 1

select isnumeric('abc');        --expect: 0
select isnumeric('123abc');     --expect: 0
select isnumeric('abc123');     --expect: 0

select isnumeric('12.34.56');     --expect: 0
select isnumeric('12,34,56');     --expect: 1
select isnumeric('$123$456');     --expect: 0
select isnumeric('123..456');     --expect: 0

select isnumeric('++123');        --expect: 0
select isnumeric('--123');        --expect: 0
select isnumeric('+-123');        --expect: 0

select isnumeric('123-');           --expect: 0
select isnumeric('123+');           --expect: 0
select isnumeric('123.456.789');    --expect: 0

select isnumeric('1,23,456');        --expect: 1
select isnumeric('1.2e3.4');         --expect: 0
select isnumeric('1.2e');            --expect: 0

select isnumeric('e1.2');            --expect: 0
select isnumeric('1.2D');            --expect: 0
select isnumeric(CAST(1.79E+308 AS varchar(50)));     --expect: 1
select isnumeric(CAST(POWER(10, 3) AS varchar(50)));  --expect: 1

drop table test_is_numeric_table;


--sys.SQL_VARIANT_PROPERTY
select SQL_VARIANT_PROPERTY(cast(cast('2020-10-20 09:00:00' as smalldatetime) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('$123.123' as money) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('256' as smallint) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('255' as tinyint) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('a' as nvarchar) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('a' as varchar) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('a' as nchar(1)) as sql_variant), 'BaseType');
select SQL_VARIANT_PROPERTY(cast(cast('a' as char(1)) as sql_variant), 'BaseType');

create table sqlvariant_test_1 (testcase varchar(50), v sql_variant);
insert into sqlvariant_test_1 (testcase, v) values ('smalldatetime basic', cast('2020-10-05 09:00:00' as smalldatetime));
insert into sqlvariant_test_1 (testcase, v) values ('date basic', cast('0001-01-01' as date));
insert into sqlvariant_test_1 (testcase, v) values ('time basic', cast('00:00:00' as time));
insert into sqlvariant_test_1 (testcase, v) values ('time basic w/ typmod', cast('00:00:00' as time(3)));
insert into sqlvariant_test_1 (testcase, v) values ('float basic', cast(3.1415926 as float(53)));
insert into sqlvariant_test_1 (testcase, v) values ('real basic', cast(3.1415926 as real));
insert into sqlvariant_test_1 (testcase, v) values ('numeric basic', cast(93.1415926 as numeric(4,2)));
insert into sqlvariant_test_1 (testcase, v) values ('numeric basic2', cast(93.1415926 as numeric(5,1)));
insert into sqlvariant_test_1 (testcase, v) values ('money basic', cast('100.123' as money));
insert into sqlvariant_test_1 (testcase, v) values ('bigint basic', cast(2147483648 as bigint));
insert into sqlvariant_test_1 (testcase, v) values ('int basic', cast(2147483647 as int));
insert into sqlvariant_test_1 (testcase, v) values ('smallint basic', cast(32767 as smallint));
insert into sqlvariant_test_1 (testcase, v) values ('tinyint basic', cast(255 as tinyint));
insert into sqlvariant_test_1 (testcase, v) values ('bit basic', cast(0 as bit));
insert into sqlvariant_test_1 (testcase, v) values ('nvarchar basic', cast('a' as nvarchar(1)));
insert into sqlvariant_test_1 (testcase, v) values ('varchar basic', cast('a' as varchar(1)));
insert into sqlvariant_test_1 (testcase, v) values ('nchar basic', cast('a' as nchar(1)));
insert into sqlvariant_test_1 (testcase, v) values ('char basic', cast('a' as char(1)));
insert into sqlvariant_test_1 (testcase, v) values ('char basic', cast('a' as text)::sql_variant);

select sql_variant_property(v, 'nothing') from sqlvariant_test_1;
select sql_variant_property(v, 'basetype') from sqlvariant_test_1;
select sql_variant_property(v, 'precision') from sqlvariant_test_1;
select sql_variant_property(v, 'scale') from sqlvariant_test_1;
select sql_variant_property(v, 'collation') from sqlvariant_test_1;
select sql_variant_property(v, 'totalbytes') from sqlvariant_test_1;
select sql_variant_property(v, 'maxlength') from sqlvariant_test_1;
drop table sqlvariant_test_1;


CREATE table sqlvariant_test_2 ( a sql_variant);
insert into sqlvariant_test_2 values (null);
select sql_variant_property(a, 'basetype') as 'basetype',
       sql_variant_property(a, 'precision') as 'precision',
       sql_variant_property(a, 'scale') as 'scale',
       sql_variant_property(a, 'collation') as 'collation',
       sql_variant_property(a, 'totalbytes') as 'totalbytes',
       sql_variant_property(a, 'maxlength') as 'maxlength' from sqlvariant_test_2;

drop table sqlvariant_test_2; 


create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   text_col text
);

insert into test_type_table_column_name values (1, 1, 1, 1, 1, 1, 1, b'1', 1, 1, 1, 1, 1, '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 'abc');

select 
    sql_variant_property(int1_col, 'BaseType'), 
	sql_variant_property(int2_col, 'BaseType'), 
	sql_variant_property(int4_col, 'BaseType'), 
	sql_variant_property(int8_col, 'BaseType'), 
	sql_variant_property(float4_col, 'BaseType'), 
	sql_variant_property(float8_col, 'BaseType'), 
	sql_variant_property(numeric_col, 'BaseType'), 
	sql_variant_property(bit1_col, 'BaseType'), 
	sql_variant_property(char_col, 'BaseType'), 
	sql_variant_property(varchar_col, 'BaseType'), 
	sql_variant_property(nvarchar_col, 'BaseType'),
    sql_variant_property(date_col, 'BaseType'),
   sql_variant_property(text_col, 'BaseType')
from test_type_table_column_name;

drop table test_type_table_column_name;

-- sys.patindex
SELECT PATINDEX('%abc%', 'xyzabc123'), PATINDEX('hello%', 'hello world'), PATINDEX('hello%', 'hi hello'), PATINDEX('%123', 'test123');  -- expect 4 1 0 5
SELECT PATINDEX('%123', '123test'), PATINDEX('abc123', 'abc123'), PATINDEX('abc123', 'abc1234');   --expect  0 1 0
SELECT PATINDEX('%a_c%', 'xayc123'), PATINDEX('%a_c%', 'ac123'), PATINDEX('%a__c%', 'axyzc');  -- expect 2 0 0
SELECT PATINDEX('%[0-9]%', 'abc123'), PATINDEX('%[A-Z]%', 'abcDEF'), PATINDEX('%[abc]%', 'xyzc');  -- expect 4 1 4  -- to be fixed
SELECT PATINDEX('%[^0-9]%', '123abc'), PATINDEX('%[^a-z]%', 'abc123');  -- expect 4 4  -- to be fixed
SELECT PATINDEX('%[a-z][0-9]%', 'testA5xyz'), PATINDEX('%[0-9][^0-9]%', '123abc');  -- expect 5 3  -- to be fixed
SELECT PATINDEX('%.%', 'test.txt'), PATINDEX('%[.]%', 'test.txt'), PATINDEX('%#.%', 'test#.txt');   -- expect 5 5 5   -- to be fixed
SELECT PATINDEX('%[%', 'a[b]c'); -- expect 0  -- to be fixed
SELECT PATINDEX('%]%', 'a[b]c');  -- expect 4
SELECT PATINDEX('%*%', 'test*123'); -- expect 5  -- to be fixed
SELECT PATINDEX('%#*%', 'test#*123');  -- expect 5  -- to be fixed
SELECT PATINDEX('%abc%', NULL);  -- expect error
SELECT PATINDEX(NULL, 'abc123');   -- expect NULL
SELECT PATINDEX('%a%', ''), PATINDEX('', ''), PATINDEX('', 'a');     -- expect 0  1 0  -- to be fixed
SELECT PATINDEX('%测试%', 'SQL Server 测试案例'), PATINDEX('%[测]%', 'SQL Server 测试案例');  -- expect 12 12
SELECT PATINDEX('%@%', 'user@example.com'), PATINDEX('%￥%', '价格：￥99');   -- expect 5 4 
SELECT PATINDEX('%a b%', 'x a b y'), PATINDEX('%a_b%', 'x a b y');  -- expect 3 3


-- different data type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10');

SELECT PATINDEX(int1_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(int2_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(int4_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(int8_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(float4_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(float8_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(numeric_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(bit1_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(datetime_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(smalldatetime_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(date_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(time_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(boolean_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(char_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(varchar_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(nvarchar_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(varbinary_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX(text_col, 'x a b y')  from test_type_table_column_name;
SELECT PATINDEX('x a b y', int1_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', int2_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', int4_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', int8_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', float4_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', float8_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', numeric_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', bit1_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', datetime_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', smalldatetime_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', date_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', time_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', boolean_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', char_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', varchar_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', nvarchar_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', varbinary_col)  from test_type_table_column_name;
SELECT PATINDEX('x a b y', text_col)  from test_type_table_column_name;

drop table if exists test_type_table_column_name;


-- sys.stuff
SELECT STUFF('abcdefg', 2, 3, 'XYZ');       --expect: aXYZefg
SELECT STUFF('abcdefg', 4, 0, 'INSERTED');  --expect: abcINSERTEDdefg
SELECT STUFF('abcdefg', 3, 2, '');          --expect: abefg
SELECT STUFF('abcdefg', 2, 1, 'XXXX');      --expect: aXXXXcdefg
SELECT STUFF('abcdefg', 2, 4, 'XX');        --expect: aXXfg
SELECT STUFF('abcdefg', 1, 3, '123');       --expect: 123defg
SELECT STUFF('abcdefg', 5, 10, 'END');      --expect: abcdEND
SELECT STUFF('abcdefg', 7, 1, 'Z');         --expect: abcdefZ
SELECT STUFF('abcdefg', 8, 1, 'Z');         --expect: NULL
SELECT STUFF('abcdefg', 1, 0, 'PRE-');      --expect: PRE-abcdefg
SELECT STUFF('', 1, 0, 'Hello');            --expect: NULL
SELECT STUFF('abcdefg', 2, 3, '');          --expect: aefg
SELECT STUFF('abcdefg', 0, 1, 'X');         --expect: NULL
SELECT STUFF('abcdefg', -1, 1, 'X');        --expect: NULL 
SELECT STUFF('abcdefg', 2, -1, 'X');        --expect: NULL
SELECT STUFF(NULL, 2, 3, 'XYZ');            --expect: NULL
SELECT STUFF('abcdefg', 2, 3, NULL);        --expect: aefg
SELECT STUFF(CAST('Old Text' AS TEXT), 5, 1, 'X');  --expect: Old TXext
SELECT STUFF(N'abcdefg', 3, 2, N'你好');            --expect: ab你好efg
SELECT LEN(STUFF(REPLICATE('A', 9000), 4000, 1000, REPLICATE('B', 500)));  --expect: 8500


-- diff input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10', '2025-10-10');

SELECT STUFF(int1_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(int2_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(int4_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(int8_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(float4_col, 2, 3, 'XYZ') from test_type_table_column_name;   
SELECT STUFF(float8_col, 2, 3, 'XYZ') from test_type_table_column_name;   
SELECT STUFF(numeric_col, 2, 3, 'XYZ') from test_type_table_column_name;  
SELECT STUFF(bit1_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(datetime_col, 2, 3, 'XYZ') from test_type_table_column_name; 
SELECT STUFF(smalldatetime_col, 2, 3, 'XYZ') from test_type_table_column_name;     
SELECT STUFF(date_col, 2, 3, 'XYZ') from test_type_table_column_name;       
SELECT STUFF(time_col, 2, 3, 'XYZ') from test_type_table_column_name;        
SELECT STUFF(char_col, 2, 3, 'XYZ') from test_type_table_column_name;       
SELECT STUFF(varchar_col, 2, 3, 'XYZ') from test_type_table_column_name;    
SELECT STUFF(nvarchar_col, 2, 3, 'XYZ') from test_type_table_column_name;   
SELECT STUFF(varbinary_col, 2, 3, 'XYZ') from test_type_table_column_name;  
SELECT STUFF(text_col, 2, 3, 'XYZ') from test_type_table_column_name;       


SELECT STUFF('XYZ', 2, 3, int1_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, int2_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, int4_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, int8_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, float4_col) from test_type_table_column_name;     
SELECT STUFF('XYZ', 2, 3, float8_col) from test_type_table_column_name;     
SELECT STUFF('XYZ', 2, 3, numeric_col) from test_type_table_column_name;    
SELECT STUFF('XYZ', 2, 3, bit1_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, datetime_col) from test_type_table_column_name;   
SELECT STUFF('XYZ', 2, 3, smalldatetime_col) from test_type_table_column_name;
SELECT STUFF('XYZ', 2, 3, date_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, time_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, char_col) from test_type_table_column_name;       
SELECT STUFF('XYZ', 2, 3, varchar_col) from test_type_table_column_name;    
SELECT STUFF('XYZ', 2, 3, nvarchar_col) from test_type_table_column_name;   
SELECT STUFF('XYZ', 2, 3, varbinary_col) from test_type_table_column_name;  
SELECT STUFF('XYZ', 2, 3, text_col) from test_type_table_column_name;       

drop table if exists test_type_table_column_name;

-- sys.str
SELECT STR(123.45, 6, 1);            --expect:  123.5
SELECT STR(123.45, 2, 2);            --expect:  **
SELECT STR (FLOOR (123.45), 8, 3);   --expect:  123.000
SELECT STR(123);                     --expect:  123
SELECT STR(123.45);                  --expect:  123
SELECT STR(123.456, 6, 2);           --expect:  123.46
SELECT STR(123, 3);                  --expect:  123
SELECT STR(12345, 3);                --expect:  ***
SELECT STR(123.999, 5, 0);           --expect:  124
SELECT STR(-123.45, 7, 2);           --expect:  -123.45
SELECT STR('ABC');                   --expect:  error
SELECT STR('123.45', 7, 2);          --expect:  123.45
select str('99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999',64,32);


-- diff input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '2025', '2025', '2025', '2025', '2025');


SELECT STR(int1_col) from test_type_table_column_name;
SELECT STR(int2_col) from test_type_table_column_name;
SELECT STR(int4_col) from test_type_table_column_name;
SELECT STR(int8_col) from test_type_table_column_name;
SELECT STR(float4_col) from test_type_table_column_name;
SELECT STR(float8_col) from test_type_table_column_name;
SELECT STR(bit1_col) from test_type_table_column_name;
SELECT STR(char_col) from test_type_table_column_name;
SELECT STR(varchar_col) from test_type_table_column_name;
SELECT STR(nvarchar_col) from test_type_table_column_name;
SELECT STR(text_col) from test_type_table_column_name;
SELECT STR(int1_col, 6, 2) from test_type_table_column_name;
SELECT STR(int2_col, 6, 2) from test_type_table_column_name;
SELECT STR(int4_col, 6, 2) from test_type_table_column_name;
SELECT STR(int8_col, 6, 2) from test_type_table_column_name;
SELECT STR(float4_col, 6, 2) from test_type_table_column_name;
SELECT STR(float8_col, 6, 2) from test_type_table_column_name;
SELECT STR(bit1_col, 6, 2) from test_type_table_column_name;
SELECT STR(char_col, 6, 2) from test_type_table_column_name;
SELECT STR(varchar_col, 6, 2) from test_type_table_column_name;
SELECT STR(nvarchar_col, 6, 2) from test_type_table_column_name;
SELECT STR(text_col, 6, 2) from test_type_table_column_name;

drop table if exists test_type_table_column_name;


-- sys.replicate
SELECT REPLICATE('A', 3);                           -- expect: AAA
SELECT REPLICATE('abc', 2);                         -- expect: abcabc
SELECT REPLICATE('123', 4);                         -- expect: 123123123123
SELECT REPLICATE('abc', 1);                         -- expect: abc

SELECT REPLICATE('@', 5);                           -- expect: @@@@@
SELECT REPLICATE('!#', 3);                          -- expect: !#!#!#

SELECT REPLICATE(' ', 4);                           -- expect:     
SELECT REPLICATE('', 5);                            -- expect: 
SELECT REPLICATE('test', 0);                        -- expect: 

SELECT LEN(REPLICATE('a', 8000));                   ---expect: 8000
SELECT LEN(REPLICATE('ab', 4000));                  ---expect: 8000
SELECT LEN(REPLICATE('abc', 2666));                 -- expect: 7998

SELECT REPLICATE('test', -1);                       -- expect: NULL
SELECT REPLICATE(NULL, 3);                          -- expect: NULL
SELECT REPLICATE('abc', NULL);                      -- expect: NULL
SELECT REPLICATE(NULL, NULL);                       -- expect: NULL

SELECT REPLICATE(123, 2);                           -- expect: 123123
SELECT REPLICATE(CAST('2025-10-10 10:10:10' AS VARCHAR), 2);    -- expect: 2025-10-10 10:10:102025-10-10 10:10:10
SELECT REPLICATE(N'中', 3);                         -- expect: 中中中
SELECT REPLICATE(N'国', 2);                         -- expect: 国国

SELECT LEN(REPLICATE(N'a', 4000));                  -- expect: 4000
SELECT LEN(REPLICATE('a', 8001));                   -- expect: 8000
SELECT LEN(REPLICATE(N'a', 4001));                  -- expect: 4000

select REPLICATE('a\t', 3);                         -- expect: a\ta\ta\t
select REPLICATE('a\\t', 3);                        -- expect: a\\ta\\ta\\t
select REPLICATE('a\n', 3);                         -- expect: a\na\na\n
select REPLICATE('a\\n', 3);                        -- expect: a\\na\\na\\n


create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '10', '10', '10', '10', '10');

SELECT 
    REPLICATE(int1_col, 2),
	REPLICATE(int2_col, 2),
	REPLICATE(int4_col, 2),
	REPLICATE(int8_col, 2),
	REPLICATE(float4_col, 2),
	REPLICATE(float8_col, 2),
	REPLICATE(numeric_col, 2),
	REPLICATE(bit1_col, 2),
	REPLICATE(datetime_col, 2),
	REPLICATE(smalldatetime_col, 2),
	REPLICATE(date_col, 2),
	REPLICATE(time_col, 2),
	REPLICATE(char_col, 2),
	REPLICATE(varchar_col, 2),
	REPLICATE(nvarchar_col, 2),
	REPLICATE(text_col, 2)
from test_type_table_column_name;

SELECT 
    LEN(REPLICATE('amaoagou', int1_col)),
	LEN(REPLICATE('amaoagou', int2_col)),
	LEN(REPLICATE('amaoagou', int4_col)),
	LEN(REPLICATE('amaoagou', int8_col)),
	LEN(REPLICATE('amaoagou', float4_col)),
	LEN(REPLICATE('amaoagou', float8_col)),
	LEN(REPLICATE('amaoagou', numeric_col)),
	LEN(REPLICATE('amaoagou', bit1_col)),
	LEN(REPLICATE('amaoagou', char_col)),
	LEN(REPLICATE('amaoagou', varchar_col)),
	LEN(REPLICATE('amaoagou', nvarchar_col)),
	LEN(REPLICATE('amaoagou', text_col))
from test_type_table_column_name;

drop table if exists test_type_table_column_name;

-- sys.STRING_SPLIT
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.', ' ');    -- 5 rows
SELECT value FROM STRING_SPLIT('clothing,road,,touring,bike', ',');    -- 5 rows
SELECT value FROM STRING_SPLIT('||||||||', '|');                       -- 9 rows
SELECT value FROM STRING_SPLIT(NULL, ' ');                             -- 0 rows
SELECT value FROM STRING_SPLIT('asdf', '');                            -- error
SELECT value FROM STRING_SPLIT('asdf', NULL);                          -- error
SELECT value FROM STRING_SPLIT(NULL, NULL);                            -- error
SELECT value FROM STRING_SPLIT(CAST('nvarchar nvarchar nvarchar' as nvarchar(100)), CAST(' ' as nvarchar(100)));    -- 3 rows
SELECT value FROM STRING_SPLIT(CAST('varchar varchar varchar' as varchar), CAST(' ' as varchar));         -- 3 rows
SELECT value FROM STRING_SPLIT('char char char', ' ');         -- 3 rows
SELECT value FROM STRING_SPLIT('a,b,c,d', ',');                -- 4 rows
SELECT value FROM STRING_SPLIT('mississippi island lives in igloo', 'i');   -- 9 rows
SELECT value FROM STRING_SPLIT(CAST('asdf' as nchar(4)), ' ');              -- 1 rows
SELECT value FROM STRING_SPLIT(CAST('asdf' as char(4)), ' ');               -- 1 rows
SELECT value FROM STRING_SPLIT('Lorem ipsum', 'too many chars');            -- error
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.', ' ');         -- 5 rows
SELECT mycol FROM STRING_SPLIT('Lorem ipsum dolor sit amet.', ' ');         -- error
SELECT value FROM STRING_SPLIT('red;green;blue', ';');                      -- 3 rows
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.'::char(100), ' ');
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.'::varchar(100), ' ');
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.'::nchar(100), ' ');
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.'::nvarchar(100), ' ');
SELECT value FROM STRING_SPLIT('Lorem ipsum dolor sit amet.'::text, ' ');



-- different input type
create table test_type_table_column_name
(
   int1_col tinyint,
   int2_col smallint,
   int4_col integer,
   int8_col bigint,
   float4_col float4,
   float8_col float8,
   numeric_col decimal(20, 6),
   bit1_col bit(1),
   datetime_col timestamp without time zone,
   smalldatetime_col smalldatetime,
   date_col date,
   time_col time,
   boolean_col boolean,
   char_col char(100),
   varchar_col varchar(100), 
   nvarchar_col nvarchar(10),
   varbinary_col varbinary(100),
   text_col text
);

insert into test_type_table_column_name values (20, 2025, 2025, 2025, 2025, 2025, 2025, b'1', '2025-10-10 10:10:10', '2025-10-10 10:10:10', '2025-10-10', '10:10:10', 1, '10', '10', '10', '10', '10');

SELECT 
    sys.columnproperty(int1_col, 'cp1', 'precision'),
	sys.columnproperty(int2_col, 'cp1', 'precision'),
	sys.columnproperty(int4_col, 'cp1', 'precision'),
	sys.columnproperty(int8_col, 'cp1', 'precision')
from test_type_table_column_name;


drop table test_type_table_column_name;
drop table t_column_property;
drop table t_column_property2;
drop table t_column_property3;

-- sys.quotename
SELECT quotename('hardrada', ']');   --expect: [hardrada]
SELECT quotename('gershwin', '<');   --expect: <gershwin>
SELECT quotename('faulkner', '>');   --expect: <faulkner>

SELECT quotename('edgerton', '(');   --expect：(edgerton)
SELECT quotename('denali', ')');     --expect: (denali)
SELECT quotename('charisma', '{');   --expect: {charisma}

SELECT quotename('banana', '}');     --expect: {banana}
SELECT quotename('aardvark', '`');   --expect: `aardvark`

SELECT quotename('128 characters exactly----------------------------------------------------------------------------------------------------------');   --expect [xxx]
SELECT quotename(']]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]');   --expect [xxx]
SELECT quotename('""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""');   --expect [xxx]
SELECT quotename('''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''');   -- expect: [xx]


SELECT quotename('');           --expect []
SELECT quotename(CAST('abc' as varchar));    --expect: [abc]
SELECT quotename(CAST('abc' as nvarchar(20)));    --expect: [abc]

SELECT quotename(CAST('abc' as text));   --expect： [abc]
SELECT quotename('invalid char', 'F');   --expect：NULL
SELECT quotename('too long char', 'aa');  --expect： NULL

SELECT quotename('129 characters exactly-----------------------------------------------------------------------------------------------------------');  --expect: NULL
SELECT quotename('default should be bracket');   --expect: [default should be bracket]
SELECT quotename('abc [] def');                  --expect：[abc []] def]
 
SELECT quotename(NULL);                          --expect: NULL
SELECT quotename(NULL, NULL);                    --expect: NULL
SELECT quotename('hey', NULL);                   --expect: NULL
SELECT quotename(NULL, '[');                     --expect: NULL

-- diff input type
CREATE TABLE test_quotename_table (
    bigint_type bigint,
    int_type int,
    smallint_type smallint,
    tinyint_type tinyint,
    bit_type bit,
    decimal_type decimal(5,2),
    numeric_type numeric(10,5),
    float_type float,
    real_type real,
    money_type money,
    float8_type float8,
    boolean_col boolean,
    char_col char(100),
    varchar_col varchar(100), 
    nvarchar_col nvarchar(10),
    varbinary_col varbinary(100),
    text_col text
);

INSERT INTO test_quotename_table VALUES (
    9223372036854775806,
    45000,
    -32767,
    100,
    b'1',
    123,
    12345.12,
    1.79E+30,
    -3.40E+38, 
    237891.22,
    77.58,
	1,  -- bool
	'1',
	'1',
	'1',
	'1',
	'1'
);

SELECT quotename(bigint_type) FROM test_quotename_table;     
SELECT quotename(int_type) FROM test_quotename_table;        
SELECT quotename(smallint_type) FROM test_quotename_table;   
SELECT quotename(tinyint_type) FROM test_quotename_table;    
SELECT quotename(bit_type) FROM test_quotename_table;        
SELECT quotename(decimal_type) FROM test_quotename_table;    
SELECT quotename(numeric_type) FROM test_quotename_table;    
SELECT quotename(float_type) FROM test_quotename_table;      
SELECT quotename(real_type) FROM test_quotename_table;           
SELECT quotename(float8_type) FROM test_quotename_table;       
SELECT quotename(char_col) FROM test_quotename_table;        
SELECT quotename(varchar_col) FROM test_quotename_table;     
SELECT quotename(nvarchar_col) FROM test_quotename_table;    
SELECT quotename(varbinary_col) FROM test_quotename_table;   
SELECT quotename(text_col) FROM test_quotename_table;        

drop table test_quotename_table;


-- sys.trim
SELECT TRIM('   test   ');       -- test
SELECT TRIM('   test   ');       -- test
SELECT TRIM('   ');              -- ''
SELECT TRIM(NULL);               -- null

SELECT TRIM('test');             -- test
SELECT TRIM('   测试   ');       -- 测试
SELECT LTRIM('   测试abc');      -- 测试abc
SELECT TRIM( '.,! ' FROM '     #     test    .');    --#     test

SELECT TRIM(LEADING '.,! ' FROM  '     .#     test    .');
SELECT TRIM(TRAILING '.,! ' FROM '     .#     test    .');
SELECT TRIM(BOTH '123' FROM '123abc123');

CREATE TABLE test_quotename_table (
    bigint_type bigint,
    int_type int,
    smallint_type smallint,
    tinyint_type tinyint,
    bit_type bit,
    decimal_type decimal(5,2),
    numeric_type numeric(10,5),
    float_type float,
    real_type real,
    money_type money,
    float8_type float8,
    boolean_col boolean,
    char_col char(100),
    varchar_col varchar(100), 
    nvarchar_col nvarchar(10),
    varbinary_col varbinary(100),
    text_col text
);

INSERT INTO test_quotename_table VALUES (
    9223372036854775806,
    45000,
    -32767,
    100,
    b'1',
    123,
    12345.12,
    1.79E+30,
    -3.40E+38, 
    237891.22,
    77.58,
	1,  -- bool
	'1',
	'1',
	'1',
	'1',
	'1'
);

SELECT TRIM(char_col), TRIM(varchar_col), TRIM(nvarchar_col), TRIM(varbinary_col), TRIM(text_col)  from test_quotename_table;
drop table test_quotename_table;

reset current_schema;
drop schema sharksysfunc cascade;
