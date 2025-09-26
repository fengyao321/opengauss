select newid();
select newid();
select sys.newid();
select newid(1); --error
\df newid
\sf newid
select pg_typeof(newid());
