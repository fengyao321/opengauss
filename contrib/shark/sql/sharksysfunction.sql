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

reset current_schema;
drop schema sharksysfunc cascade;
