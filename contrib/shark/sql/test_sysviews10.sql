drop schema if exists test_views5 cascade;
create schema test_views5;
set current_schema to test_views5;

-- sys.sysprocesses
\d sys.sysprocesses

select kpid, waittype, waittime, lastwaittype, waitresource, cpu, physical_io, memusage, ecid,
  open_tran, hostprocess, nt_domain, nt_username, net_address, net_library, context_info, sql_handle,
  stmt_start, stmt_end from sys.sysprocesses limit 1;

-- sys.index_columns
\d sys.index_columns

create table test(id int primary key, name varchar(10));
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('test');

create table sales_range (
    id          int,
    product     varchar(100),
    sale_date   date
) with (storage_type = ustore);
create index idx on sales_range using ubtree (id) include (product);
create columnstore index idx1 on sales_range (id) include (sale_date);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range') order by index_id, index_column_id;

create table sales_range1 (
    id          int,
    product     varchar(100),
    sale_date   date
);
create index ix_sales_id_desc_date_asc on sales_range1 (id desc, sale_date asc);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range1');

create table sales_range2 (
    id          int,
    product     varchar(100),
    sale_date   date
);
create index sales_range2_lower on sales_range2 (lower(product));
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range2');

create table sales_range3 (
    id          int,
    product     varchar(100),
    sale_date   date
)
partition by range (sale_date) (
    partition p2023 values less than ('2024-01-01'),
    partition p2024 values less than ('2025-01-01'),
    partition p_max values less than (maxvalue)
);
create index index1 on sales_range3(sale_date);
create index index2 on sales_range3(sale_date, id);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range3') order by index_id, index_column_id;

create table sales (
    id          int,
    region_id   int,
    sale_date   date,
    amount      decimal(10,2)
)
partition by range (region_id, sale_date)
(
    partition p1 values less than (1, '2024-01-01'),
    partition p2 values less than (2, '2025-01-01'),
    partition p3 values less than (3, '2026-01-01'),
    partition p4 values less than (maxvalue, maxvalue)
);
create index sales_index1 on sales(id);
create index sales_index2 on sales(region_id, sale_date);
create index sales_index3 on sales(id, amount);
create index sales_index4 on sales(id, sale_date);
create index sales_index5 on sales(id, sale_date, region_id);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales') order by index_id, index_column_id;

create table sales1 (
    id          int,
    region_id   int,
    sale_date   date,
    amount      decimal(10,2)
)
partition by range (abs(id))
(
    partition p1 values less than (2024),
    partition p2 values less than (2025),
    partition p3 values less than (2026),
    partition p4 values less than (maxvalue)
);
create index sales1_index1 on sales1 (id);
create index sales1_index2 on sales1 (region_id, sale_date);
create index sales1_index3 on sales1 (id, amount);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales1') order by index_id, index_column_id;

create table sales2 (
    id          int,
    region_id   int,
    sale_date   date,
    amount      decimal(10,2)
) with (storage_type = ustore)
partition by range (abs(id))
(
    partition p1 values less than (2024),
    partition p2 values less than (2025),
    partition p3 values less than (2026),
    partition p4 values less than (maxvalue)
);
create index idx22 on sales2 using ubtree (id) include (amount);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales2');

create table range_range(id int, gender varchar not null, birthday date not null)
partition by range (id) subpartition by range (birthday)
(
    partition p_1 values less than(100)
    (
            subpartition p_1_a values less than('2022-01-01'),
            subpartition p_1_b values less than(MAXVALUE)
    ),
    partition p_2 values less than(200)
    (
            subpartition p_2_a values less than('2022-01-01'),
            subpartition p_2_b values less than(MAXVALUE)
    ),
    partition p_3 values less than(MAXVALUE)
    (
            subpartition p_3_a values less than('2022-01-01'),
            subpartition p_3_b values less than(MAXVALUE)
    )
);
insert into range_range values(198,'boy','2010-02-15'),(33,'boy','2003-08-11'),(78,'girl','2014-06-24');
insert into range_range values(233,'girl','2010-01-01'),(360,'boy','2007-05-14'),(146,'girl','2005-03-08');
insert into range_range values(111,'girl','2013-11-19'),(15,'girl','2009-01-12'),(156,'boy','2011-05-21');

create index range_range_index1 on range_range(id);
create index range_range_index2 on range_range(id, gender);
create index range_range_index3 on range_range(id, birthday);
create index range_range_index4 on range_range(gender);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('range_range') order by index_id, index_column_id;

drop table if exists sales3;
create table sales3 (
    id          int,
    product     varchar(100),
    sale_date   date,
    num         int
);
create index sales3_upper on sales3 (upper(product));
create index sales3_index1 on sales3 (product);
create index sales3_abs on sales3 (abs(id));
create index sales3_index2 on sales3 (id);
create index sales3_abs2 on sales3 (abs(id + num));
create index sales3_index3 on sales3 (id, num);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales3') order by index_id, index_column_id;

drop table if exists sales3;
create table sales3 (
    id          int,
    product     varchar(100),
    sale_date   date,
    num         int,
    product_lower as lower(product) persisted
);
create index ix_sales3_product_lower on sales3 (product_lower);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales3');

drop table if exists sales1;
create table sales1 (
    id          int,
    region_id   int,
    sale_date   date,
    amount      decimal(10,2)
)
partition by range (abs(id))
(
    partition p1 values less than (2024),
    partition p2 values less than (2025),
    partition p3 values less than (2026),
    partition p4 values less than (maxvalue)
);
create index sales1_index1 on sales1 (id);
create index sales1_index2 on sales1 (id, region_id);
create index sales1_index3 on sales1 (region_id, sale_date);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales1') order by index_id, index_column_id;

drop table if exists sales1;
create table sales1 (
    id          int,
    region_id   int,
    sale_date   date,
    amount      decimal(10,2)
)
partition by range (id)
(
    partition p1 values less than (2024),
    partition p2 values less than (2025),
    partition p3 values less than (2026),
    partition p4 values less than (maxvalue)
);
create index sales1_index1 on sales1 (id);
create index sales1_index2 on sales1 (id, region_id);
create index sales1_index3 on sales1 (region_id, sale_date);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales1') order by index_id, index_column_id;

drop table if exists sales_range;
CREATE TABLE sales_range (
    id          INT,
    product     VARCHAR(100),
    sale_date   DATE,
    region_id   INT,
    amount      NUMERIC
)
PARTITION BY RANGE (sale_date, region_id) (
    PARTITION p1 VALUES LESS THAN ('2023-01-01', 100),
    PARTITION p2 VALUES LESS THAN ('2023-01-01', 200),
    PARTITION p3 VALUES LESS THAN ('2024-01-01', 100),
    PARTITION p4 VALUES LESS THAN ('2024-01-01', MAXVALUE),
    PARTITION p5 VALUES LESS THAN (MAXVALUE, MAXVALUE)
);
create index sales_range_index1 on sales_range(id);
create index sales_range_index2 on sales_range(id, sale_date, region_id);
create index sales_range_index3 on sales_range(id, sale_date);
create index sales_range_index4 on sales_range(id, region_id);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range') order by index_id, index_column_id;

CREATE TABLE sales_list (
    id        INT,
    product   VARCHAR(100),
    region_id INT,
    channel   VARCHAR(20),
    amount    NUMERIC
)
PARTITION BY LIST (region_id, channel) (
    PARTITION p_north_online  VALUES ((1, 'online'), (1, 'web')),
    PARTITION p_south_offline VALUES ((2, 'offline'), (2, 'store')),
    PARTITION p_other         VALUES (DEFAULT)
);
create index sales_list_index1 on sales_list(id, region_id);
create index sales_list_index2 on sales_list(id, channel);
create index sales_list_index3 on sales_list(id, channel, region_id);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_list') order by index_id, index_column_id;

drop table if exists sales_range;
CREATE TABLE sales_range (
    id          INT,
    product     VARCHAR(100),
    sale_date   DATE,
    region_id   INT,
    amount      NUMERIC
)
PARTITION BY RANGE (id, region_id) (
    PARTITION p1 VALUES LESS THAN (10, 100),
    PARTITION p2 VALUES LESS THAN (20, 200),
    PARTITION p3 VALUES LESS THAN (30, 300),
    PARTITION p4 VALUES LESS THAN (40, 400),
    PARTITION p5 VALUES LESS THAN (MAXVALUE, MAXVALUE)
);
create index sales_range_index1 on sales_range(id);
create index sales_range_index2 on sales_range(id, sale_date, region_id);
create index sales_range_index3 on sales_range(id, sale_date);
create index sales_range_index4 on sales_range(id, region_id);
create index sales_range_index5 on sales_range(region_id, amount);
select index_column_id, column_id, key_ordinal, partition_ordinal, is_descending_key, is_included_column
  from sys.index_columns where object_id = object_id('sales_range') order by index_id, index_column_id;

drop table if exists sales_range;
CREATE TABLE sales_range (
    id          INT,
    product     VARCHAR(100),
    sale_date   DATE,
    region_id   INT,
    amount      NUMERIC
)
PARTITION BY RANGE (abs(id), region_id) (
    PARTITION p1 VALUES LESS THAN (10, 100),
    PARTITION p2 VALUES LESS THAN (20, 200),
    PARTITION p3 VALUES LESS THAN (30, 300),
    PARTITION p4 VALUES LESS THAN (40, 400),
    PARTITION p5 VALUES LESS THAN (MAXVALUE, MAXVALUE)
);

drop schema if exists test_views5 cascade;