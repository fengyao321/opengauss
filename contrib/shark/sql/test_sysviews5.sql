drop schema if exists test_views1 cascade;
create schema test_views1;
set current_schema to test_views1;

-- sys.key_constraints
\d sys.key_constraints

create table test1(id int, name varchar(2), primary key(id));
\d+ test1 

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where type = 'PK' and parent_object_id = object_id('test1', 'U');
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.key_constraints where type = 'PK' and parent_object_id = object_id('test1', 'U');

select count(*) from sys.objects where object_id = object_id('test1_pkey', 'PK');
select count(*) from sys.key_constraints where object_id = object_id('test1_pkey', 'PK');
select count(*) from sys.objects pk inner join pg_constraint con
  on pk.schema_id = con.connamespace and pk.parent_object_id = con.conrelid
  where con.conname = 'test1_pkey';
select count(*) from sys.key_constraints pk inner join pg_constraint con
  on pk.schema_id = con.connamespace and pk.parent_object_id = con.conrelid
  where con.conname = 'test1_pkey';

select count(*) from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test1_pkey';
select is_system_named, is_enforced from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test1_pkey';

create table test2(id int, name varchar(2), unique(name));
\d+ test2

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where type = 'UQ' and parent_object_id = object_id('test2', 'U');
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.key_constraints where type = 'UQ' and parent_object_id = object_id('test2', 'U');

select count(*) from sys.objects where object_id = object_id('test2_name_key', 'UQ');
select count(*) from sys.key_constraints where object_id = object_id('test2_name_key', 'UQ');
select count(*) from sys.objects pk inner join pg_constraint con
  on pk.schema_id = con.connamespace and pk.parent_object_id = con.conrelid
  where con.conname = 'test2_name_key';
select count(*) from sys.key_constraints pk inner join pg_constraint con
  on pk.schema_id = con.connamespace and pk.parent_object_id = con.conrelid
  where con.conname = 'test2_name_key';

select count(*) from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test2_name_key';
select is_system_named, is_enforced from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test2_name_key';

select count(*) from sys.key_constraints pk inner join pg_namespace pn
  on pk.schema_id = pn.oid where pn.nspname = 'test_views1';

create table test3(id int, name varchar(2));
create unique index on test3(id); -- not record in sys.key_constraints
create table test4(id int, name varchar(2));
create unique index index4_index on test4(id); -- not record in sys.key_constraints

select count(*) from sys.key_constraints pk inner join pg_namespace pn
  on pk.schema_id = pn.oid where pn.nspname = 'test_views1';

create table test5(id int, name varchar(2), primary key(id, name));
\d+ test5
select is_system_named, is_enforced from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test5_pkey';

create table test6(id int, name varchar(2), unique(id, name));
\d+ test6
select is_system_named, is_enforced from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test6_id_name_key';

create table test7(id int, name varchar(2), col3 int, col4 int, unique(id, name, col3, col4));
\d+ test7
select is_system_named, is_enforced from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test7_id_name_col3_col4_key';

create table test8(id int);
alter table test8 add constraint mypkey_test8 primary key(id);
select is_system_named from sys.key_constraints where parent_object_id = object_id('test8', 'U');

create table employees (
    id int,
    name varchar(100),
    email varchar(100),
    constraint pk_employees_id primary key (id)
);
select is_system_named from sys.key_constraints where parent_object_id = object_id('employees', 'U');

create table employees1 (
    id int,
    name varchar(100),
    email varchar(100),
    constraint uk_employees1_id unique (id)
);
select is_system_named from sys.key_constraints where parent_object_id = object_id('employees1', 'U');

create table employees2 (
    id int,
    name varchar(100),
    email varchar(100),
    constraint employees2_id_key unique (id)
);
select is_system_named from sys.key_constraints where parent_object_id = object_id('employees2', 'U');

-- sys.check_constraints
\d sys.check_constraints

create table test_check1(id int check(id > 2));
\d+ test_check1

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where type = 'C' and parent_object_id = object_id('test_check1', 'U');
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.check_constraints where type = 'C' and parent_object_id = object_id('test_check1', 'U');

select count(*) from sys.objects where object_id = object_id('test_check1_id_check', 'C');
select count(*) from sys.check_constraints where object_id = object_id('test_check1_id_check', 'C');
select count(*) from sys.objects ck inner join pg_constraint con
  on ck.schema_id = con.connamespace and ck.parent_object_id = con.conrelid
  where con.conname = 'test_check1_id_check';
select count(*) from sys.check_constraints ck inner join pg_constraint con
  on ck.schema_id = con.connamespace and ck.parent_object_id = con.conrelid
  where con.conname = 'test_check1_id_check';

select is_disabled, is_not_for_replication, is_not_trusted, parent_column_id, definition, uses_database_collation,
  is_system_named from sys.check_constraints where name = 'test_check1_id_check';

select count(*) from sys.check_constraints ck inner join pg_constraint con
  on ck.is_disabled = con.condisable::int::bit and ck.is_not_trusted = (not con.convalidated)::int::bit
  and ck.definition = con.consrc where ck.name = 'test_check1_id_check';

create table test_check2(id int, idd int, iddd int, check(idd > 2 and id < 4 and iddd = 1));
\d+ test_check2

select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.objects where type = 'C' and parent_object_id = object_id('test_check2', 'U');
select name, principal_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published
  from sys.check_constraints where type = 'C' and parent_object_id = object_id('test_check2', 'U');

select count(*) from sys.objects where object_id = object_id('test_check2_check', 'C');
select count(*) from sys.check_constraints where object_id = object_id('test_check2_check', 'C');
select count(*) from sys.objects ck inner join pg_constraint con
  on ck.schema_id = con.connamespace and ck.parent_object_id = con.conrelid
  where con.conname = 'test_check2_check';
select count(*) from sys.check_constraints ck inner join pg_constraint con
  on ck.schema_id = con.connamespace and ck.parent_object_id = con.conrelid
  where con.conname = 'test_check2_check';

select is_disabled, is_not_for_replication, is_not_trusted, parent_column_id, definition, uses_database_collation,
  is_system_named from sys.check_constraints where name = 'test_check2_check';

select count(*) from sys.check_constraints ck inner join pg_constraint con
  on ck.is_disabled = con.condisable::int::bit and ck.is_not_trusted = (not con.convalidated)::int::bit
  and ck.definition = con.consrc where ck.name = 'test_check2_check';

create table test_check3(id int, idd int constraint mycheck3 check(idd > 2));
select is_disabled, is_not_for_replication, is_not_trusted, parent_column_id, definition, uses_database_collation,
  is_system_named from sys.check_constraints where name = 'mycheck3';

create table test_check4(id int, idd int, iddd int, constraint mycheck4 check(idd > 2 and id < 4));
select is_disabled, is_not_for_replication, is_not_trusted, parent_column_id, definition, uses_database_collation,
  is_system_named from sys.check_constraints where name = 'mycheck4';

-- case sensitive for is_system_named
create table "Test3"("Id" int, name varchar(2), primary key("Id"));
\d+ "Test3" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test3_pkey';

create table "Test 4"("Id" int, name varchar(2), primary key("Id"));
\d+ "Test 4"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test 4_pkey';

create table "Test4"("Id" int, name varchar(2), constraint "Test4_pkey" primary key("Id"));
\d+ "Test4"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test4_pkey';

drop table if exists "Test4";
create table "Test4"("Id" int, name varchar(2), constraint "test4_pkey" primary key("Id"));
\d+ "Test4"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test4_pkey';

create table "Test41"("Id" int primary key, name varchar(2), constraint "test41_pkey" primary key("Id")); --error

create table "Test5"("Id" int, name varchar(2), unique("Id"));
\d+ "Test5" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test5_Id_key';

create table "Test51"("Id" int, name varchar(2), unique("Id"), constraint test51_id_unique_key unique("Id"));
\d+ "Test51" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test51_id_unique_key';

create table "Test52"("Id" int, name varchar(2), unique("Id"), constraint test52_id_unique_key unique("Id"),
constraint test52_id_unique_key1 unique("Id"));
\d+ "Test52" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test52_id_unique_key';

create table "Test53"("Id" int, name varchar(2), unique("Id"), constraint test53_id_unique_key unique("Id"),
constraint test53_id_unique_key1 unique("Id", name));
\d+ "Test53" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test53_id_unique_key';
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test53_id_unique_key1';

create table "Test54"("Id" int unique, name varchar(2), unique("Id"), constraint test54_id_unique_key unique("Id"),
constraint test54_id_unique_key1 unique("Id", name));
\d+ "Test54" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test54_id_unique_key';
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test54_id_unique_key1';

create table "Test55"("Id" int unique, name varchar(2), unique("Id"), constraint "Test55_Id_key" unique("Id"),
constraint test55_id_unique_key1 unique("Id", name));
\d+ "Test55" 
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test55_Id_key';
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test55_id_unique_key1';

create table "Test56"("Id" int unique, name varchar(2), unique("Id"),
constraint "Test56_Id_key" unique("Id"),
constraint "Test56_Id_key1" unique("Id"),
constraint test56_id_unique_key1 unique("Id", name),
constraint test56_id_unique_key12 unique("Id", name),
constraint test56_id_unique_key13 unique(name, "Id")
);
\d+ "Test56"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test56_Id_key';
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test56_id_unique_key1';
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test56_id_unique_key13';

create table "Test 6"("Id" int, name varchar(2), unique("Id"));
\d+ "Test 6"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test 6_Id_key';

create table "Test6"("Id" int, name varchar(2), constraint "Test6_Id_key" unique("Id"));
\d+ "Test6"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test6_Id_key';

drop table if exists "Test6";
create table "Test6"("Id" int, name varchar(2), constraint "test6_Id_key" unique("Id"));
\d+ "Test6"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'test6_Id_key';

create table "Test7"("I d" int, name varchar(2), constraint "Test7_I d_key" unique("I d"));
\d+ "Test7"
select is_system_named from sys.key_constraints pk inner join pg_constraint con
  on pk.unique_index_id = con.conindid where con.conname = 'Test7_I d_key';



create table "Test_check1"("Id" int, idd int, iddd int, check(idd > 2 and "Id" < 4 and iddd = 1));
\d+ "Test_check1"
select is_system_named from sys.check_constraints where name = 'Test_check1_check';

create table "Test_check2"("Id" int, idd int, iddd int, check("Id" < 4));
\d+ "Test_check2"
select is_system_named from sys.check_constraints where name = 'Test_check2_Id_check';

create table "Test_check3"("I d" int, idd int, iddd int, check("I d" < 4));
\d+ "Test_check3"
select is_system_named from sys.check_constraints where name = 'Test_check3_I d_check';

create table "Test_check4"("I d" int, idd int, iddd int, constraint "Test_check4_I d_check" check("I d" < 4));
\d+ "Test_check4"
select is_system_named from sys.check_constraints where name = 'Test_check4_I d_check';

create table "Test_check5"("I d" int, idd int, iddd int, constraint "test_check5_i d_check" check("I d" < 4));
\d+ "Test_check5"
select is_system_named from sys.check_constraints where name = 'test_check5_i d_check';

create table "Test_check6"("I d" int, idd int, iddd int, constraint "test_check6_i d_check" check("I d" < 4),
constraint "test_check6_i d_check1" check("I d" > -10));
\d+ "Test_check6"
select is_system_named from sys.check_constraints where name = 'test_check6_i d_check';
select is_system_named from sys.check_constraints where name = 'test_check6_i d_check1';

create table "Test_check7"("I d" int, idd int, iddd int, check("I d" < 4), check("I d" > -10));
\d+ "Test_check7"
select is_system_named from sys.check_constraints where name = 'Test_check7_I d_check';
select is_system_named from sys.check_constraints where name = 'Test_check7_I d_check1'; --error

create table "Test_check8"("I d" int, idd int, iddd int, check("I d" < 4), check("I d" > -10),
constraint "Test_check8_I d_check" check ("I d" < 10)); --error

create table "Test_check9"("I d" int, idd int, iddd int, check("I d" < 4), check("I d" > -10),
constraint "Test_check9_I d_check1" check ("I d" < 10)); --error

create table "Test_check9"("I d" int, idd int, iddd int, check("I d" < 4), check("I d" > -10),
constraint "Test_check9_I d_check2" check ("I d" < 10));
\d+ "Test_check9"
select is_system_named from sys.check_constraints where name = 'Test_check9_I d_check';
select is_system_named from sys.check_constraints where name = 'Test_check9_I d_check1';
select is_system_named from sys.check_constraints where name = 'Test_check9_I d_check2';

create table "Test_check10"("I d" int, idd int, iddd int, check("I d" < 4), check("I d" > -10),
constraint "Test_check10_I d_check2" check ("I d" < 10),
constraint "Test_check10_iddd_check2" check (iddd < 10));
\d+ "Test_check10"
select is_system_named from sys.check_constraints where name = 'Test_check10_I d_check';
select is_system_named from sys.check_constraints where name = 'Test_check10_I d_check1';
select is_system_named from sys.check_constraints where name = 'Test_check10_I d_check2';
select is_system_named from sys.check_constraints where name = 'Test_check10_iddd_check2';

create table test_check11(id int, idd int, iddd int, check(idd > 2 and id < 4 and iddd = 1),
check(idd > 2 and id < 4 and iddd = 1));
\d+ test_check11
select is_system_named from sys.check_constraints where name = 'test_check11_check';
select is_system_named from sys.check_constraints where name = 'test_check11_check1';

create table test_check12(id int, idd int, iddd int, check(idd > 2 and id < 4 and iddd = 1),
check(idd > 2 and iddd = 1));
\d+ test_check12
select is_system_named from sys.check_constraints where name = 'test_check12_check';
select is_system_named from sys.check_constraints where name = 'test_check12_check1';

drop schema if exists test_views1 cascade;