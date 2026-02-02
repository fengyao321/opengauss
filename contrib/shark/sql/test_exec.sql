CREATE TYPE department AS ENUM ('aa', 'ss', 'cc');
CREATE CAST (department AS text) WITH INOUT AS IMPLICIT;
CREATE DOMAIN lowercase_alpha_domain AS varchar(50) CHECK (VALUE ~ '^[a-z]*$');

create table employees(
    employee_id integer,
    employee_name VARCHAR(100),
    department VARCHAR(50),
    salary NUMERIC
);

insert into employees values(1001,'aaa','cc','5000');
insert into employees values(1001,'aaa','cc','5000');
insert into employees values(1002,'bbb','aa','6000');
insert into employees values(1003,'ccc','ss','7000'); 

create or replace function employee_id_func (
    id int4
) returns int4
as $$
begin 
    return id;
end;
$$ language plpgsql;

create or replace function employee_name_func (
    employee_name text
) returns text
as $$
begin 
    return employee_name;
end;
$$ language plpgsql;

create or replace function employee_salary_func (
    employee_salary NUMERIC
) returns NUMERIC
as $$
begin 
    return employee_salary;
end;
$$ language plpgsql;

--test exec procedure
create or replace procedure add_employee_details_proc(
    IN id1 INTEGER,
    IN department1 text,
    IN name1 lowercase_alpha_domain,
    IN salary1 NUMERIC
)
package as
begin
    insert into employees values(id1, name1, department1, salary1);
end;
/

exec add_employee_details_proc 1001, 'cc', 'aaa', 7000;

begin
    exec add_employee_details_proc 1001, 'cc', 'aaa', 7000;
end;
/
select * from employees;

create or replace procedure get_employee_details_proc1(
    IN OUT id1 INTEGER,
    IN OUT department1 text,
    IN OUT name1 lowercase_alpha_domain,
    IN OUT salary1 NUMERIC
)
package as
begin
    SELECT e.employee_id, e.employee_name, e.department, e.salary
    INTO id1, name1, department1, salary1
    FROM employees e
    WHERE e.employee_id = id1 
          and e.employee_name = name1 
          and e.department = department1 
          and e.salary = salary1;
end;
/

declare
    @id integer := 1001;
    @name lowercase_alpha_domain := 'aaa';
    @department department := 'cc';
    @salary numeric(7,2) := 5000;
begin
    exec get_employee_details_proc1 @id, @department, @name, @salary;
    raise notice '@id: %', @id;
    raise notice '@name: %', @name;
    raise notice '@department: %', @department;
    raise notice '@salary: %', @salary;
end;
/

declare
    @id integer := 1002;
    @name lowercase_alpha_domain := 'bbb';
    @department department := 'aa';
    @salary numeric(7,2) := 6000;
begin
    exec get_employee_details_proc1 @id, @department, @name, @salary;
    raise notice '@id: %', @id;
    raise notice '@name: %', @name;
    raise notice '@department: %', @department;
    raise notice '@salary: %', @salary;
end;
/

declare
    @id integer := 1002;
    @name lowercase_alpha_domain := 'bbb';
    @department department := 'aa';
    @salary numeric(7,2) := 6000;
begin
    exec get_employee_details_proc1 @id, @department, @name, employee_salary_func(employee_id_func(@salary));
    raise notice '@id: %', @id;
    raise notice '@name: %', @name;
    raise notice '@department: %', @department;
    raise notice '@salary: %', @salary;
end;
/

--test procedure that return type of 'record'
create or replace procedure get_employee_details_proc(
    OUT employee_id INTEGER,
    emp_id INTEGER,
    OUT department text,
    IN OUT employee_name1 lowercase_alpha_domain,
    OUT salary NUMERIC
)
package as
begin
    SELECT e.employee_id, e.employee_name, e.department, e.salary
    INTO employee_id, employee_name1, department, salary
    FROM employees e
    WHERE e.employee_id = emp_id and e.employee_name = employee_name1;
end;
/

exec get_employee_details_proc 1001, 'aaa';
exec get_employee_details_proc 1002, 'bbb';
exec get_employee_details_proc emp_id = 1001, employee_name1 = 'aaa';
exec get_employee_details_proc emp_id = 1002, employee_name1 = 'bbb';

declare
    @v_object_text1 text := 'aaa';
    @v_object_id integer := 0;
    @v_object_text2 text := '';
    @v_object_id2 integer := 0;
begin
    exec get_employee_details_proc @v_object_id, employee_id_func(employee_id_func(1001)), @v_object_text2, @v_object_text1, @v_object_id2;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

declare
    @v_object_text1 text := 'bbb';
    @v_object_id text := '123';
    @v_object_text2 department := 'aa';
    @v_object_id2 integer := '0';
begin
    exec get_employee_details_proc @v_object_id, employee_id_func('1002'::numeric), @v_object_text2, @v_object_text1, @v_object_id2;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

declare
    @v_object_text1 text := 'bbb';
    @v_object_id integer := 0;
    @v_object_text2 text := '';
    @v_object_id2 integer := 0;
begin
    exec get_employee_details_proc @v_object_id, employee_id_func(1002), @v_object_text2, employee_name_func(employee_name_func(@v_object_text1)), @v_object_id2;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

declare
    @v_object_text1 text := 'bbb';
    @v_object_id integer := 0;
    @v_object_text2 text := '';
    @v_object_id2 integer := 0;
begin
    exec get_employee_details_proc @v_object_id, employee_id_func(1002), @v_object_text2, @v_object_text1, 6000;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

--test procedure that return type of 'record'
create or replace procedure get_employee_details_proc2(
    OUT employee_id INTEGER,
    emp_id INTEGER,
    OUT department VARCHAR(50),
    OUT employee_name1 VARCHAR(100),
    IN OUT salary1 NUMERIC
)
package as
begin
    SELECT e.employee_id, e.employee_name, e.department, e.salary
    INTO employee_id, employee_name1, department, salary1
    FROM employees e
    WHERE e.employee_id = emp_id and e.salary = salary1;
end;
/

declare
    @v_object_text1 text := 'aaa';
    @v_object_id integer := 0;
    @v_object_text2 text := '';
    @v_object_id2 integer := 5000;
begin
    exec get_employee_details_proc2 @v_object_id, employee_id_func(1001)::numeric, @v_object_text2, @v_object_text1, @v_object_id2;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

--test function that return type of 'record'
create or replace function get_employee_details_func(
    OUT employee_id INTEGER,
    emp_id INTEGER,
    OUT department VARCHAR(50),
    IN OUT employee_name1 VARCHAR(100),
    OUT salary NUMERIC
)
as $$
begin
    SELECT e.employee_id, e.employee_name, e.department, e.salary
    INTO employee_id, employee_name1, department, salary
    FROM employees e
    WHERE e.employee_id = emp_id and e.employee_name = employee_name1;
end;
$$ language plpgsql;

exec get_employee_details_func 1001, 'aaa';
exec get_employee_details_func emp_id = 1001, employee_name1 = 'aaa';

declare
    @v_object_text1 text := 'aaa';
    @v_object_id integer := 0;
    @v_object_text2 text := '';
    @v_object_id2 integer := 0;
begin
    exec get_employee_details_func @v_object_id, 1001, @v_object_text2, @v_object_text1, @v_object_id2;
    raise notice '@v_object_text1: %', @v_object_text1;
    raise notice '@v_object_id: %', @v_object_id;
    raise notice '@v_object_text2: %', @v_object_text2;
    raise notice '@v_object_id2: %', @v_object_id2;
end;
/

create or replace procedure add_id_proc(
    id1 int4 default 10,
    out id2 int4
)
package as
begin
    id2 = id1 + 10; 
end;
/
declare
    id int4;
begin
    exec add_id_proc id1 = 1, id;
    raise notice 'id:%', id;
end;
/

create or replace function integer_func ()
returns int4
as $$
begin 
    return 10;
end;
$$ language plpgsql;

exec integer_func();

declare
    id int4;
begin
    exec id = integer_func;
    raise notice 'id:%', id;
end;
/

create or replace function add_id_func (
    id1 int4 default 10,
    id2 int4
) returns int4
as $$
begin 
    return id1 + id2;
end;
$$ language plpgsql;

exec add_id_func 1, 2;

exec add_id_func 2;

exec add_id_func id2 = 2;

exec add_id_func id1 = 1, id2 = 2;

declare
    id int4;
begin
    exec id = add_id_func id2 = 2;
    raise notice 'id:%', id;
end;
/

create or replace function add_id_func2 (
    int4 default 10,
    int4
) returns int4
as $$
begin 
    return $1 + $2;
end;
$$ language plpgsql;

exec add_id_func2 1, 2;

declare
    id int4;
begin
    exec id = add_id_func2 2, 2;
    raise notice 'id:%', id;
end;
/

--test exec string as sql
exec ('delete from employees where employee_id = 1001;');
select * from employees;
