CREATE OR REPLACE FUNCTION Update_pg_amproc_temp()
RETURNS void AS $$
DECLARE
query_str text;
BEGIN
query_str := 'update pg_catalog.pg_am set amhandler = 8208 where amname = ''hnsw'' and amhandler = 0';
EXECUTE(query_str);
query_str := 'update pg_catalog.pg_am set amhandler = 8206 where amname = ''ivfflat'' and amhandler = 0';
EXECUTE(query_str);
query_str := 'update pg_catalog.pg_am set amhandler = 8532 where amname = ''diskann'' and amhandler = 0';
EXECUTE(query_str);
return;
END; $$ LANGUAGE 'plpgsql';

SELECT Update_pg_amproc_temp();
DROP FUNCTION Update_pg_amproc_temp();