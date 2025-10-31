DROP VIEW IF EXISTS pg_catalog.pg_matviews;
/* pg_matviews */
CREATE VIEW pg_catalog.pg_matviews AS
    SELECT
        N.nspname AS schemaname,
        C.relname AS matviewname,
        /* current_user or superuser */
        pg_catalog.pg_get_userbyid(C.relowner) AS matviewowner,
        T.spcname AS tablespace,
        C.relhasindex AS hasindexes,
        M.ivm::bool AS isincremental,
        NULL::bool AS ispopulated,
        /* need schema privilegs */
        pg_catalog.pg_get_viewdef(C.oid) AS definition
    FROM pg_catalog.pg_class C
        LEFT JOIN pg_catalog.pg_namespace N ON (N.oid = C.relnamespace) 
        LEFT JOIN pg_catalog.pg_tablespace T ON (T.oid = C.reltablespace)
        INNER JOIN pg_catalog.gs_matview M ON (C.oid = M.matviewid)
    WHERE C.relkind = 'm'
        AND (C.relowner = (SELECT oid from pg_catalog.pg_authid where rolname = current_user)
        OR (SELECT rolsystemadmin or rolcreaterole or rolsuper from pg_catalog.pg_authid where rolname = current_user));
