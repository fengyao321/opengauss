CREATE schema schma_rangefuncs_with_ordinality;
set current_schema = schma_rangefuncs_with_ordinality;
CREATE TABLE rngfunc2(rngfuncid int, f2 int);
INSERT INTO rngfunc2 VALUES(1, 11);
INSERT INTO rngfunc2 VALUES(2, 22);
INSERT INTO rngfunc2 VALUES(1, 111);

CREATE FUNCTION rngfunct(int) returns setof rngfunc2 as 'SELECT * FROM rngfunc2 WHERE rngfuncid = $1 ORDER BY f2;' LANGUAGE SQL;

CREATE FUNCTION f1 (a out int) return int as 
begin
return 1;
end;
/

create table t2 (a int);
insert into t2 values(1);
insert into t2 values(2);

-- function with ORDINALITY
select * from rngfunct(1) with ordinality as z(a,b,ord);
select * from rngfunct(1) with ordinality as z(a,b,ord) where b > 100;   -- ordinal 2, not 1
-- ordinality vs. column names and types
select a,b,ord from rngfunct(1) with ordinality as z(a,b,ord);
select a,ord from unnest(array['a','b']) with ordinality as z(a,ord);
select * from unnest(array['a','b']) with ordinality as z(a,ord);
select a,ord from unnest(array[1.0::float8]) with ordinality as z(a,ord);
select * from unnest(array[1.0::float8]) with ordinality as z(a,ord);
select row_to_json(s.*) from generate_series(11,14) with ordinality s;
select * from f1() with ordinality ; -- out parameter
-- table function join / left join
select a.rngfuncid, ab, aord, bb, bord from rngfunct(1) with ordinality a(rngfuncid, ab, aord)
  JOIN rngfunct(2) with ordinality b(rngfuncid, bb, bord) ON (a.aord = b.bord) order by 1,2,3,4,5;

select a.rngfuncid, ab, aord, bb, bord from rngfunct(1) with ordinality a(rngfuncid, ab, aord)
  LEFT JOIN rngfunct(2) with ordinality b(rngfuncid, bb, bord) ON (a.rngfuncid = b.rngfuncid) order by 1,2,3,4,5;

select * from t2 where exists (select ord from f1() with ordinality as f1(a, ord));
drop table t2;
drop function f1;
-- ordinality vs. views
create temporary view vw_ord as select * from (values (1)) v(n) join rngfunct(1) with ordinality as z(a,b,ord) on (n=ord);
select * from vw_ord;
select definition from pg_views where viewname='vw_ord';
drop view vw_ord;

create temporary view vw_ord as select * from (values (1)) v(n) join (select * from rngfunct(1) with ordinality) as z(a,b,ord) on (n=ord);
select * from vw_ord;
select definition from pg_views where viewname='vw_ord';
drop view vw_ord;

create temporary view vw_ord as select * from (values (1)) v(n) join (select * from rngfunct(1) with ordinality UNION ALL select * from rngfunct(2) with ordinality) as z(a,b,ord) on (n=ord);
select * from vw_ord;
select definition from pg_views where viewname='vw_ord';
drop view vw_ord;

-- function with implicit LATERAL and explicit ORDINALITY
select * from rngfunc2, rngfunct(rngfunc2.rngfuncid) with ordinality as z(rngfuncid,f2,ord) where rngfunc2.f2 = z.f2;
select * from rngfunc2, lateral rngfunct(rngfunc2.rngfuncid) with ordinality as z(rngfuncid,f2,ord) where rngfunc2.f2 = z.f2;

CREATE TABLE rngfunc (rngfuncid int, rngfuncsubid int, rngfuncname text, primary key(rngfuncid,rngfuncsubid));
INSERT INTO rngfunc VALUES(1,1,'Joe');
INSERT INTO rngfunc VALUES(1,2,'Ed');
INSERT INTO rngfunc VALUES(2,1,'Mary');

-- sql, proretset = f, prorettype = b
CREATE FUNCTION getrngfunc1(int) RETURNS int AS 'SELECT $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc1(1) AS t1;
SELECT * FROM getrngfunc1(1) WITH ORDINALITY AS t1(v,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc1(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc1(1) WITH ORDINALITY as t1(v,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = t, prorettype = b
CREATE FUNCTION getrngfunc2(int) RETURNS setof int AS 'SELECT rngfuncid FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc2(1) AS t1;
SELECT * FROM getrngfunc2(1) WITH ORDINALITY AS t1(v,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc2(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc2(1) WITH ORDINALITY AS t1(v,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = t, prorettype = b
CREATE FUNCTION getrngfunc3(int) RETURNS setof text AS 'SELECT rngfuncname FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc3(1) AS t1;
SELECT * FROM getrngfunc3(1) WITH ORDINALITY AS t1(v,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc3(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc3(1) WITH ORDINALITY AS t1(v,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = f, prorettype = c
CREATE FUNCTION getrngfunc4(int) RETURNS rngfunc AS 'SELECT * FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc4(1) AS t1;
SELECT * FROM getrngfunc4(1) WITH ORDINALITY AS t1(a,b,c,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc4(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc4(1) WITH ORDINALITY AS t1(a,b,c,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = t, prorettype = c
CREATE FUNCTION getrngfunc5(int) RETURNS setof rngfunc AS 'SELECT * FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc5(1) AS t1;
SELECT * FROM getrngfunc5(1) WITH ORDINALITY AS t1(a,b,c,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc5(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc5(1) WITH ORDINALITY AS t1(a,b,c,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = f, prorettype = record
CREATE FUNCTION getrngfunc6(int) RETURNS RECORD AS 'SELECT * FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc6(1) AS t1(rngfuncid int, rngfuncsubid int, rngfuncname text);
CREATE VIEW vw_getrngfunc AS
  SELECT * FROM getrngfunc6(1) AS (rngfuncid int, rngfuncsubid int, rngfuncname text);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- sql, proretset = t, prorettype = record
CREATE FUNCTION getrngfunc7(int) RETURNS setof record AS 'SELECT * FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc7(1) AS t1(rngfuncid int, rngfuncsubid int, rngfuncname text);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc7(1) AS
(rngfuncid int, rngfuncsubid int, rngfuncname text);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- plpgsql, proretset = f, prorettype = b
CREATE FUNCTION getrngfunc8(int) RETURNS int AS 'DECLARE rngfuncint int; BEGIN SELECT rngfuncid into rngfuncint FROM rngfunc WHERE rngfuncid = $1 LIMIT 1; RETURN rngfuncint; END;' LANGUAGE plpgsql;
SELECT * FROM getrngfunc8(1) AS t1;
SELECT * FROM getrngfunc8(1) WITH ORDINALITY AS t1(v,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc8(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc8(1) WITH ORDINALITY AS t1(v,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- plpgsql, proretset = f, prorettype = c
CREATE FUNCTION getrngfunc9(int) RETURNS rngfunc AS 'DECLARE rngfunctup rngfunc%ROWTYPE; BEGIN SELECT * into rngfunctup FROM rngfunc WHERE rngfuncid = $1 LIMIT 1; RETURN rngfunctup; END;' LANGUAGE plpgsql;
SELECT * FROM getrngfunc9(1) AS t1;
SELECT * FROM getrngfunc9(1) WITH ORDINALITY AS t1(a,b,c,o);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc9(1);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc9(1) WITH ORDINALITY AS t1(a,b,c,o);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- not supported
CREATE FUNCTION getrngfunc10(int) RETURNS RECORD AS 'SELECT * FROM rngfunc WHERE rngfuncid = $1;' LANGUAGE SQL;
SELECT * FROM getrngfunc10(1) WITH ORDINALITY t1(rngfuncid int, rngfuncsubid int, rngfuncname text);
SELECT * FROM getrngfunc10(1) WITH ORDINALITY AS t1 (rngfuncid int, rngfuncsubid int, rngfuncname text);
CREATE VIEW vw_getrngfunc AS SELECT * FROM getrngfunc10(1) WITH ORDINALITY AS
(rngfuncid int, rngfuncsubid int, rngfuncname text);
SELECT * FROM vw_getrngfunc;
DROP VIEW vw_getrngfunc;

-- named subquery expose alias
select ord, f1.ord, f1.a from (SELECT * FROM getrngfunc1(1) WITH ORDINALITY) f1(a, ord);

-- returing ordinality
create table t1 (a int);
insert into t1 values(1);
update t1 set t1.a = ff.ordinality + 2 from getrngfunc1(1) with ordinality ff(a) where t1.a = ff.a returning ff.ordinality;
drop table t1;

-- merge/update/delete using..
CREATE TABLE t1 (a int, b int);
INSERT INTO t1 VALUES(1, 11);
INSERT INTO t1 VALUES(2, 22);
CREATE TABLE t2(rngfuncid int);
INSERT INTO t2 VALUES(1);
INSERT INTO t2 VALUES(2);
CREATE FUNCTION t1_func1(int) returns setof t2 as 'SELECT * FROM t2 WHERE rngfuncid = $1 ORDER BY rngfuncid;' LANGUAGE SQL;

merge into t1 using t1_func1(1) with ordinality as f1(a, ord)
on t1.a = f1.a
when matched then
    update set t1.b = f1.ord;

update t1 set t1.b = f1.ord from t1_func1(2) with ordinality f1(a, ord)
    where t1.a = f1.a;

delete from t1 using t1_func1(1) with ordinality f1(a, ord)
    where t1.a = f1.ord;

DROP FUNCTION getrngfunc1(int);
DROP FUNCTION getrngfunc2(int);
DROP FUNCTION getrngfunc3(int);
DROP FUNCTION getrngfunc4(int);
DROP FUNCTION getrngfunc5(int);
DROP FUNCTION getrngfunc6(int);
DROP FUNCTION getrngfunc7(int);
DROP FUNCTION getrngfunc8(int);
DROP FUNCTION getrngfunc9(int);
DROP FUNCTION getrngfunc10(int);
DROP FUNCTION rngfunct(int);
DROP TABLE rngfunc2;
DROP TABLE rngfunc;
DROP TABLE t1;

DROP SCHEMA schma_rangefuncs_with_ordinality cascade;
