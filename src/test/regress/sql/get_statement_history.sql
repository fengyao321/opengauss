\c postgres

-- record slow sql
set log_min_duration_statement = 50;
set track_stmt_stat_level = 'OFF,L0';
show log_min_duration_statement;
show track_stmt_stat_level;
delete from statement_history;
select pg_sleep(1);
select count(1) from dbe_perf.get_statement_history('1970-01-01 00:00:00', now()) limit 0;
select count(1) from dbe_perf.get_statement_history(now(), '1970-01-01 00:00:00') limit 0;
select count(1) from dbe_perf.get_statement_history(NULL, NULL) limit 0;
delete from statement_history;
