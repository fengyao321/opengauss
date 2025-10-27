select newid();
select newid();
select sys.newid();
select newid(1); --error
\df newid
\sf newid
select pg_typeof(newid());

CREATE TABLE tab_rep_next(a) AS SELECT generate_series(1,10);
select * from tab_rep_next;
