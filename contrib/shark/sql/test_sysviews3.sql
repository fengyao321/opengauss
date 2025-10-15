create schema sys_view_test3;
set search_path to sys_view_test3;

\d sys.identity_columns

CREATE TABLE products(
num int identity(1, 1),
QtyAvailable smallint,
UnitPrice money,
InventoryValue AS (QtyAvailable * UnitPrice)
);
select c.name, c.is_identity, c.is_computed from sys.columns c inner join pg_class t on t.oid = c.object_id
where t.relname = 'products' order by name;

select c.name, c.is_identity, c.is_computed from sys.identity_columns c inner join pg_class t on t.oid = c.object_id
where t.relname = 'products' order by name;

drop table if exists test_identity;
create table test_identity(col1 int identity(100,3), col2 serial, col3 varchar(50));
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc from sys.columns i inner join pg_class c
on c.oid = i.object_id where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test2');
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
delete from test_identity;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
truncate table test_identity;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'test_identity' order by name;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc from sys.columns i inner join pg_class c
on c.oid = i.object_id where c.relname = 'test_identity' order by name;

create view view1 as select * from test_identity;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'view1' order by name;

create view view2 as select col3 from test_identity;
select i.name, i.column_id, i.system_type_id, i.user_type_id, i.max_length, i.precision, i.scale, i.collation_name, i.is_nullable, 
i.is_ansi_padded, i.is_rowguidcol, i.is_identity, i.is_computed, i.is_filestream, i.is_replicated, i.is_non_sql_subscribed, i.is_merge_published, 
i.is_dts_replicated, i.is_xml_document, i.xml_collection_id, i.rule_object_id, i.is_sparse, i.is_column_set, i.generated_always_type,
i.generated_always_type_desc, i.encryption_type, i.encryption_type_desc, i.encryption_algorithm_name, i.column_encryption_key_id, 
i.column_encryption_key_database_name, i.is_hidden, i.is_masked, i.graph_type, i.graph_type_desc, i.seed_value, i.increment_value, 
i.last_value, i.is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id
where c.relname = 'view2' order by name;

select c.name, c.column_id, c.system_type_id, c.user_type_id, c.max_length, c.precision, c.scale, c.collation_name, c.is_nullable, 
c.is_ansi_padded, c.is_rowguidcol, c.is_identity, c.is_computed, c.is_filestream, c.is_replicated, c.is_non_sql_subscribed, c.is_merge_published, 
c.is_dts_replicated, c.is_xml_document, c.xml_collection_id, c.rule_object_id, c.is_sparse, c.is_column_set, c.generated_always_type,
c.generated_always_type_desc, c.encryption_type, c.encryption_type_desc, c.encryption_algorithm_name, c.column_encryption_key_id, 
c.column_encryption_key_database_name, c.is_hidden, c.is_masked, c.graph_type, c.graph_type_desc from sys.columns c
inner join pg_class t on c.object_id = t.oid
inner join pg_namespace s on t.relnamespace = s.oid
where s.nspname = 'sys_view_test3'
order by object_id, column_id;

select c.name, c.column_id, c.system_type_id, c.user_type_id, c.max_length, c.precision, c.scale, c.collation_name, c.is_nullable, 
c.is_ansi_padded, c.is_rowguidcol, c.is_identity, c.is_computed, c.is_filestream, c.is_replicated, c.is_non_sql_subscribed, c.is_merge_published, 
c.is_dts_replicated, c.is_xml_document, c.xml_collection_id, c.rule_object_id, c.is_sparse, c.is_column_set, c.generated_always_type,
c.generated_always_type_desc, c.encryption_type, c.encryption_type_desc, c.encryption_algorithm_name, c.column_encryption_key_id, 
c.column_encryption_key_database_name, c.is_hidden, c.is_masked, c.graph_type, c.graph_type_desc, c.seed_value, c.increment_value, 
c.last_value, c.is_not_for_replication from sys.identity_columns c
inner join pg_class t on c.object_id = t.oid
inner join pg_namespace s on t.relnamespace = s.oid
where s.nspname = 'sys_view_test3'
order by object_id, column_id;

drop table if exists test_identity;
create table test_identity(col1 int identity(100,3), col2 serial, col3 varchar(50));
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test2');
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
delete from test_identity;
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
truncate table test_identity;
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;
insert into test_identity(col3) values('test1');
select seed_value, increment_value, last_value, is_not_for_replication from sys.identity_columns i inner join pg_class c on c.oid = i.object_id where c.relname = 'test_identity' order by name;

create table test_identity2(col1 int identity(100,3), col2 varchar(50));
create view view3 as select * from test_identity2;
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('view3');
create view view4 as select col2 from test_identity2;
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('view4');

create table test_identity3(col1 int identity(100,3), col2 serial, col3 varchar(50));
select * from pg_get_serial_sequence('test_identity3', 'col1');
select * from pg_get_serial_sequence('test_identity3', 'col2');
select * from get_sequence_start_value('test_identity3_col1_seq_identity');
select * from get_sequence_increment_value('test_identity3_col1_seq_identity');
select * from get_sequence_last_value('test_identity3_col1_seq_identity');
select * from get_sequence_start_value('test_identity3_col2_seq');
select * from get_sequence_increment_value('test_identity3_col2_seq');
select * from get_sequence_last_value('test_identity3_col2_seq');
insert into test_identity3(col3) values('test');
select * from get_sequence_last_value('test_identity3_col1_seq_identity');
select * from get_sequence_last_value('test_identity3_col2_seq');

drop table if exists test_identity;
create table test_identity(col1 int identity(100,3), col2 varchar(50));
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
insert into test_identity(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
insert into test_identity(col2) values('test2');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
delete from test_identity;
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
insert into test_identity(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
truncate table test_identity;
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');
insert into test_identity(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity');

create table test_identity_large_sequence1(col1 bigint identity(-9223372036854775808, 3), col2 varchar(50));
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence1');
insert into test_identity_large_sequence1(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence1');

create table test_identity_large_sequence2(col1 bigint identity(9223372036854775806, 1), col2 varchar(50));
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence2');
insert into test_identity_large_sequence2(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence2');

create table test_identity_large_sequence3(col1 bigint identity(1, 9223372036854775806), col2 varchar(50));
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence3');
insert into test_identity_large_sequence3(col2) values('test1');
select seed_value, increment_value, last_value from sys.identity_columns where object_id = object_id('test_identity_large_sequence3');

reset search_path;
drop schema sys_view_test3 cascade;
