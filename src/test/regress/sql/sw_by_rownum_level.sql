set client_min_messages = error;
set search_path=swtest;
SET CLIENT_ENCODING='UTF8';

--accepted cases
explain (costs off)
select * from test_area CONNECT BY LEVEL <= LENGTH('SOME TEXT');
explain (costs off)
select *, LEVEL from test_area CONNECT BY LEVEL <= LENGTH('SOME TEXT');

explain (costs off)
select * from test_area CONNECT BY ROWNUM <= LENGTH('SOME TEXT');
explain (costs off)
select *, ROWNUM from test_area CONNECT BY ROWNUM <= LENGTH('SOME TEXT');

explain (costs off)
select * from test_area CONNECT BY LEVEL < LENGTH('SOME TEXT');
explain (costs off)
select *, LEVEL from test_area CONNECT BY LEVEL < LENGTH('SOME TEXT');

explain (costs off)
select * from test_area CONNECT BY ROWNUM < LENGTH('SOME TEXT');
explain (costs off)
select *, ROWNUM from test_area CONNECT BY ROWNUM < LENGTH('SOME TEXT');

--rejected cases
explain (costs off)
select *, LEVEL from test_area CONNECT BY LEVEL > LENGTH('SOME TEXT');
explain (costs off)
select *, LEVEL from test_area CONNECT BY LEVEL >= LENGTH('SOME TEXT');
explain (costs off)
select * from test_area CONNECT BY APPLE > LENGTH('SOME TEXT');
explain (costs off)
select * from test_area CONNECT BY APPLE < LENGTH('SOME TEXT');
explain (costs off)
select * from test_area CONNECT BY APPLE <= LENGTH('SOME TEXT');

-- materialized view with column name 'level' 'connect_by_isleaf' 'connect_by_iscycle'
create table startwith_t(id int, level int, connect_by_isleaf int, connect_by_iscycle int);
create materialized view startwith_mv as 
    WITH RECURSIVE t(id, level, connect_by_isleaf, connect_by_iscycle) as (select * from startwith_t)
    select t.id, t.connect_by_isleaf as level, t.level as connect_by_isleaf from t;
select pg_get_viewdef('startwith_mv', true);

drop materialized view startwith_mv;
drop table startwith_t;

create table ta(a int,b int);
insert into ta values(1,1),(2,2),(3,3);


select * from ta left join
(SELECT -3.0 c1) AS test on c1=c1
start with a != 1
CONNECT BY NOCYCLE  (PRIOR c1) BETWEEN -6.7 AND 0.619;

drop table ta;

