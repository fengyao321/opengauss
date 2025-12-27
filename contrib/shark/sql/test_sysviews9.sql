drop schema if exists test_views4 cascade;
create schema test_views4;
set current_schema to test_views4;

-- sys.system_objects
\d sys.system_objects

select distinct type, type_desc from sys.system_objects order by type;

select count(distinct schema_id) from sys.system_objects;

select distinct pn.nspname as schema_name from pg_namespace pn inner join sys.system_objects so on pn.oid = so.schema_id
  order by schema_name;

-- sys.all_views
\d sys.all_views

drop table if exists test1 cascade;
create table test1(id int, name varchar(50));
create view view1 as select * from test1;
create view view2 as select * from test1 with check option;
create materialized view mat_view as select * from test1;

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view
  from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'view1' and s.nspname = 'test_views4';

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view, is_tracked_by_cdc
  from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'view1' and s.nspname = 'test_views4';

select count(*) from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'view1' and s.nspname = 'test_views4';

select count(*) from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'view1' and s.nspname = 'test_views4';

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view
  from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'view2' and s.nspname = 'test_views4';

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view, is_tracked_by_cdc
  from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'view2' and s.nspname = 'test_views4';

select count(*) from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'view2' and s.nspname = 'test_views4';

select count(*) from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'view2' and s.nspname = 'test_views4';

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view
  from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'mat_view' and s.nspname = 'test_views4';

select name, principal_id, parent_object_id, type, type_desc, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view, is_tracked_by_cdc
  from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'mat_view' and s.nspname = 'test_views4';

select count(*) from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'mat_view' and s.nspname = 'test_views4';

select count(*) from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  inner join pg_object o on o.ctime = v.create_date and o.mtime = v.modify_date
  where v.name = 'mat_view' and s.nspname = 'test_views4';

select v.* from sys.views v inner join pg_namespace s on v.schema_id = s.oid
 where v.name = 'tables' and s.nspname = 'information_schema'; --empty

select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view, is_tracked_by_cdc
  from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'tables' and s.nspname = 'information_schema';

select count(*) from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  where v.name = 'tables' and s.nspname = 'information_schema';

select v.* from sys.views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'columns' and s.nspname = 'information_schema'; --empty

select name, principal_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped,
  is_published, is_schema_published, is_replicated, has_replication_filter, has_opaque_metadata,
  has_unchecked_assembly_data, with_check_option, is_date_correlation_view, is_tracked_by_cdc
  from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  where v.name = 'columns' and s.nspname = 'information_schema';

select count(*) from sys.all_views v inner join pg_namespace s on v.schema_id = s.oid
  inner join pg_class t on t.oid = v.object_id
  where v.name = 'columns' and s.nspname = 'information_schema';

drop schema test_views4 cascade;
