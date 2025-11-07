SET search_path TO information_schema;

CREATE OR REPLACE FUNCTION pg_catalog.get_param_values(text)
RETURNS TEXT AS $$
DECLARE
    sql_mode_value TEXT;
BEGIN	
	SELECT s.setting INTO sql_mode_value
    FROM (SELECT 1) AS dummy
    LEFT JOIN pg_settings s ON s.name = $1;
    RETURN sql_mode_value;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_catalog.get_table_option(
   reloptions_info  text[],
   option_key text
) 
RETURNS TEXT AS $$
SELECT opt.option_value from pg_catalog.pg_options_to_table(reloptions_info) AS opt where opt.option_name = option_key;
$$ LANGUAGE sql STABLE; 


CREATE OR REPLACE FUNCTION pg_catalog.pg_extract_collate_name(oid) RETURNS text
    LANGUAGE sql
    IMMUTABLE
    NOT FENCED
    RETURNS NULL ON NULL INPUT
    AS
$$select collname::text from pg_collation where oid = $1 $$;

CREATE OR REPLACE FUNCTION pg_catalog.pg_get_expr(text, oid) RETURNS text LANGUAGE INTERNAL IMMUTABLE STRICT as 'pg_get_expr';

DROP FUNCTION IF EXISTS pg_catalog.get_auto_increment_nextval(oid, bool);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8554;
CREATE FUNCTION pg_catalog.get_auto_increment_nextval(oid, bool) RETURNS bool LANGUAGE INTERNAL IMMUTABLE STRICT AS 'get_auto_increment_nextval';
COMMENT ON FUNCTION pg_catalog.get_auto_increment_nextval(oid, bool) is 'get_auto_increment_nextval';

DROP FUNCTION IF EXISTS pg_catalog.pg_avg_row_length(oid, oid);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8555;
CREATE FUNCTION pg_catalog.pg_avg_row_length(oid, oid) RETURNS int LANGUAGE INTERNAL IMMUTABLE STRICT AS 'pg_avg_row_length';
COMMENT ON FUNCTION pg_catalog.pg_avg_row_length(oid, oid) is 'pg_avg_row_length';


DROP FUNCTION IF EXISTS pg_catalog.pg_get_index_type(oid, int2);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8556;
CREATE FUNCTION pg_catalog.pg_get_index_type(oid, int2) RETURNS cstring LANGUAGE INTERNAL IMMUTABLE STRICT AS 'pg_get_index_type';
COMMENT ON FUNCTION pg_catalog.pg_get_index_type(oid, int2) is 'pg_get_index_type';


DROP FUNCTION IF EXISTS pg_catalog.attnum_used_by_indexprs(text, int2);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8557;
CREATE FUNCTION pg_catalog.attnum_used_by_indexprs(text, int2) RETURNS bool LANGUAGE INTERNAL IMMUTABLE STRICT AS 'attnum_used_by_indexprs';
COMMENT ON FUNCTION pg_catalog.attnum_used_by_indexprs(text, int2) is 'attnum_used_by_indexprs';

DROP FUNCTION IF EXISTS pg_catalog.pg_get_partition_expression(oid, int, bool);
SET LOCAL inplace_upgrade_next_system_object_oids = IUO_PROC, 8558;
CREATE FUNCTION pg_catalog.pg_get_partition_expression(oid, int, bool) RETURNS text LANGUAGE INTERNAL IMMUTABLE STRICT AS 'pg_get_partition_expression';
COMMENT ON FUNCTION pg_catalog.pg_get_partition_expression(oid, int, bool) is 'pg_get_partition_expression';

CREATE OR REPLACE FUNCTION pg_catalog.partstrategy_to_full_str(input "char") 
RETURNS TEXT AS $$
select CASE WHEN input = 'r' THEN 'RANGE'
    WHEN input = 'i' THEN 'INTERVAL'
    WHEN input = 'v' THEN 'VALUE'
	WHEN input = 'l' THEN 'LIST'
	WHEN input = 'h' THEN 'HASH'
	ELSE NULL END
$$ LANGUAGE sql STABLE; 

CREATE OR REPLACE VIEW character_sets AS
    SELECT CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(pg_catalog.getdatabaseencoding() AS sql_identifier) AS character_set_name,
           CAST(CASE WHEN pg_catalog.getdatabaseencoding() = 'UTF8' THEN 'UCS' ELSE pg_catalog.getdatabaseencoding() END AS sql_identifier) AS character_repertoire,
           CAST(pg_catalog.getdatabaseencoding() AS sql_identifier) AS form_of_use,
           CAST(pg_catalog.current_database() AS sql_identifier) AS default_collate_catalog,
           CAST(nc.nspname AS sql_identifier) AS default_collate_schema,
           CAST(c.collname AS sql_identifier) AS default_collate_name,
           CAST(CASE 
               WHEN lower(character_set_name) IN ('utf16', 'utf16le', 'utf32', 'gb18030', 'utf8mb4') THEN 4
               WHEN lower(character_set_name) IN ('ujis', 'utf8mb3', 'eucjpms') THEN 3
               WHEN lower(character_set_name) IN ('big5', 'sjis', 'euckr', 'gb2312', 'gbk', 'ucs2', 'cp932') THEN 2
               WHEN lower(character_set_name) IN ('LATIN1', 'ASCII') THEN 1
               ELSE 1 END as int) AS maxlen,
           CAST(null AS varchar(2048)) AS description
    FROM pg_database d
         LEFT JOIN (pg_collation c JOIN pg_namespace nc ON (c.collnamespace = nc.oid))
             ON (datcollate = collcollate AND datctype = collctype)
    WHERE d.datname = pg_catalog.current_database()
    ORDER BY pg_catalog.char_length(c.collname) DESC, c.collname ASC -- prefer full/canonical name
    LIMIT 1;


CREATE OR REPLACE VIEW check_constraints AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(rs.nspname AS sql_identifier) AS constraint_schema,
           CAST(con.conname AS sql_identifier) AS constraint_name,
           CAST(substring(pg_catalog.pg_get_constraintdef(con.oid) from 7) AS character_data)
             AS check_clause,
           CAST(c.relname AS sql_identifier) AS table_name
    FROM pg_constraint con
           LEFT OUTER JOIN pg_namespace rs ON (rs.oid = con.connamespace)
           LEFT OUTER JOIN pg_class c ON (c.oid = con.conrelid)
           LEFT OUTER JOIN pg_type t ON (t.oid = con.contypid)
    WHERE pg_catalog.pg_has_role(coalesce(c.relowner, t.typowner), 'USAGE')
      AND con.contype = 'c'

    UNION
    -- not-null constraints

    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(n.nspname AS sql_identifier) AS constraint_schema,
           CAST(CAST(n.oid AS text) || '_' || CAST(r.oid AS text) || '_' || CAST(a.attnum AS text) || '_not_null' AS sql_identifier) AS constraint_name, -- XXX
           CAST(a.attname || ' IS NOT NULL' AS character_data)
             AS check_clause,
           CAST(r.relname AS sql_identifier) AS table_name
    FROM pg_namespace n, pg_class r, pg_attribute a
    WHERE n.oid = r.relnamespace
      AND r.oid = a.attrelid
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attnotnull
      AND r.relkind = 'r'
      AND pg_catalog.pg_has_role(r.relowner, 'USAGE');


CREATE OR REPLACE VIEW collations AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS collation_catalog,
           CAST(nc.nspname AS sql_identifier) AS collation_schema,
           CAST(c.collname AS sql_identifier) AS collation_name,
           CAST('NO PAD' AS character_data) AS pad_attribute,
           CAST(pg_catalog.pg_encoding_to_char(collencoding) AS varchar(64)) AS character_set_name,
           CAST(c.oid AS bigint) AS id,
           CAST(CASE WHEN c.collisdef THEN 'YES' ELSE NULL END AS varchar(3)) AS is_default,
           CAST('YES' AS varchar(3)) AS is_compiled,
           NULL::INTEGER AS sortlen
    FROM pg_collation c, pg_namespace nc
    WHERE c.collnamespace = nc.oid
          AND collencoding IN (-1, (SELECT encoding FROM pg_database WHERE datname = pg_catalog.current_database()));



CREATE OR REPLACE VIEW columns AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nc.nspname AS sql_identifier) AS table_schema,
           CAST(c.relname AS sql_identifier) AS table_name,
           CAST(a.attname AS sql_identifier) AS column_name,
           CAST(a.attnum AS cardinal_number) AS ordinal_position,
           CAST(CASE WHEN ad.adgencol <> 's' THEN pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) END AS character_data) AS column_default,
           CAST(CASE WHEN a.attnotnull OR (t.typtype = 'd' AND t.typnotnull) THEN 'NO' ELSE 'YES' END
             AS yes_or_no)
             AS is_nullable,

           CAST(
             CASE WHEN t.typtype = 'd' THEN
               CASE WHEN bt.typelem <> 0 AND bt.typlen = -1 THEN 'ARRAY'
                    WHEN nbt.nspname = 'pg_catalog' THEN pg_catalog.format_type(t.typbasetype, null)
                    ELSE 'USER-DEFINED' END
             ELSE
               CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ARRAY'
                    WHEN nt.nspname = 'pg_catalog' THEN pg_catalog.format_type(a.atttypid, null)
                    ELSE 'USER-DEFINED' END
             END
             AS character_data)
             AS data_type,

           CAST(
             _pg_char_max_length(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS character_maximum_length,

           CAST(
             _pg_char_octet_length(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS character_octet_length,

           CAST(
             _pg_numeric_precision(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS numeric_precision,

           CAST(
             _pg_numeric_precision_radix(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS numeric_precision_radix,

           CAST(
             _pg_numeric_scale(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS numeric_scale,

           CAST(
             _pg_datetime_precision(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS cardinal_number)
             AS datetime_precision,

           CAST(
             _pg_interval_type(_pg_truetypid(a, t), _pg_truetypmod(a, t))
             AS character_data)
             AS interval_type,
           CAST(null AS cardinal_number) AS interval_precision,

           CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(null AS sql_identifier) AS character_set_name,

           CAST(CASE WHEN nco.nspname IS NOT NULL THEN pg_catalog.current_database() END AS sql_identifier) AS collation_catalog,
           CAST(nco.nspname AS sql_identifier) AS collation_schema,
           CAST(co.collname AS sql_identifier) AS collation_name,

           CAST(CASE WHEN t.typtype = 'd' THEN pg_catalog.current_database() ELSE null END
             AS sql_identifier) AS domain_catalog,
           CAST(CASE WHEN t.typtype = 'd' THEN nt.nspname ELSE null END
             AS sql_identifier) AS domain_schema,
           CAST(CASE WHEN t.typtype = 'd' THEN t.typname ELSE null END
             AS sql_identifier) AS domain_name,

           CAST(pg_catalog.current_database() AS sql_identifier) AS udt_catalog,
           CAST(coalesce(nbt.nspname, nt.nspname) AS sql_identifier) AS udt_schema,
           CAST(coalesce(bt.typname, t.typname) AS sql_identifier) AS udt_name,

           CAST(null AS sql_identifier) AS scope_catalog,
           CAST(null AS sql_identifier) AS scope_schema,
           CAST(null AS sql_identifier) AS scope_name,

           CAST(null AS cardinal_number) AS maximum_cardinality,
           CAST(a.attnum AS sql_identifier) AS dtd_identifier,
           CAST('NO' AS yes_or_no) AS is_self_referencing,

           CAST('NO' AS yes_or_no) AS is_identity,
           CAST(null AS character_data) AS identity_generation,
           CAST(null AS character_data) AS identity_start,
           CAST(null AS character_data) AS identity_increment,
           CAST(null AS character_data) AS identity_maximum,
           CAST(null AS character_data) AS identity_minimum,
           CAST(null AS yes_or_no) AS identity_cycle,

           CAST(CASE WHEN ad.adgencol = 's' THEN 'ALWAYS' ELSE 'NEVER' END AS character_data) AS is_generated,
           CAST(CASE WHEN ad.adgencol = 's' THEN pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) END AS character_data) AS generation_expression,

           CAST(CASE WHEN c.relkind = 'r'
                          OR (c.relkind in ('v', 'f') AND pg_column_is_updatable(c.oid, a.attnum, false))
                THEN 'YES' ELSE 'NO' END AS yes_or_no) AS is_updatable,
           CAST(
             CASE WHEN t.typtype = 'd' THEN
               CASE WHEN bt.typelem <> 0 AND bt.typlen = -1 THEN 'ARRAY'
                    WHEN nbt.nspname = 'pg_catalog' THEN pg_catalog.format_type(t.typbasetype, null)
                    ELSE 'USER-DEFINED' END
             ELSE
               CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ARRAY'
                    WHEN nt.nspname = 'pg_catalog' THEN pg_catalog.format_type(a.atttypid, null)
                    ELSE 'USER-DEFINED' END
             END
             AS character_data)
             AS COLUMN_TYPE,
            CAST(d.description AS information_schema.character_data) AS COLUMN_COMMENT,
            CAST(
               CASE WHEN ad.adsrc = 'AUTO_INCREMENT' THEN 'AUTO_INCREMENT' 
               ELSE
                  CASE WHEN ad.adsrc_on_update is not null THEN CONCAT('DEFAULT_GENERATED on update ', ad.adsrc_on_update)
                  ELSE null
                  END
               END 
               AS character_data)
            AS EXTRA,
            CAST(array_to_string(ARRAY[
                CASE WHEN has_column_privilege(c.oid, a.attnum, 'SELECT') THEN 'select' END,
                CASE WHEN has_column_privilege(c.oid, a.attnum, 'INSERT') THEN 'insert' END,
                CASE WHEN has_column_privilege(c.oid, a.attnum, 'UPDATE') THEN 'update' END,
                CASE WHEN has_column_privilege(c.oid, a.attnum, 'REFERENCES') THEN 'references' END
                ], ',') AS varchar(154)) AS privileges,
            CAST(pg_get_index_type(c.oid, a.attnum) AS varchar(3)) AS column_key,
            CAST(null AS int) AS srs_id

    FROM (pg_attribute a LEFT JOIN pg_attrdef ad ON attrelid = adrelid AND attnum = adnum)
         JOIN (pg_class c JOIN pg_namespace nc ON (c.relnamespace = nc.oid)) ON a.attrelid = c.oid
         JOIN (pg_type t JOIN pg_namespace nt ON (t.typnamespace = nt.oid)) ON a.atttypid = t.oid
         LEFT JOIN (pg_type bt JOIN pg_namespace nbt ON (bt.typnamespace = nbt.oid))
           ON (t.typtype = 'd' AND t.typbasetype = bt.oid)
         LEFT JOIN (pg_collation co JOIN pg_namespace nco ON (co.collnamespace = nco.oid))
           ON a.attcollation = co.oid AND (nco.nspname, co.collname) <> ('pg_catalog', 'default')
         LEFT JOIN pg_description d on d.objoid = a.attrelid  and d.objsubid = a.attnum

    WHERE (NOT pg_catalog.pg_is_other_temp_schema(nc.oid))

          AND a.attnum > 0 AND NOT a.attisdropped AND c.relkind in ('r', 'm', 'v', 'f')

          AND (c.relname not like 'mlog\_%' AND c.relname not like 'matviewmap\_%')

          AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
               OR pg_catalog.has_column_privilege(c.oid, a.attnum,
                                       'SELECT, INSERT, UPDATE, REFERENCES'));


CREATE OR REPLACE VIEW key_column_usage AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(nc_nspname AS sql_identifier) AS constraint_schema,
           CAST(conname AS sql_identifier) AS constraint_name,
           CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nr_nspname AS sql_identifier) AS table_schema,
           CAST(ss.relname AS sql_identifier) AS table_name,
           CAST(a.attname AS sql_identifier) AS column_name,
           CAST((ss.x).n AS cardinal_number) AS ordinal_position,
           CAST(CASE WHEN contype = 'f' THEN
                       _pg_index_position(ss.conindid, ss.confkey[(ss.x).n])
                     ELSE NULL
                END AS cardinal_number)
             AS position_in_unique_constraint,
			 
           CAST(CASE WHEN ss.contype = 'f' THEN ref_ns.nspname ELSE NULL END AS varchar(64))
            AS referenced_table_schema,
           CAST(CASE WHEN ss.contype = 'f' THEN ref_rel.relname ELSE NULL END AS varchar(64))
            AS referenced_table_name,
           CAST(CASE WHEN ss.contype = 'f' THEN ref_att.attname ELSE NULL END AS varchar(64))
            AS referenced_column_name
			 
    FROM pg_attribute a,
         (SELECT r.oid AS roid, r.relname, r.relowner,
                 nc.nspname AS nc_nspname, nr.nspname AS nr_nspname,
                 c.oid AS coid, c.conname, c.contype, c.conindid,
                 c.confkey, c.confrelid,
                 _pg_expandarray(c.conkey) AS x
          FROM pg_namespace nr, pg_class r, pg_namespace nc,
               pg_constraint c
          WHERE nr.oid = r.relnamespace
                AND r.oid = c.conrelid
                AND nc.oid = c.connamespace
                AND c.contype IN ('p', 'u', 'f')
                AND r.relkind = 'r'
                AND (NOT pg_catalog.pg_is_other_temp_schema(nr.oid)) ) AS ss
         LEFT JOIN pg_class ref_rel 
            ON ss.contype = 'f' AND ss.confrelid = ref_rel.oid
         LEFT JOIN pg_namespace ref_ns 
            ON ss.contype = 'f' AND ref_rel.relnamespace = ref_ns.oid
         LEFT JOIN pg_attribute ref_att 
            ON ss.contype = 'f' 
            AND ref_rel.oid = ref_att.attrelid 
            AND ref_att.attnum = ss.confkey[(ss.x).n] 		
    WHERE ss.roid = a.attrelid
          AND a.attnum = (ss.x).x
          AND NOT a.attisdropped
          AND (pg_catalog.pg_has_role(ss.relowner, 'USAGE')
               OR pg_catalog.has_column_privilege(roid, a.attnum,
                                       'SELECT, INSERT, UPDATE, REFERENCES'));


CREATE OR REPLACE VIEW parameters AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS specific_catalog,
           CAST(n_nspname AS sql_identifier) AS specific_schema,
           CAST(proname || '_' || CAST(p_oid AS text) AS sql_identifier) AS specific_name,
           CAST((ss.x).n AS cardinal_number) AS ordinal_position,
           CAST(
             CASE WHEN proargmodes IS NULL THEN 'IN'
                WHEN proargmodes[(ss.x).n] = 'i' THEN 'IN'
                WHEN proargmodes[(ss.x).n] = 'o' THEN 'OUT'
                WHEN proargmodes[(ss.x).n] = 'b' THEN 'INOUT'
                WHEN proargmodes[(ss.x).n] = 'v' THEN 'IN'
                WHEN proargmodes[(ss.x).n] = 't' THEN 'OUT'
             END AS character_data) AS parameter_mode,
           CAST('NO' AS yes_or_no) AS is_result,
           CAST('NO' AS yes_or_no) AS as_locator,
           CAST(NULLIF(proargnames[(ss.x).n], '') AS sql_identifier) AS parameter_name,
           CAST(
             CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ARRAY'
                  WHEN nt.nspname = 'pg_catalog' THEN pg_catalog.format_type(t.oid, null)
                  ELSE 'USER-DEFINED' END AS character_data)
             AS data_type,
           CAST(null AS cardinal_number) AS character_maximum_length,
           CAST(null AS cardinal_number) AS character_octet_length,
           CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(null AS sql_identifier) AS character_set_name,
           CAST(null AS sql_identifier) AS collation_catalog,
           CAST(null AS sql_identifier) AS collation_schema,
           CAST(null AS sql_identifier) AS collation_name,
           CAST(null AS cardinal_number) AS numeric_precision,
           CAST(null AS cardinal_number) AS numeric_precision_radix,
           CAST(null AS cardinal_number) AS numeric_scale,
           CAST(null AS cardinal_number) AS datetime_precision,
           CAST(null AS character_data) AS interval_type,
           CAST(null AS cardinal_number) AS interval_precision,
           CAST(pg_catalog.current_database() AS sql_identifier) AS udt_catalog,
           CAST(nt.nspname AS sql_identifier) AS udt_schema,
           CAST(t.typname AS sql_identifier) AS udt_name,
           CAST(null AS sql_identifier) AS scope_catalog,
           CAST(null AS sql_identifier) AS scope_schema,
           CAST(null AS sql_identifier) AS scope_name,
           CAST(null AS cardinal_number) AS maximum_cardinality,
           CAST((ss.x).n AS sql_identifier) AS dtd_identifier,
           CAST(CASE WHEN ss.p_prokind = 'f' THEN 'FUNCTION' ELSE 'PROCEDURE' END AS varchar(64)) AS routine_type

    FROM pg_type t, pg_namespace nt,
         (SELECT n.nspname AS n_nspname, p.proname, p.oid AS p_oid,
                 p.proargnames, p.proargmodes,
                 _pg_expandarray(coalesce(p.proallargtypes, p.proargtypes::oid[])) AS x,
                 p.prokind as p_prokind
          FROM pg_namespace n, pg_proc p
          WHERE n.oid = p.pronamespace
                AND (pg_catalog.pg_has_role(p.proowner, 'USAGE') OR
                     pg_catalog.has_function_privilege(p.oid, 'EXECUTE'))) AS ss
    WHERE t.oid = (ss.x).x AND t.typnamespace = nt.oid;

CREATE OR REPLACE VIEW referential_constraints AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(ncon.nspname AS sql_identifier) AS constraint_schema,
           CAST(con.conname AS sql_identifier) AS constraint_name,
           CAST(
             CASE WHEN npkc.nspname IS NULL THEN NULL
                  ELSE pg_catalog.current_database() END
             AS sql_identifier) AS unique_constraint_catalog,
           CAST(npkc.nspname AS sql_identifier) AS unique_constraint_schema,
           CAST(pkc.conname AS sql_identifier) AS unique_constraint_name,

           CAST(
             CASE con.confmatchtype WHEN 'f' THEN 'FULL'
                                    WHEN 'p' THEN 'PARTIAL'
                                    WHEN 'u' THEN 'NONE' END
             AS character_data) AS match_option,

           CAST(
             CASE con.confupdtype WHEN 'c' THEN 'CASCADE'
                                  WHEN 'n' THEN 'SET NULL'
                                  WHEN 'd' THEN 'SET DEFAULT'
                                  WHEN 'r' THEN 'RESTRICT'
                                  WHEN 'a' THEN 'NO ACTION' END
             AS character_data) AS update_rule,

           CAST(
             CASE con.confdeltype WHEN 'c' THEN 'CASCADE'
                                  WHEN 'n' THEN 'SET NULL'
                                  WHEN 'd' THEN 'SET DEFAULT'
                                  WHEN 'r' THEN 'RESTRICT'
                                  WHEN 'a' THEN 'NO ACTION' END
             AS character_data) AS delete_rule,
           CAST(c.relname AS varchar(64)) AS table_name,
           CAST(c2.relname AS varchar(64)) AS referenced_table_name

    FROM (pg_namespace ncon
          INNER JOIN pg_constraint con ON ncon.oid = con.connamespace
          INNER JOIN pg_class c ON con.conrelid = c.oid AND con.contype = 'f')
         LEFT JOIN pg_depend d1  -- find constraint's dependency on an index
          ON d1.objid = con.oid AND d1.classid = 'pg_constraint'::regclass
             AND d1.refclassid = 'pg_class'::regclass AND d1.refobjsubid = 0
         LEFT JOIN pg_depend d2  -- find pkey/unique constraint for that index
          ON d2.refclassid = 'pg_constraint'::regclass
             AND d2.classid = 'pg_class'::regclass
             AND d2.objid = d1.refobjid AND d2.objsubid = 0
             AND d2.deptype = 'i'
         LEFT JOIN pg_constraint pkc ON pkc.oid = d2.refobjid
            AND pkc.contype IN ('p', 'u')
            AND pkc.conrelid = con.confrelid
         LEFT JOIN pg_namespace npkc ON pkc.connamespace = npkc.oid
         LEFT JOIN pg_class c2 on c2.oid = con.confrelid

    WHERE pg_catalog.pg_has_role(c.relowner, 'USAGE')
          -- SELECT privilege omitted, per SQL standard
          OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
          OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES') ;



CREATE OR REPLACE VIEW routines AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS specific_catalog,
           CAST(n.nspname AS sql_identifier) AS specific_schema,
           CAST(p.proname || '_' || CAST(p.oid AS text) AS sql_identifier) AS specific_name,
           CAST(pg_catalog.current_database() AS sql_identifier) AS routine_catalog,
           CAST(n.nspname AS sql_identifier) AS routine_schema,
           CAST(p.proname AS sql_identifier) AS routine_name,
           CAST('FUNCTION' AS character_data) AS routine_type,
           CAST(null AS sql_identifier) AS module_catalog,
           CAST(null AS sql_identifier) AS module_schema,
           CAST(null AS sql_identifier) AS module_name,
           CAST(null AS sql_identifier) AS udt_catalog,
           CAST(null AS sql_identifier) AS udt_schema,
           CAST(null AS sql_identifier) AS udt_name,

           CAST(
             CASE WHEN t.typelem <> 0 AND t.typlen = -1 THEN 'ARRAY'
                  WHEN nt.nspname = 'pg_catalog' THEN pg_catalog.format_type(t.oid, null)
                  ELSE 'USER-DEFINED' END AS character_data)
             AS data_type,
           CAST(null AS cardinal_number) AS character_maximum_length,
           CAST(null AS cardinal_number) AS character_octet_length,
           CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(null AS sql_identifier) AS character_set_name,
           CAST(null AS sql_identifier) AS collation_catalog,
           CAST(null AS sql_identifier) AS collation_schema,
           CAST(null AS sql_identifier) AS collation_name,
           CAST(null AS cardinal_number) AS numeric_precision,
           CAST(null AS cardinal_number) AS numeric_precision_radix,
           CAST(null AS cardinal_number) AS numeric_scale,
           CAST(null AS cardinal_number) AS datetime_precision,
           CAST(null AS character_data) AS interval_type,
           CAST(null AS cardinal_number) AS interval_precision,
           CAST(pg_catalog.current_database() AS sql_identifier) AS type_udt_catalog,
           CAST(nt.nspname AS sql_identifier) AS type_udt_schema,
           CAST(t.typname AS sql_identifier) AS type_udt_name,
           CAST(null AS sql_identifier) AS scope_catalog,
           CAST(null AS sql_identifier) AS scope_schema,
           CAST(null AS sql_identifier) AS scope_name,
           CAST(null AS cardinal_number) AS maximum_cardinality,
           CAST(0 AS sql_identifier) AS dtd_identifier,

           CAST(CASE WHEN l.lanname = 'sql' THEN 'SQL' ELSE 'EXTERNAL' END AS character_data)
             AS routine_body,
           CAST(
             CASE WHEN pg_catalog.pg_has_role(p.proowner, 'USAGE') THEN p.prosrc ELSE null END
             AS character_data) AS routine_definition,
           CAST(
             CASE WHEN l.lanname = 'c' THEN p.prosrc ELSE null END
             AS character_data) AS external_name,
           CAST(pg_catalog.upper(l.lanname) AS character_data) AS external_language,

           CAST('GENERAL' AS character_data) AS parameter_style,
           CAST(CASE WHEN p.provolatile = 'i' THEN 'YES' ELSE 'NO' END AS yes_or_no) AS is_deterministic,
           CAST('MODIFIES' AS character_data) AS sql_data_access,
           CAST(CASE WHEN p.proisstrict THEN 'YES' ELSE 'NO' END AS yes_or_no) AS is_null_call,
           CAST(null AS character_data) AS sql_path,
           CAST('YES' AS yes_or_no) AS schema_level_routine,
           CAST(0 AS cardinal_number) AS max_dynamic_result_sets,
           CAST(null AS yes_or_no) AS is_user_defined_cast,
           CAST(null AS yes_or_no) AS is_implicitly_invocable,
           CAST(CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS character_data) AS security_type,
           CAST(null AS sql_identifier) AS to_sql_specific_catalog,
           CAST(null AS sql_identifier) AS to_sql_specific_schema,
           CAST(null AS sql_identifier) AS to_sql_specific_name,
           CAST('NO' AS yes_or_no) AS as_locator,
           CAST(null AS time_stamp) AS created,
           CAST(null AS time_stamp) AS last_altered,
           CAST(null AS yes_or_no) AS new_savepoint_level,
           CAST('NO' AS yes_or_no) AS is_udt_dependent,

           CAST(null AS character_data) AS result_cast_from_data_type,
           CAST(null AS yes_or_no) AS result_cast_as_locator,
           CAST(null AS cardinal_number) AS result_cast_char_max_length,
           CAST(null AS cardinal_number) AS result_cast_char_octet_length,
           CAST(null AS sql_identifier) AS result_cast_char_set_catalog,
           CAST(null AS sql_identifier) AS result_cast_char_set_schema,
           CAST(null AS sql_identifier) AS result_cast_character_set_name,
           CAST(null AS sql_identifier) AS result_cast_collation_catalog,
           CAST(null AS sql_identifier) AS result_cast_collation_schema,
           CAST(null AS sql_identifier) AS result_cast_collation_name,
           CAST(null AS cardinal_number) AS result_cast_numeric_precision,
           CAST(null AS cardinal_number) AS result_cast_numeric_precision_radix,
           CAST(null AS cardinal_number) AS result_cast_numeric_scale,
           CAST(null AS cardinal_number) AS result_cast_datetime_precision,
           CAST(null AS character_data) AS result_cast_interval_type,
           CAST(null AS cardinal_number) AS result_cast_interval_precision,
           CAST(null AS sql_identifier) AS result_cast_type_udt_catalog,
           CAST(null AS sql_identifier) AS result_cast_type_udt_schema,
           CAST(null AS sql_identifier) AS result_cast_type_udt_name,
           CAST(null AS sql_identifier) AS result_cast_scope_catalog,
           CAST(null AS sql_identifier) AS result_cast_scope_schema,
           CAST(null AS sql_identifier) AS result_cast_scope_name,
           CAST(null AS cardinal_number) AS result_cast_maximum_cardinality,
           CAST(null AS sql_identifier) AS result_cast_dtd_identifier,
           CAST(d.description AS text) AS routine_comment,
           CAST(pg_catalog.get_param_values('dolphin.sql_mode'::text) AS text) AS sql_mode,
           CAST(u.usename AS varchar(288)) AS definer,
           CAST(pg_catalog.get_param_values('client_encoding'::text) AS varchar(64)) AS character_set_client,
           CAST(db.datcollate AS varchar(64)) AS collation_connection,
           CAST(db.datcollate AS varchar(64)) AS database_collation
          
          FROM pg_namespace n
          INNER JOIN pg_proc p ON n.oid = p.pronamespace  
          INNER JOIN pg_language l ON p.prolang = l.oid 
          INNER JOIN pg_type t ON p.prorettype = t.oid 
          INNER JOIN pg_namespace nt ON t.typnamespace = nt.oid
          INNER JOIN pg_description d ON d.objoid = p.oid 
          INNER JOIN pg_class c ON d.classoid = c.oid
          LEFT JOIN pg_user u ON p.proowner = u.usesysid
          LEFT JOIN pg_database db ON db.datname = current_database()
           WHERE 
             (pg_catalog.pg_has_role(p.proowner, 'USAGE')
              OR pg_catalog.has_function_privilege(p.oid, 'EXECUTE'));


CREATE OR REPLACE VIEW schemata AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS catalog_name,
           CAST(n.nspname AS sql_identifier) AS schema_name,
           CAST(u.rolname AS sql_identifier) AS schema_owner,
           CAST(null AS sql_identifier) AS default_character_set_catalog,
           CAST(null AS sql_identifier) AS default_character_set_schema,
           CAST(pg_encoding_to_char(d.encoding) AS sql_identifier) AS default_character_set_name,
           CAST(null AS character_data) AS sql_path,
           CAST(d.datcollate AS varchar(64)) AS default_collation_name,
           CAST('NO' AS varchar(3)) AS default_encryption
    FROM pg_namespace n, pg_authid u, pg_catalog.pg_database d
    WHERE n.nspowner = u.oid AND pg_catalog.pg_has_role(n.nspowner, 'USAGE') AND d.datname = current_database();


CREATE OR REPLACE VIEW table_constraints AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(nc.nspname AS sql_identifier) AS constraint_schema,
           CAST(c.conname AS sql_identifier) AS constraint_name,
           CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nr.nspname AS sql_identifier) AS table_schema,
           CAST(r.relname AS sql_identifier) AS table_name,
           CAST(
             CASE c.contype WHEN 'c' THEN 'CHECK'
                            WHEN 'f' THEN 'FOREIGN KEY'
                            WHEN 'p' THEN 'PRIMARY KEY'
                            WHEN 'u' THEN 'UNIQUE' END
             AS character_data) AS constraint_type,
           CAST(CASE WHEN c.condeferrable THEN 'YES' ELSE 'NO' END AS yes_or_no)
             AS is_deferrable,
           CAST(CASE WHEN c.condeferred THEN 'YES' ELSE 'NO' END AS yes_or_no)
             AS initially_deferred,
           CAST('YES' AS varchar(3)) AS enforced

    FROM pg_namespace nc,
         pg_namespace nr,
         pg_constraint c,
         pg_class r

    WHERE nc.oid = c.connamespace AND nr.oid = r.relnamespace
          AND c.conrelid = r.oid
          AND c.contype NOT IN ('t', 'x')  -- ignore nonstandard constraints
          AND r.relkind = 'r'
          AND (NOT pg_catalog.pg_is_other_temp_schema(nr.oid))
          AND (pg_catalog.pg_has_role(r.relowner, 'USAGE')
               -- SELECT privilege omitted, per SQL standard
               OR pg_catalog.has_table_privilege(r.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
               OR pg_catalog.has_any_column_privilege(r.oid, 'INSERT, UPDATE, REFERENCES') )

    UNION ALL

    -- not-null constraints

    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(nr.nspname AS sql_identifier) AS constraint_schema,
           CAST(CAST(nr.oid AS text) || '_' || CAST(r.oid AS text) || '_' || CAST(a.attnum AS text) || '_not_null' AS sql_identifier) AS constraint_name, -- XXX
           CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nr.nspname AS sql_identifier) AS table_schema,
           CAST(r.relname AS sql_identifier) AS table_name,
           CAST('CHECK' AS character_data) AS constraint_type,
           CAST('NO' AS yes_or_no) AS is_deferrable,
           CAST('NO' AS yes_or_no) AS initially_deferred,
           CAST('YES' AS yes_or_no) AS enforced

    FROM pg_namespace nr,
         pg_class r,
         pg_attribute a

    WHERE nr.oid = r.relnamespace
          AND r.oid = a.attrelid
          AND a.attnotnull
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND r.relkind = 'r'
          AND (NOT pg_catalog.pg_is_other_temp_schema(nr.oid))
          AND (pg_catalog.pg_has_role(r.relowner, 'USAGE')
               -- SELECT privilege omitted, per SQL standard
               OR pg_catalog.has_table_privilege(r.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
               OR pg_catalog.has_any_column_privilege(r.oid, 'INSERT, UPDATE, REFERENCES') );


CREATE OR REPLACE VIEW tables AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nc.nspname AS sql_identifier) AS table_schema,
           CAST(c.relname AS sql_identifier) AS table_name,

           CAST(
             CASE WHEN nc.oid = pg_catalog.pg_my_temp_schema() THEN 'LOCAL TEMPORARY'
                  WHEN c.relkind = 'r' THEN 'BASE TABLE'
                  WHEN c.relkind = 'm' THEN 'MATERIALIZED VIEW'
                  WHEN c.relkind = 'v' THEN 'VIEW'
                  WHEN c.relkind = 'f' THEN 'FOREIGN TABLE'
                  ELSE null END
             AS character_data) AS table_type,

           CAST(null AS sql_identifier) AS self_referencing_column_name,
           CAST(null AS character_data) AS reference_generation,

           CAST(CASE WHEN t.typname IS NOT NULL THEN pg_catalog.current_database() ELSE null END AS sql_identifier) AS user_defined_type_catalog,
           CAST(nt.nspname AS sql_identifier) AS user_defined_type_schema,
           CAST(t.typname AS sql_identifier) AS user_defined_type_name,

           CAST(CASE WHEN c.relkind = 'r' OR
                          (c.relkind in ('v', 'f') AND
                           -- 1 << CMD_INSERT
                           pg_relation_is_updatable(c.oid, false) & 8 = 8)
                THEN 'YES' ELSE 'NO' END AS yes_or_no) AS is_insertable_into,

           CAST(CASE WHEN t.typname IS NOT NULL THEN 'YES' ELSE 'NO' END AS yes_or_no) AS is_typed,
           CAST(null AS character_data) AS commit_action,
           CAST(d.description AS information_schema.character_data) AS TABLE_COMMENT,
           CAST(pg_catalog.pg_extract_collate_name(pg_catalog.get_table_option(c.reloptions, 'collate'::text)::oid) AS varchar(64)) AS table_collation,
           CAST(null AS varchar(64)) AS engine,
           CAST(10 AS INTEGER) AS version,
           CAST(CASE WHEN c.relkind = 'r' THEN 
                   CASE WHEN pg_catalog.get_table_option(c.reloptions, 'compression'::text) is not null and pg_catalog.get_table_option(c.reloptions, 'compression'::text) != 'no'
                        THEN 'Compressed'
                   ELSE 'Dynamic' END
               ELSE NULL END AS varchar(64)) AS row_format,
           CAST(CASE WHEN c.relkind = 'r' THEN c.reltuples::BIGINT ELSE NULL END AS bigint) AS table_rows,
           CAST(CASE WHEN c.relkind = 'r' THEN pg_avg_row_length(c.oid, 0) 
              ELSE NULL 
              END AS bigint) AS avg_row_length,
           CAST(CASE WHEN c.relkind = 'r' THEN pg_relation_size(c.oid) ELSE NULL END AS bigint) AS data_length,
           CAST(NULL AS bigint) AS max_data_length,
           CAST(CASE WHEN c.relkind = 'r' THEN pg_indexes_size(c.oid) ELSE NULL END AS bigint) AS index_length,
           CAST(NULL AS bigint) AS data_free,
           CAST(get_auto_increment_nextval(c.oid, true) AS int16) AS auto_increment,
           CAST(po.ctime AS timestamptz) AS create_time,
       	   CAST(po.mtime AS timestamp) AS update_time,
           CAST(null AS timestamp) AS check_time,
           CAST(null AS bigint) AS checksum,
           CAST(c.reloptions AS varchar(256)) AS create_options

    FROM pg_namespace nc JOIN pg_class c ON (nc.oid = c.relnamespace)
           LEFT JOIN (pg_type t JOIN pg_namespace nt ON (t.typnamespace = nt.oid)) ON (c.reloftype = t.oid)
           LEFT JOIN pg_description d on d.objoid = c.oid and objsubid = 0
      	   LEFT JOIN pg_object po on c.oid = po.object_oid and c.relkind = po.object_type
           LEFT JOIN pg_tablespace ts ON c.reltablespace = ts.oid

    WHERE c.relkind IN ('r', 'm', 'v', 'f')
          AND (c.relname not like 'mlog\_%' AND c.relname not like 'matviewmap\_%')
          AND (NOT pg_catalog.pg_is_other_temp_schema(nc.oid))
          AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
               OR pg_catalog.has_table_privilege(c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
               OR pg_catalog.has_any_column_privilege(c.oid, 'SELECT, INSERT, UPDATE, REFERENCES') );


CREATE OR REPLACE VIEW KEYWORDS AS
    select t.word::varchar(128) as word,
	CAST(
        CASE WHEN t.catcode = 'U' THEN 0
             WHEN t.catcode = 'C' THEN 0
             WHEN t.catcode = 'T' THEN 1
             WHEN t.catcode = 'R' THEN 1
             ELSE 0 END
        AS int) AS reserved
	from pg_get_keywords() t;

GRANT SELECT ON KEYWORDS TO PUBLIC; 


CREATE OR REPLACE VIEW statistics AS
SELECT
    CAST(CURRENT_CATALOG AS varchar(64)) AS table_catalog,
    CAST(n.nspname AS varchar(64)) AS table_schema,
    CAST(t.relname AS varchar(64)) AS table_name,	
    CAST(CASE WHEN idx.indisunique THEN 0 ELSE 1 END as int) AS non_unique,
    CAST(n.nspname AS varchar(64)) AS index_schema,
    CAST(i.relname AS varchar(64)) AS index_name,
    CAST(pos AS int) AS seq_in_index,
    CAST(a.attname AS varchar(64)) AS column_name,
    CAST(CASE 
        WHEN idx.indoption[pos-1] & 1 = 0 THEN 'A' 
        ELSE 'D'           
        END AS varchar(1)) AS collation,	
    CAST(CASE 
        WHEN idx.indisunique THEN t.reltuples
        ELSE ceil(i.reltuples * (1 - (1.0 / idx.indnatts)))
        END AS bigint) AS cardinality,
    CAST(NULL as bigint) AS sub_part, 
    CAST(NULL as varchar(64)) AS packed,
    CAST(CASE WHEN a.attnotnull THEN '' ELSE 'YES' END AS varchar(3)) AS nullable,
    CAST(CASE am.amname 
        WHEN 'ubtree' THEN 'UBTREE'
        WHEN 'btree' THEN 'BTREE'
        WHEN 'hash' THEN 'HASH'
        WHEN 'gist' THEN 'GIST'
        WHEN 'gin' THEN 'GIN'
        ELSE am.amname::TEXT 
        END AS varchar(11)) AS index_type,
    CAST('' AS varchar(8)) AS comment,
    CAST(d.description AS varchar(2048)) AS index_comment,
    CAST(CASE 
        WHEN idx.indisvalid = 't'::boolean THEN 'YES' 
        ELSE 'NO'           
        END AS varchar(3)) AS is_visible,
    CAST(pg_get_expr(idx.indexprs, t.oid) AS TEXT) AS expression
FROM
    pg_class t
    JOIN pg_namespace n ON t.relnamespace = n.oid
    JOIN pg_index idx ON idx.indrelid = t.oid
    JOIN pg_class i ON i.oid = idx.indexrelid
    JOIN pg_am am ON i.relam = am.oid
    JOIN generate_series(1, array_length(idx.indkey, 1)) AS pos ON true
    JOIN pg_attribute a ON a.attrelid = t.oid AND (a.attnum = idx.indkey[pos - 1] or attnum_used_by_indexprs(idx.indexprs, a.attnum))
    left JOIN pg_description d on d.objoid = idx.indexrelid and d.objsubid = 0	
WHERE
    t.relkind = 'r'
    AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast');

GRANT SELECT ON statistics TO PUBLIC; 


CREATE OR REPLACE VIEW partitions AS
SELECT CAST(pg_catalog.current_database() AS varchar(64)) AS table_catalog,
       CAST(nc.nspname AS varchar(64)) AS table_schema,
       CAST(c.relname AS varchar(64)) AS table_name,
       CAST(p.relname AS varchar(64)) AS partition_name,
       CAST(NULL AS varchar(64)) AS subpartition_name,
       CAST((pg_catalog.dense_rank() OVER(PARTITION BY TABLE_NAME ORDER BY PARTITION_NAME)) AS int) AS partition_ordinal_position,
       CAST(NULL AS int) AS subpartition_ordinal_position,
       CAST(pg_catalog.partstrategy_to_full_str(p.partstrategy) AS varchar(13)) AS partition_method,
       CAST(NULL AS varchar(13)) AS subpartition_method,
       CAST(pg_catalog.pg_get_partition_expression(p.parentid, -1, false) AS varchar(2048) )AS partition_expression,
       CAST(NULL AS varchar(2048)) AS subpartition_expression,
       CAST(CASE
            WHEN p.partstrategy = 'r' OR p.partstrategy = 'i' THEN pg_catalog.array_to_string(p.boundaries, ',' , 'MAXVALUE')
            WHEN p.partstrategy = 'l' THEN pg_catalog.array_to_string(p.boundaries, ',' , 'DEFAULT')
            ELSE pg_catalog.array_to_string(p.boundaries, ',' , NULL)
            END AS text) AS partition_description,
       CAST(p.reltuples AS bigint) AS table_rows,
       CAST(CASE WHEN c.relkind = 'r' THEN pg_avg_row_length(c.oid, p.oid) ELSE NULL END AS bigint) AS avg_row_length,
       CAST(CASE WHEN c.relkind = 'r' THEN pg_partition_size(c.oid, p.oid) ELSE NULL END AS bigint) AS data_length,
       CAST(NULL AS bigint) AS max_data_length,
       CAST(NULL AS bigint) AS index_length,
       CAST(NULL AS bigint) AS data_free,
       CAST(po.ctime AS timestamptz) AS create_time,
       CAST(po.mtime AS timestamp) AS update_time,
       CAST(NULL AS timestamp) AS check_time,
       CAST(NULL AS bigint) AS checksum,
       CAST(NULL AS text) AS partition_comment,
       CAST(NULL AS varchar(256)) AS nodegroup,
       CAST(CASE
            WHEN p.reltablespace = 0 THEN 'pg_default'::text
            ELSE (SELECT spc.spcname FROM pg_catalog.pg_tablespace spc WHERE p.reltablespace = spc.oid)
            END AS varchar(268)) AS tablespace_name
	
	FROM pg_catalog.pg_class c INNER JOIN pg_catalog.pg_partition p on p.parentid = c.oid
	INNER JOIN pg_catalog.pg_authid a on c.relowner = a.oid
	INNER JOIN pg_catalog.pg_namespace nc on c.relnamespace = nc.oid
        LEFT JOIN pg_object po on c.oid = po.object_oid and c.relkind = po.object_type
	where p.parttype = 'p' AND
    (
        pg_catalog.pg_has_role(c.relowner, 'usage')
        OR pg_catalog.has_table_privilege(c.oid, 'select, insert, update, delete, truncate, references, trigger')
        OR pg_catalog.has_any_column_privilege(c.oid, 'select, insert, update, references')
    ) AND subpartitionno is null
    UNION ALL
    SELECT CAST(pg_catalog.current_database() AS varchar(64)) AS table_catalog,
       CAST(nc.nspname AS varchar(64)) AS table_schema,
       CAST(c.relname AS varchar(64)) AS table_name,
       CAST(p.relname AS varchar(64)) AS partition_name,
       CAST(sp.relname AS varchar(64)) AS subpartition_name,
       CAST((pg_catalog.dense_rank() OVER(PARTITION BY TABLE_NAME ORDER BY PARTITION_NAME)) AS int) AS partition_ordinal_position,
       CAST((pg_catalog.dense_rank() OVER(PARTITION BY TABLE_NAME, PARTITION_NAME ORDER BY SUBPARTITION_NAME)) AS int) AS subpartition_ordinal_position,
       CAST(pg_catalog.partstrategy_to_full_str(p.partstrategy) AS varchar(13)) AS partition_method,
       CAST(pg_catalog.partstrategy_to_full_str(sp.partstrategy) as varchar(13)) AS subpartition_method,
       CAST(pg_catalog.pg_get_partition_expression(p.parentid, -1, false) AS varchar(2048)) AS partition_expression,
       CAST(pg_catalog.pg_get_partition_expression(sp.parentid, -1, true) AS varchar(2048)) AS subpartition_expression,
       CAST(CASE
            WHEN sp.partstrategy = 'r' OR sp.partstrategy = 'i' THEN pg_catalog.array_to_string(sp.boundaries, ',' , 'MAXVALUE')
            WHEN sp.partstrategy = 'l' THEN pg_catalog.array_to_string(sp.boundaries, ',' , 'DEFAULT')
            ELSE pg_catalog.array_to_string(sp.boundaries, ',' , NULL)
            END AS text) AS partition_description,
       CAST(sp.reltuples as bigint) AS table_rows,
       CAST(CASE WHEN c.relkind = 'r' THEN pg_avg_row_length(c.oid, p.oid) ELSE NULL END AS bigint) AS avg_row_length,
       CAST(CASE WHEN c.relkind = 'r' THEN pg_partition_size(c.oid, p.oid) ELSE NULL END AS bigint) AS data_length,
       CAST(NULL AS bigint) AS max_data_length,
       CAST(NULL AS bigint) AS index_length,
       CAST(NULL AS bigint) data_free,
       CAST(po.ctime AS timestamptz) AS create_time,
       CAST(po.mtime AS timestamp) AS update_time,
       CAST(NULL AS timestamp) AS check_time,
       CAST(NULL AS bigint) AS checksum,
       CAST(NULL AS text) AS partition_comment,
       CAST(NULL AS varchar(256)) AS nodegroup,
       CAST(CASE
            WHEN sp.reltablespace = 0 THEN 'pg_default'::text
            ELSE (SELECT spc.spcname FROM pg_tablespace spc WHERE sp.reltablespace = spc.oid)
            END AS varchar(268)) AS tablespace_name
	FROM pg_catalog.pg_class c INNER JOIN pg_catalog.pg_partition p on p.parentid = c.oid
	INNER JOIN pg_catalog.pg_partition sp on sp.parentid = p.oid
	INNER JOIN pg_catalog.pg_authid a on c.relowner = a.oid
	INNER JOIN pg_catalog.pg_namespace nc on c.relnamespace = nc.oid
   LEFT JOIN pg_object po on c.oid = po.object_oid and c.relkind = po.object_type
	where p.parttype = 'p' AND
    sp.parttype = 's' AND
    (
        pg_catalog.pg_has_role(c.relowner, 'usage')
        OR pg_catalog.has_table_privilege(c.oid, 'select, insert, update, delete, truncate, references, trigger')
        OR pg_catalog.has_any_column_privilege(c.oid, 'select, insert, update, references')
    );
	
GRANT SELECT ON partitions TO PUBLIC; 

CREATE OR REPLACE VIEW events AS
  SELECT
    CAST(pg_catalog.current_database() AS varchar(64)) AS event_catalog,
    CAST(job.nspname AS varchar(64)) AS event_schema,
    CAST(job_proc.job_name AS varchar(64)) AS event_name,
    CAST(job.log_user AS varchar(288)) AS definer,
    CAST('SYSTEM' AS varchar(64)) AS time_zone,
    CAST('SQL' AS varchar(3)) AS event_body,
    CAST(job_proc.what AS text) AS event_definition,
    CAST(CASE WHEN job.interval IS NULL THEN 'ONE TIME' ELSE 'RECURRING' END AS varchar(9)) AS event_type,
    CAST(CASE WHEN job.interval IS NULL THEN job.start_date ELSE NULL END AS timestamp) AS execute_at,
    CAST(job.interval AS varchar(256)) AS interval_value,
    CAST(NULL AS text) AS interval_field,
    CAST(pg_catalog.get_param_values('dolphin.sql_mode'::text) AS text) AS sql_mode,
    CAST(CASE WHEN job.interval IS NOT NULL THEN job.start_date ELSE NULL END AS timestamp) AS starts,
    CAST(job.end_date AS timestamp) AS ends,
    CAST(job.job_status AS varchar(21)) AS status, 
    CAST('PRESERVE' AS varchar(12)) AS on_completion,
    CAST(job.start_date AS timestamp) AS created,
    CAST(job.start_date AS timestamp) AS last_altered,
    CAST(job.last_start_date AS timestamp) AS last_executed,
    CAST(NULL AS varchar(2048)) AS event_comment,
    CAST(0 AS int) AS originator,
    CAST(pg_catalog.get_param_values('client_encoding'::text) AS varchar(64)) AS character_set_client,
    CAST(db.datcollate AS varchar(64)) AS collation_connection,
    CAST(db.datcollate AS varchar(64)) AS database_collation
    from pg_job job join pg_job_proc job_proc on job.job_id = job_proc.job_id
      join pg_authid au on job.log_user = au.rolname
   JOIN pg_database db ON db.datname = pg_catalog.current_database()
      where pg_catalog.pg_has_role(au.oid, 'USAGE') AND db.datname = pg_catalog.current_database();

GRANT SELECT ON events TO PUBLIC; 

RESET search_path;
