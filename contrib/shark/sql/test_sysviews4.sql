-- sys.database_principals
\d sys.database_principals
select * from sys.database_principals where is_fixed_role::int = 1 and name like 'gs_role%';
select count(*) from sys.database_principals where principal_id = 10 and is_fixed_role::int = 1;
create user testview password 'Test@123';
select count(*) from sys.database_principals where name = 'testview' and is_fixed_role::int = 0;
select count(*) from sys.database_principals d inner join pg_roles r
  on d.name = 'testview' and d.principal_id = r.oid and d.sid = r.oid::int::varbinary(85);
select name, type, type_desc, default_schema_name, create_date, modify_date, owning_principal_id,
  is_fixed_role, authentication_type, authentication_type_desc, default_language_name, 
  default_language_lcid, allow_encrypted_value_modifications from sys.database_principals d inner join pg_roles r
  on d.name = 'testview' and d.principal_id = r.oid and d.sid = r.oid::int::varbinary(85);
drop user testview;

-- sys.foreign_key_columns
-- sys.foreign_keys
-- sys.sysforeignkeys
\d sys.foreign_key_columns
\d sys.foreign_keys
\d sys.sysforeignkeys

drop schema if exists test_views cascade;
create schema test_views;
set current_schema to test_views;

create table astore_mult1 (a int primary key, b int);
create table astore_mult2 (c int, d int);
alter table astore_mult2 add foreign key (c) references astore_mult1(a);
\d+ astore_mult2

select constraint_column_id, parent_column_id, referenced_column_id from sys.foreign_key_columns
  where constraint_object_id = object_id('astore_mult2_c_fkey', 'F') 
  and parent_object_id = object_id('astore_mult2', 'U')
  and referenced_object_id = object_id('astore_mult1', 'U');

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where name = 'astore_mult2_c_fkey';
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.foreign_keys where name = 'astore_mult2_c_fkey';
select is_disabled, is_not_for_replication, is_not_trusted, delete_referential_action, delete_referential_action_desc,
  update_referential_action, update_referential_action_desc, is_system_named
  from sys.foreign_keys where name = 'astore_mult2_c_fkey';
select count(*) from sys.objects where object_id = object_id('astore_mult2_c_fkey', 'F');
select count(*) from sys.foreign_keys where object_id = object_id('astore_mult2_c_fkey', 'F');
select count(*) from sys.objects fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult2_c_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult2_c_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.referenced_object_id = con.confrelid and fk.key_index_id = con.conindid
  and fk.is_disabled = con.condisable::int::bit and fk.is_not_trusted = (not con.convalidated)::int::bit
  where con.conname = 'astore_mult2_c_fkey';

select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult2_c_fkey';

create table astore_mult3 (a int, b int primary key);
create table astore_mult4 (c int, d int);
alter table astore_mult4 add foreign key (d) references astore_mult3(b);
\d+ astore_mult4

select constraint_column_id, parent_column_id, referenced_column_id from sys.foreign_key_columns
  where constraint_object_id = object_id('astore_mult4_d_fkey', 'F') 
  and parent_object_id = object_id('astore_mult4', 'U')
  and referenced_object_id = object_id('astore_mult3', 'U');

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where name = 'astore_mult4_d_fkey';
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.foreign_keys where name = 'astore_mult4_d_fkey';
select is_disabled, is_not_for_replication, is_not_trusted, delete_referential_action, delete_referential_action_desc,
  update_referential_action, update_referential_action_desc, is_system_named
  from sys.foreign_keys where name = 'astore_mult4_d_fkey';
select count(*) from sys.objects where object_id = object_id('astore_mult4_d_fkey', 'F');
select count(*) from sys.foreign_keys where object_id = object_id('astore_mult4_d_fkey', 'F');
select count(*) from sys.objects fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult4_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult4_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.referenced_object_id = con.confrelid and fk.key_index_id = con.conindid
  and fk.is_disabled = con.condisable::int::bit and fk.is_not_trusted = (not con.convalidated)::int::bit
  where con.conname = 'astore_mult4_d_fkey';

select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult4_d_fkey';

create table astore_mult5 (a int, b int, primary key(a, b));
create table astore_mult6 (c int, d int, e int);
alter table astore_mult6 add foreign key (d, e) references astore_mult5 (a, b);
\d+ astore_mult6

select constraint_column_id, parent_column_id, referenced_column_id from sys.foreign_key_columns
  where constraint_object_id = object_id('astore_mult6_d_fkey', 'F') 
  and parent_object_id = object_id('astore_mult6', 'U')
  and referenced_object_id = object_id('astore_mult5', 'U');

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where name = 'astore_mult6_d_fkey';
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.foreign_keys where name = 'astore_mult6_d_fkey';
select is_disabled, is_not_for_replication, is_not_trusted, delete_referential_action, delete_referential_action_desc,
  update_referential_action, update_referential_action_desc, is_system_named
  from sys.foreign_keys where name = 'astore_mult6_d_fkey';
select count(*) from sys.objects where object_id = object_id('astore_mult6_d_fkey', 'F');
select count(*) from sys.foreign_keys where object_id = object_id('astore_mult6_d_fkey', 'F');
select count(*) from sys.objects fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult6_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult6_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.referenced_object_id = con.confrelid and fk.key_index_id = con.conindid
  and fk.is_disabled = con.condisable::int::bit and fk.is_not_trusted = (not con.convalidated)::int::bit
  where con.conname = 'astore_mult6_d_fkey';

select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult6_d_fkey';

create table astore_mult7 (a int, b int, primary key(b, a));
create table astore_mult8 (c int, d int, e int);
alter table astore_mult8 add foreign key (d, e) references astore_mult7 (b, a);
\d+ astore_mult8

select constraint_column_id, parent_column_id, referenced_column_id from sys.foreign_key_columns
  where constraint_object_id = object_id('astore_mult8_d_fkey', 'F') 
  and parent_object_id = object_id('astore_mult8', 'U')
  and referenced_object_id = object_id('astore_mult7', 'U');

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where name = 'astore_mult8_d_fkey';
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.foreign_keys where name = 'astore_mult8_d_fkey';
select is_disabled, is_not_for_replication, is_not_trusted, delete_referential_action, delete_referential_action_desc,
  update_referential_action, update_referential_action_desc, is_system_named
  from sys.foreign_keys where name = 'astore_mult8_d_fkey';
select count(*) from sys.objects where object_id = object_id('astore_mult8_d_fkey', 'F');
select count(*) from sys.foreign_keys where object_id = object_id('astore_mult8_d_fkey', 'F');
select count(*) from sys.objects fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult8_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.schema_id = con.connamespace and fk.parent_object_id = con.conrelid
  where con.conname = 'astore_mult8_d_fkey';
select count(*) from sys.foreign_keys fk inner join pg_constraint con
  on fk.referenced_object_id = con.confrelid and fk.key_index_id = con.conindid
  and fk.is_disabled = con.condisable::int::bit and fk.is_not_trusted = (not con.convalidated)::int::bit
  where con.conname = 'astore_mult8_d_fkey';

select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult8_d_fkey';

drop table if exists astore_mult2;
drop table if exists astore_mult1;
drop table if exists astore_mult4;
drop table if exists astore_mult3;
drop table if exists astore_mult6;
drop table if exists astore_mult5;
drop table if exists astore_mult8;
drop table if exists astore_mult7;

create table staff (
    id          int primary key not null,
    name        text not null,
    age         int not null,
    address     char(50),
    salary      real
);
create table department (
    id          int primary key not null,
    dept        char(50) not null,
    emp_id      int references staff(id) on update cascade on delete set default
);
select delete_referential_action, delete_referential_action_desc, update_referential_action,
  update_referential_action_desc, is_system_named
  from sys.foreign_keys where name = 'department_emp_id_fkey';

drop table if exists department;
drop table if exists staff;

create table staff1 (
    id          int primary key not null,
    name        text not null,
    age         int not null,
    address     char(50),
    salary      real
);
create table department1 (
    id          int primary key not null,
    dept        char(50) not null,
    emp_id      int,
    constraint my_fkey foreign key (emp_id) references staff1(id) on update set null on delete cascade
);
select delete_referential_action, delete_referential_action_desc, update_referential_action,
  update_referential_action_desc, is_system_named 
  from sys.foreign_keys where name = 'my_fkey';

create table astore_mult1 (a int primary key, b int);
create table astore_mult2 (c int, d int);
alter table astore_mult2 add foreign key (c) references astore_mult1(a);
create table astore_mult3 (a int primary key, b int);
alter table astore_mult2 add foreign key (c) references astore_mult3(a);
\d+ astore_mult2

select is_system_named from sys.foreign_keys where name = 'astore_mult2_c_fkey';
select is_system_named from sys.foreign_keys where name = 'astore_mult2_c_fkey1'; --error

drop table if exists astore_mult5;
drop table if exists astore_mult4;
create table astore_mult4 (a int, b int, c int, d int, primary key(a, d));
create table astore_mult5 (aa int, bb int, cc int, dd int);
alter table astore_mult5 add foreign key (aa, cc) references astore_mult4(a, d);
\d+ astore_mult5
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult5_aa_fkey';

alter table astore_mult4 drop column c; -- sys.sysforeignkeys value is not changed
\d astore_mult4
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult4') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult5_aa_fkey';

alter table astore_mult5 drop column bb; -- sys.sysforeignkeys value is not changed
\d astore_mult5
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult5') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult5_aa_fkey';

alter table astore_mult4 add column e int; -- sys.sysforeignkeys value is not changed
alter table astore_mult5 add column ee int; -- sys.sysforeignkeys value is not changed
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult5_aa_fkey';

drop table if exists test_1;
create table test_1(col1 int, col2 int, col3 int, col4 int);
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'test_1') and attnum > 0;
alter table test_1 add column col int;
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'test_1') and attnum > 0;
alter table test_1 add column col_after int after col2;
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'test_1') and attnum > 0;
alter table test_1 add column col_before int first;
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'test_1') and attnum > 0;
\d test_1

drop table if exists astore_mult7;
drop table if exists astore_mult6;
create table astore_mult6 (a int, b int, c int, d int, primary key(a, d));
create table astore_mult7 (aa int, bb int, cc int, dd int);
alter table astore_mult7 add foreign key (aa, cc) references astore_mult6(a, d);
\d+ astore_mult7
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult7_aa_fkey';

alter table astore_mult6 add column a0 int first; -- sys.sysforeignkeys value is changed
\d astore_mult6
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult6') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult7_aa_fkey';

alter table astore_mult6 add column a00 int after a0; -- sys.sysforeignkeys value is changed
\d astore_mult6
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult6') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult7_aa_fkey';

alter table astore_mult7 add column aa0 int first; -- sys.sysforeignkeys value is changed
\d astore_mult7
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult7') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult7_aa_fkey';

alter table astore_mult7 add column aa00 int after aa0; -- sys.sysforeignkeys value is changed
\d astore_mult7
select attname, attnum from pg_attribute where attrelid =
  (select oid from pg_class where relname = 'astore_mult7') and attnum > 0;
select fkey, rkey, keyno from sys.sysforeignkeys fk inner join pg_constraint con
  on fk.constid = con.oid and fk.fkeyid = con.conrelid and fk.rkeyid = con.confrelid
  and con.conname = 'astore_mult7_aa_fkey';

drop table if exists department1;
drop table if exists staff1;

drop schema if exists test_views cascade;