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


reset current_schema;
drop schema sharksysfunc cascade;
