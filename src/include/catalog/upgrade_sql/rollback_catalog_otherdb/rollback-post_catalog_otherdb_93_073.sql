SET search_path TO information_schema;

DROP VIEW IF EXISTS character_sets CASCADE;
CREATE OR REPLACE VIEW character_sets AS
    SELECT CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(pg_catalog.getdatabaseencoding() AS sql_identifier) AS character_set_name,
           CAST(CASE WHEN pg_catalog.getdatabaseencoding() = 'UTF8' THEN 'UCS' ELSE pg_catalog.getdatabaseencoding() END AS sql_identifier) AS character_repertoire,
           CAST(pg_catalog.getdatabaseencoding() AS sql_identifier) AS form_of_use,
           CAST(pg_catalog.current_database() AS sql_identifier) AS default_collate_catalog,
           CAST(nc.nspname AS sql_identifier) AS default_collate_schema,
           CAST(c.collname AS sql_identifier) AS default_collate_name
    FROM pg_database d
         LEFT JOIN (pg_collation c JOIN pg_namespace nc ON (c.collnamespace = nc.oid))
             ON (datcollate = collcollate AND datctype = collctype)
    WHERE d.datname = pg_catalog.current_database()
    ORDER BY pg_catalog.char_length(c.collname) DESC, c.collname ASC -- prefer full/canonical name
    LIMIT 1;
GRANT SELECT ON character_sets TO PUBLIC;

DROP VIEW IF EXISTS check_constraints CASCADE;
CREATE OR REPLACE VIEW check_constraints AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(rs.nspname AS sql_identifier) AS constraint_schema,
           CAST(con.conname AS sql_identifier) AS constraint_name,
           CAST(substring(pg_catalog.pg_get_constraintdef(con.oid) from 7) AS character_data)
             AS check_clause
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
             AS check_clause
    FROM pg_namespace n, pg_class r, pg_attribute a
    WHERE n.oid = r.relnamespace
      AND r.oid = a.attrelid
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attnotnull
      AND r.relkind = 'r'
      AND pg_catalog.pg_has_role(r.relowner, 'USAGE');

GRANT SELECT ON check_constraints TO PUBLIC;


DROP VIEW IF EXISTS collations CASCADE;
CREATE OR REPLACE VIEW collations AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS collation_catalog,
           CAST(nc.nspname AS sql_identifier) AS collation_schema,
           CAST(c.collname AS sql_identifier) AS collation_name,
           CAST('NO PAD' AS character_data) AS pad_attribute
    FROM pg_collation c, pg_namespace nc
    WHERE c.collnamespace = nc.oid
          AND collencoding IN (-1, (SELECT encoding FROM pg_database WHERE datname = pg_catalog.current_database()));
GRANT SELECT ON collations TO PUBLIC;


DROP VIEW IF EXISTS columns CASCADE;
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
            AS EXTRA

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
GRANT SELECT ON columns TO PUBLIC;


DROP VIEW IF EXISTS key_column_usage CASCADE;
CREATE OR REPLACE VIEW key_column_usage AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS constraint_catalog,
           CAST(nc_nspname AS sql_identifier) AS constraint_schema,
           CAST(conname AS sql_identifier) AS constraint_name,
           CAST(pg_catalog.current_database() AS sql_identifier) AS table_catalog,
           CAST(nr_nspname AS sql_identifier) AS table_schema,
           CAST(relname AS sql_identifier) AS table_name,
           CAST(a.attname AS sql_identifier) AS column_name,
           CAST((ss.x).n AS cardinal_number) AS ordinal_position,
           CAST(CASE WHEN contype = 'f' THEN
                       _pg_index_position(ss.conindid, ss.confkey[(ss.x).n])
                     ELSE NULL
                END AS cardinal_number)
             AS position_in_unique_constraint
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
    WHERE ss.roid = a.attrelid
          AND a.attnum = (ss.x).x
          AND NOT a.attisdropped
          AND (pg_catalog.pg_has_role(relowner, 'USAGE')
               OR pg_catalog.has_column_privilege(roid, a.attnum,
                                       'SELECT, INSERT, UPDATE, REFERENCES'));

GRANT SELECT ON key_column_usage TO PUBLIC;

DROP VIEW IF EXISTS parameters CASCADE;
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
           CAST((ss.x).n AS sql_identifier) AS dtd_identifier

    FROM pg_type t, pg_namespace nt,
         (SELECT n.nspname AS n_nspname, p.proname, p.oid AS p_oid,
                 p.proargnames, p.proargmodes,
                 _pg_expandarray(coalesce(p.proallargtypes, p.proargtypes::oid[])) AS x
          FROM pg_namespace n, pg_proc p
          WHERE n.oid = p.pronamespace
                AND (pg_catalog.pg_has_role(p.proowner, 'USAGE') OR
                     pg_catalog.has_function_privilege(p.oid, 'EXECUTE'))) AS ss
    WHERE t.oid = (ss.x).x AND t.typnamespace = nt.oid;

GRANT SELECT ON parameters TO PUBLIC;


DROP VIEW IF EXISTS referential_constraints CASCADE;
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
             AS character_data) AS delete_rule

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

    WHERE pg_catalog.pg_has_role(c.relowner, 'USAGE')
          -- SELECT privilege omitted, per SQL standard
          OR pg_catalog.has_table_privilege(c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
          OR pg_catalog.has_any_column_privilege(c.oid, 'INSERT, UPDATE, REFERENCES') ;

GRANT SELECT ON referential_constraints TO PUBLIC;


DROP VIEW IF EXISTS routines CASCADE;
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
           CAST(null AS sql_identifier) AS result_cast_dtd_identifier

    FROM pg_namespace n, pg_proc p, pg_language l,
         pg_type t, pg_namespace nt

    WHERE n.oid = p.pronamespace AND p.prolang = l.oid
          AND p.prorettype = t.oid AND t.typnamespace = nt.oid
          AND (pg_catalog.pg_has_role(p.proowner, 'USAGE')
               OR pg_catalog.has_function_privilege(p.oid, 'EXECUTE'));

GRANT SELECT ON routines TO PUBLIC;


DROP VIEW IF EXISTS schemata CASCADE;
CREATE OR REPLACE VIEW schemata AS
    SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS catalog_name,
           CAST(n.nspname AS sql_identifier) AS schema_name,
           CAST(u.rolname AS sql_identifier) AS schema_owner,
           CAST(null AS sql_identifier) AS default_character_set_catalog,
           CAST(null AS sql_identifier) AS default_character_set_schema,
           CAST(null AS sql_identifier) AS default_character_set_name,
           CAST(null AS character_data) AS sql_path
    FROM pg_namespace n, pg_authid u
    WHERE n.nspowner = u.oid AND pg_catalog.pg_has_role(n.nspowner, 'USAGE');

GRANT SELECT ON schemata TO PUBLIC;


DROP VIEW IF EXISTS table_constraints CASCADE;
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
             AS initially_deferred

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
           CAST('NO' AS yes_or_no) AS initially_deferred

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

GRANT SELECT ON table_constraints TO PUBLIC;

DROP VIEW IF EXISTS tables CASCADE;
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
           CAST(d.description AS information_schema.character_data) AS TABLE_COMMENT

    FROM pg_namespace nc JOIN pg_class c ON (nc.oid = c.relnamespace)
           LEFT JOIN (pg_type t JOIN pg_namespace nt ON (t.typnamespace = nt.oid)) ON (c.reloftype = t.oid)
           LEFT JOIN pg_description d on d.objoid = c.oid and objsubid = 0

    WHERE c.relkind IN ('r', 'm', 'v', 'f')
          AND (c.relname not like 'mlog\_%' AND c.relname not like 'matviewmap\_%')
          AND (NOT pg_catalog.pg_is_other_temp_schema(nc.oid))
          AND (pg_catalog.pg_has_role(c.relowner, 'USAGE')
               OR pg_catalog.has_table_privilege(c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
               OR pg_catalog.has_any_column_privilege(c.oid, 'SELECT, INSERT, UPDATE, REFERENCES') );
GRANT SELECT ON tables TO PUBLIC;



DO $$
DECLARE
    view_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = 'data_type_privileges'
          AND n.nspname = 'information_schema'
          AND c.relkind = 'v'
    ) INTO view_exists;
    IF NOT view_exists THEN
    CREATE VIEW data_type_privileges AS
        SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS object_catalog,
           CAST(x.objschema AS sql_identifier) AS object_schema,
           CAST(x.objname AS sql_identifier) AS object_name,
           CAST(x.objtype AS character_data) AS object_type,
           CAST(x.objdtdid AS sql_identifier) AS dtd_identifier

     FROM
       (
        SELECT udt_schema, udt_name, 'USER-DEFINED TYPE'::text, dtd_identifier FROM attributes
        UNION ALL
        SELECT table_schema, table_name, 'TABLE'::text, dtd_identifier FROM information_schema.columns
        UNION ALL
        SELECT domain_schema, domain_name, 'DOMAIN'::text, dtd_identifier FROM domains
        UNION ALL
        SELECT specific_schema, specific_name, 'ROUTINE'::text, dtd_identifier FROM parameters
        UNION ALL
        SELECT specific_schema, specific_name, 'ROUTINE'::text, dtd_identifier FROM routines
       ) AS x (objschema, objname, objtype, objdtdid);
    END IF;
END $$;



DO $$
DECLARE
    view_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = 'element_types'
          AND n.nspname = 'information_schema'
          AND c.relkind = 'v'
    ) INTO view_exists;
    IF NOT view_exists THEN
    CREATE VIEW element_types AS
        SELECT CAST(pg_catalog.current_database() AS sql_identifier) AS object_catalog,
           CAST(n.nspname AS sql_identifier) AS object_schema,
           CAST(x.objname AS sql_identifier) AS object_name,
           CAST(x.objtype AS character_data) AS object_type,
           CAST(x.objdtdid AS sql_identifier) AS collection_type_identifier,
           CAST(
             CASE WHEN nbt.nspname = 'pg_catalog' THEN pg_catalog.format_type(bt.oid, null)
                  ELSE 'USER-DEFINED' END AS character_data) AS data_type,

           CAST(null AS cardinal_number) AS character_maximum_length,
           CAST(null AS cardinal_number) AS character_octet_length,
           CAST(null AS sql_identifier) AS character_set_catalog,
           CAST(null AS sql_identifier) AS character_set_schema,
           CAST(null AS sql_identifier) AS character_set_name,
           CAST(CASE WHEN nco.nspname IS NOT NULL THEN pg_catalog.current_database() END AS sql_identifier) AS collation_catalog,
           CAST(nco.nspname AS sql_identifier) AS collation_schema,
           CAST(co.collname AS sql_identifier) AS collation_name,
           CAST(null AS cardinal_number) AS numeric_precision,
           CAST(null AS cardinal_number) AS numeric_precision_radix,
           CAST(null AS cardinal_number) AS numeric_scale,
           CAST(null AS cardinal_number) AS datetime_precision,
           CAST(null AS character_data) AS interval_type,
           CAST(null AS cardinal_number) AS interval_precision,

           CAST(null AS character_data) AS domain_default, -- XXX maybe a bug in the standard

           CAST(pg_catalog.current_database() AS sql_identifier) AS udt_catalog,
           CAST(nbt.nspname AS sql_identifier) AS udt_schema,
           CAST(bt.typname AS sql_identifier) AS udt_name,

           CAST(null AS sql_identifier) AS scope_catalog,
           CAST(null AS sql_identifier) AS scope_schema,
           CAST(null AS sql_identifier) AS scope_name,

           CAST(null AS cardinal_number) AS maximum_cardinality,
           CAST('a' || CAST(x.objdtdid AS text) AS sql_identifier) AS dtd_identifier

    FROM pg_namespace n, pg_type at, pg_namespace nbt, pg_type bt,
         (
           /* columns, attributes */
           SELECT c.relnamespace, CAST(c.relname AS sql_identifier),
                  CASE WHEN c.relkind = 'c' THEN 'USER-DEFINED TYPE'::text ELSE 'TABLE'::text END,
                  a.attnum, a.atttypid, a.attcollation
           FROM pg_class c, pg_attribute a
           WHERE c.oid = a.attrelid
                 AND c.relkind IN ('r', 'm', 'v', 'f', 'c')
                 AND (c.relname not like 'mlog\_%' AND c.relname not like 'matviewmap\_%')
                 AND attnum > 0 AND NOT attisdropped

           UNION ALL

           /* domains */
           SELECT t.typnamespace, CAST(t.typname AS sql_identifier),
                  'DOMAIN'::text, 1, t.typbasetype, t.typcollation
           FROM pg_type t
           WHERE t.typtype = 'd'

           UNION ALL

           /* parameters */
           SELECT pronamespace, CAST(proname || '_' || CAST(oid AS text) AS sql_identifier),
                  'ROUTINE'::text, (ss.x).n, (ss.x).x, 0
           FROM (SELECT p.pronamespace, p.proname, p.oid,
                        _pg_expandarray(coalesce(p.proallargtypes, p.proargtypes::oid[])) AS x
                 FROM pg_proc p) AS ss

           UNION ALL

           /* result types */
           SELECT p.pronamespace, CAST(p.proname || '_' || CAST(p.oid AS text) AS sql_identifier),
                  'ROUTINE'::text, 0, p.prorettype, 0
           FROM pg_proc p

         ) AS x (objschema, objname, objtype, objdtdid, objtypeid, objcollation)
         LEFT JOIN (pg_collation co JOIN pg_namespace nco ON (co.collnamespace = nco.oid))
           ON x.objcollation = co.oid AND (nco.nspname, co.collname) <> ('pg_catalog', 'default')

    WHERE n.oid = x.objschema
          AND at.oid = x.objtypeid
          AND (at.typelem <> 0 AND at.typlen = -1)
          AND at.typelem = bt.oid
          AND nbt.oid = bt.typnamespace

          AND (n.nspname, x.objname, x.objtype, CAST(x.objdtdid AS sql_identifier)) IN
              ( SELECT object_schema, object_name, object_type, dtd_identifier
                    FROM data_type_privileges );
    END IF;
END $$;


do $$DECLARE
    user_name text;
    query_str text;
BEGIN
    SELECT SESSION_USER INTO user_name;
    query_str := 'GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON information_schema.element_types TO ' || quote_ident(user_name) || ';';
    EXECUTE IMMEDIATE query_str;
    query_str := 'GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON information_schema.data_type_privileges TO ' || quote_ident(user_name) || ';';
    EXECUTE IMMEDIATE query_str;
    query_str := 'GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON information_schema.tables TO ' || quote_ident(user_name) || ';';
    EXECUTE IMMEDIATE query_str;
    query_str := 'GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON information_schema.columns TO ' || quote_ident(user_name) || ';';
    EXECUTE IMMEDIATE query_str;
END$$;

GRANT SELECT ON information_schema.element_types TO PUBLIC;
GRANT SELECT ON information_schema.data_type_privileges TO PUBLIC;
GRANT SELECT ON information_schema.tables TO PUBLIC;
GRANT SELECT ON information_schema.columns TO PUBLIC;


DROP VIEW IF EXISTS KEYWORDS;
DROP VIEW IF EXISTS statistics;
DROP VIEW IF EXISTS partitions;

DROP FUNCTION IF EXISTS pg_catalog.pg_get_expr(text, oid);
DROP FUNCTION IF EXISTS pg_catalog.pg_extract_collate_name(oid);
DROP FUNCTION IF EXISTS pg_catalog.get_table_option(reloptions_info  text[], option_key text); 
DROP FUNCTION IF EXISTS pg_catalog.get_param_values(text);
DROP FUNCTION IF EXISTS pg_catalog.get_auto_increment_nextval(oid, bool);
DROP FUNCTION IF EXISTS pg_catalog.pg_avg_row_length(oid, oid);
DROP FUNCTION IF EXISTS pg_catalog.pg_get_index_type(oid, int2);
DROP FUNCTION IF EXISTS pg_catalog.attnum_used_by_indexprs(text, int2);
DROP FUNCTION IF EXISTS pg_catalog.pg_get_partition_expression(oid, int, bool);
DROP FUNCTION IF EXISTS pg_catalog.partstrategy_to_full_str(input "char");

RESET search_path;
