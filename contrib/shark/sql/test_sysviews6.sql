-- sys.synonyms
\d sys.synonyms

drop schema if exists test_views2 cascade;
create schema test_views2;
set current_schema to test_views2;

drop table if exists student;
create table student
(
    std_id int primary key,
    std_name varchar(20) not null,
    std_sex varchar(6),
    std_birth date,
    std_in date not null,
    std_address varchar(100)
);
create or replace synonym syn_student for student;

select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published from sys.objects where name = 'syn_student';
select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published from sys.synonyms where name = 'syn_student';

select count(*) from sys.objects obj inner join pg_synonym syn on syn.synname = obj.name
  where obj.name = 'syn_student';
select count(*) from sys.synonyms obj inner join pg_synonym syn on syn.synname = obj.name
  where obj.name = 'syn_student';
select count(*) from sys.objects obj inner join pg_synonym syn on syn.synnamespace = obj.schema_id
inner join pg_namespace np on np.oid = syn.synnamespace
  where np.nspname = 'test_views2' and obj.name = 'syn_student';
select count(*) from sys.synonyms obj inner join pg_synonym syn on syn.synnamespace = obj.schema_id
  inner join pg_namespace np on np.oid = syn.synnamespace
  where np.nspname = 'test_views2' and obj.name = 'syn_student';

select base_object_name from sys.synonyms where name = 'syn_student';

create view view_stu as select * from student;
create or replace synonym syn_view_stu FOR view_stu;

select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published from sys.objects where name = 'syn_view_stu';
select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published from sys.synonyms where name = 'syn_view_stu';

select count(*) from sys.objects obj inner join pg_synonym syn on syn.synname = obj.name
  where obj.name = 'syn_view_stu';
select count(*) from sys.synonyms obj inner join pg_synonym syn on syn.synname = obj.name
  where obj.name = 'syn_view_stu';
select count(*) from sys.objects obj inner join pg_synonym syn on syn.synnamespace = obj.schema_id
  and syn.synname = obj.name
  inner join pg_namespace np on np.oid = syn.synnamespace
  where np.nspname = 'test_views2' and obj.name = 'syn_view_stu';
select count(*) from sys.synonyms obj inner join pg_synonym syn on syn.synnamespace = obj.schema_id
  and syn.synname = obj.name
  inner join pg_namespace np on np.oid = syn.synnamespace
  where np.nspname = 'test_views2' and obj.name = 'syn_view_stu';

select base_object_name from sys.synonyms where name = 'syn_view_stu';

drop synonym syn_student;
drop synonym syn_view_stu;
drop table student cascade;

drop table if exists "student 1";
create table "student 1"
(
    std_id int primary key,
    std_name varchar(20) not null,
    std_sex varchar(6),
    std_birth date,
    std_in date not null,
    std_address varchar(100)
);
create or replace synonym "syn_student 1" FOR "student 1";
create or replace synonym "syn_student1" FOR "student 1";

select base_object_name from sys.synonyms where name = 'syn_student 1';
select base_object_name from sys.synonyms where name = 'syn_student1';

drop synonym "syn_student 1";
drop synonym "syn_student1";

drop table "student 1" cascade;
drop schema test_views2 cascade;