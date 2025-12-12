-- sys.configurations
\d sys.configurations

select name, value, minimum, maximum, value_in_use, description from sys.configurations order by name limit 2;
select name, setting, min_val, max_val, setting, short_desc from pg_settings order by name limit 2;

select distinct is_advanced from sys.configurations;
select distinct configuration_id from sys.configurations;

select name, context from pg_settings where name in ('block_size', 'advance_xlog_file_num',
  'acce_min_datasize_per_thread', 'ignore_system_indexes', 'alarm_report_interval', 'autoanalyze');

select name, is_dynamic from sys.configurations where name in ('block_size', 'advance_xlog_file_num');
select name, is_dynamic from sys.configurations where name in ('acce_min_datasize_per_thread',
  'ignore_system_indexes', 'alarm_report_interval', 'autoanalyze');

-- sys.syscurconfigs
\d sys.syscurconfigs

select value, comment from sys.syscurconfigs limit 2;
select setting, short_desc from pg_settings limit 2;

select distinct config from sys.syscurconfigs;
select status from sys.syscurconfigs con inner join pg_settings ps on con.comment = ps.short_desc
  where ps.name in ('block_size', 'advance_xlog_file_num');
select status from sys.syscurconfigs con inner join pg_settings ps on con.comment = ps.short_desc
  where ps.name in ('acce_min_datasize_per_thread', 'ignore_system_indexes', 'alarm_report_interval',
  'autoanalyze');

-- sys.sysconfigures
\d sys.sysconfigures

select value, comment from sys.syscurconfigs limit 2;
select setting, short_desc from pg_settings limit 2;

select distinct config from sys.syscurconfigs;
select status from sys.syscurconfigs con inner join pg_settings ps on con.comment = ps.short_desc
  where ps.name in ('block_size', 'advance_xlog_file_num');
select status from sys.syscurconfigs con inner join pg_settings ps on con.comment = ps.short_desc
  where ps.name in ('acce_min_datasize_per_thread', 'ignore_system_indexes', 'alarm_report_interval',
  'autoanalyze');
