-- sys.sequences
\d sys.sequences

drop schema if exists test_views6 cascade;
create schema test_views6;
set current_schema to test_views6;

create sequence seq1;

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published from sys.objects where name = 'seq1';
select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published from sys.sequences where name = 'seq1';

select count(*) from sys.objects obj inner join pg_class pc on pc.oid = obj.object_id
  where obj.name = 'seq1';
select count(*) from sys.sequences obj inner join pg_class pc on pc.oid = obj.object_id
  where obj.name = 'seq1';

select count(*) from sys.objects obj inner join pg_class pc on pc.oid = obj.object_id
  inner join pg_namespace np on np.oid = obj.schema_id
  where obj.name = 'seq1';
select count(*) from sys.sequences obj inner join pg_class pc on pc.oid = obj.object_id
  inner join pg_namespace np on np.oid = obj.schema_id
  where obj.name = 'seq1';

select count(*) from sys.objects obj inner join pg_class pc on pc.oid = obj.object_id
  inner join pg_namespace np on np.oid = obj.schema_id
  inner join pg_object po on po.object_oid = pc.oid and po.ctime = obj.create_date
  and po.mtime = obj.modify_date 
  where obj.name = 'seq1';

select count(*) from sys.sequences obj inner join pg_class pc on pc.oid = obj.object_id
  inner join pg_namespace np on np.oid = obj.schema_id
  inner join pg_object po on po.object_oid = pc.oid and po.ctime = obj.create_date
  and po.mtime = obj.modify_date 
  where obj.name = 'seq1';

select * from seq1;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq1';

create sequence seq2 increment by 2 minvalue 10 maxvalue 30 cycle;
select * from seq2;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq2';

create sequence seq3 increment by 2 cache 5;
select * from seq3;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq3';

create sequence seq4 increment by 2 start with 15 minvalue 10 maxvalue 30 cycle;
select * from seq4;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq4';

create large sequence seq11;
select * from seq11;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq11';

create large sequence seq22 increment by 2 minvalue 10 maxvalue 30 cycle;
select * from seq22;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq22';

create large sequence seq33 increment by 2 cache 5;
select * from seq33;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq33';

create large sequence seq44 increment by 2 start with 15 minvalue 10 maxvalue 30 cycle;
select * from seq44;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq44';

create large sequence seq55 increment by 12345678901234567890
start with 12345678901234567890
minvalue 12345678901234567890
maxvalue 170141183460469231731687303715884105700 cycle;
select * from seq55;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq55';

drop sequence if exists seq4;
create sequence seq4 increment by 5 minvalue 10 maxvalue 20;
select * from seq4;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq4';
select currval('seq4'); -- error
select nextval('seq4');
select * from seq4;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq4';
select currval('seq4');
select nextval('seq4');
select * from seq4;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq4';
select currval('seq4');
select nextval('seq4');
select * from seq4;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq4';
select currval('seq4');
select nextval('seq4'); -- error, exhausted
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq4';

drop sequence if exists seq5;
create sequence seq5 increment by 5 minvalue 10 maxvalue 20 cycle;
select * from seq5;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq5';
select currval('seq5'); --error
select nextval('seq5');
select * from seq5;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq5';
select currval('seq5');
select nextval('seq5');
select * from seq5;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq5';
select currval('seq5');
select nextval('seq5');
select * from seq5;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq5';
select currval('seq5');
select nextval('seq5');
select * from seq5;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq5';
select currval('seq5');
select nextval('seq5');

create sequence seq6 increment by 5 minvalue 4 maxvalue 5;
select * from seq6;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq6';
select currval('seq6'); -- error
select nextval('seq6');
select * from seq6;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq6';
select currval('seq6');
select nextval('seq6'); -- error, exhausted
select * from seq6;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq6';

create sequence seq7 increment by -2 minvalue -2 maxvalue 2;
select * from seq7;
select start_value, increment, minimum_value, maximum_value, is_cycling, is_cached, cache_size,
  system_type_id, user_type_id, precision, scale, current_value, is_exhausted, last_used_value
  from sys.sequences where name = 'seq7';
select currval('seq7'); -- error
select nextval('seq7');
select * from seq7;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq7';
select currval('seq7');
select nextval('seq7');
select * from seq7;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq7';
select currval('seq7');
select nextval('seq7');
select * from seq7;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq7';
select currval('seq7');
select nextval('seq7'); -- error, exhausted
select * from seq7;
select current_value, is_exhausted, last_used_value from sys.sequences where name = 'seq7';

drop schema test_views6 cascade;