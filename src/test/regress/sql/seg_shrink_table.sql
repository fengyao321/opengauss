drop database if exists seg_shrink_db;
drop tablespace if exists seg_shrink_tbs;

create tablespace seg_shrink_tbs relative location 'seg_shrink_tbs';
create database seg_shrink_db tablespace seg_shrink_tbs;
\c seg_shrink_db;

-- testcase1: small table for ci
drop table if exists seg_test_basic;
drop table if exists seg_test_mix;
create table seg_test_basic (id bigint, value text, update_at time) with (segment=on);
create table seg_test_mix (id bigint, value char(8000)) with (segment=on);
create index seg_basic_idx on seg_test_basic using btree(id);
create index seg_mix_idx on seg_test_mix using btree(id);
-- basic1-mix1-basic2-basic3-mix2
insert into seg_test_basic(id,value) select t,t from generate_series(1,100000) t;
insert into seg_test_basic(id,value,update_at) select t,t,now() from generate_series(1,100000) t;
insert into seg_test_mix(id,value) select t,t from generate_series(1,30000) t;
insert into seg_test_basic(id,value,update_at) select t,t,now() from generate_series(150001,200000) t;
insert into seg_test_basic(id,value,update_at) select t,t,now() from generate_series(1,50000) t;
insert into seg_test_mix(id,value) select t,t from generate_series(1,30000) t;

select count(*) from seg_test_basic;
select count(*) from seg_test_mix;

-- delete 15w rows, basic1 and basic3
select count(*) from seg_test_basic where id < 100001;
delete from seg_test_basic where id < 100001;

-- hot tuple
select id,value,ctid from seg_test_basic where id <= 150005 order by id;
update seg_test_basic set value = 'updated_1_' || id, update_at = now() where id <= 150005;
select id,value,ctid from seg_test_basic where id <= 150005 order by id;
update seg_test_basic set value = 'updated_2_' || id, update_at = now() where id <= 150005;
select id,value,ctid from seg_test_basic where id <= 150005 order by id;
select count(*) from seg_test_basic;

select pg_sleep(3);
VACUUM seg_test_basic;
VACUUM FREEZE seg_test_basic;

-- failed case
select * from gs_table_shrink('seg_test_basicbasic','seg_shrink_tbstbs','regression'); --error rel
select * from gs_table_shrink('seg_test_basic','seg_shrink_tbstbs','seg_shrink_db'); --error tbs
select * from gs_table_shrink('seg_test_basic','seg_shrink_tbs','seg_shrink_dbdb'); --error db
select * from gs_table_shrink('seg_test_basic','seg_shrink_tbs','regression'); --other db
select * from gs_space_shrink_compact('seg_shrink_tbstbs', 'seg_shrink_db'); --error tbs
select * from gs_space_shrink_compact('seg_shrink_tbs', 'seg_shrink_dbdb'); --error db
select * from gs_space_shrink_compact('seg_shrink_tbs', 'regression'); --other db

select pg_sleep(2);
VACUUM seg_test_basic;
VACUUM FREEZE seg_test_basic;

explain (costs off) select /*+ tablescan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;
select /*+ tablescan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;
explain (costs off) select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;
select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;

select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;
select * from gs_table_shrink('seg_test_basic','seg_shrink_tbs','seg_shrink_db');
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;
select * from gs_space_shrink_compact('seg_shrink_tbs', 'seg_shrink_db');
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;

-- index read blocks
explain (costs off) select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;
select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;

-- check index status
select c.relname as index_name, i.indisusable FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_class t ON t.oid = i.indrelid WHERE t.relname = 'seg_test_basic';

select count(*) from seg_test_basic;

REINDEX index seg_basic_idx;

select c.relname as index_name, i.indisusable FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_class t ON t.oid = i.indrelid WHERE t.relname = 'seg_test_basic';
explain (costs off) select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;
select /*+ indexscan(seg_test_basic)*/ id,value,ctid from seg_test_basic where id <= 150005 order by id;

select count(*) from seg_test_basic;
insert into seg_test_basic(id,value,update_at) select t,t,now() from generate_series(501,700) t;
select count(*) from seg_test_basic;
select id from seg_test_basic where id < 505 order by id;
update seg_test_basic set id=id+1000000 where id < 505;
select id from seg_test_basic where id > 1000000 order by id;
delete from seg_test_basic where id > 1000000;

select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;
drop table seg_test_basic;
drop table seg_test_mix;
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;
select * from gs_space_shrink_compact('seg_shrink_tbs', 'seg_shrink_db');
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;

-- testcase2: dont support compress table
drop table if exists seg_compress_table;
create table seg_compress_table (id bigint, value char(8000)) with (compresstype=2, segment=on);
select * from gs_table_shrink('seg_compress_table','seg_shrink_tbs','seg_shrink_db');
drop table seg_compress_table;
select * from gs_space_shrink_compact('seg_shrink_tbs', 'seg_shrink_db');
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;

-- testcase3: dont support subpartition table
drop table if exists seg_range_list_sales;
create table seg_range_list_sales( customer_id INT4 NOT NULL, channel_id CHAR(1))
WITH (segment=on) PARTITION BY RANGE (customer_id) SUBPARTITION BY LIST (channel_id) (
    PARTITION customer1 VALUES LESS THAN (20)( SUBPARTITION customer1_channel1 VALUES ('0', '1', '2'), SUBPARTITION customer1_channel4 VALUES (DEFAULT)),
    PARTITION customer2 VALUES LESS THAN (120)( SUBPARTITION customer2_channel1 VALUES ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')));
select * from gs_table_shrink('seg_range_list_sales','seg_shrink_tbs','seg_shrink_db');
drop table seg_range_list_sales;
select * from gs_space_shrink_compact('seg_shrink_tbs', 'seg_shrink_db');
select * from local_segment_space_info('seg_shrink_tbs','seg_shrink_db') where forknum=0 and extent_size > 1 order by extent_size;

\c regression;
drop database if exists seg_shrink_db;
drop tablespace if exists seg_shrink_tbs;
