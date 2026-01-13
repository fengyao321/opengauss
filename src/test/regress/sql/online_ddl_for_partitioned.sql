CREATE SCHEMA IF NOT EXISTS test_ddl;
SET current_schema = test_ddl;

CREATE OR REPLACE FUNCTION create_partitioned_table(tablename TEXT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format('
        CREATE TABLE %I (
            id int NOT NULL,
            value1 varchar,
            value2 int
        ) PARTITION BY RANGE (id) (
            PARTITION %I_p1 VALUES LESS THAN (5),
            PARTITION %I_p2 VALUES LESS THAN (10),
            PARTITION %I_p3 VALUES LESS THAN (MAXVALUE)
        );
    ', tablename, tablename, tablename, tablename);
END;
$$ LANGUAGE plpgsql;

-- Case 1: alter column type in transaction block
DROP TABLE IF EXISTS online_ddl_test_error;
SELECT create_partitioned_table('online_ddl_test_error');
BEGIN;
ALTER TABLE CONCURRENTLY online_ddl_test_error ALTER COLUMN value1 TYPE int; -- ERROR
ROLLBACK;
\d+ online_ddl_test_error

-- Case 2: set not null in transaction block
DROP TABLE IF EXISTS online_ddl_test_error;
SELECT create_partitioned_table('online_ddl_test_error');
BEGIN;
ALTER TABLE CONCURRENTLY online_ddl_test_error ALTER COLUMN value2 SET NOT NULL; -- ERROR
ROLLBACK;
\d+ online_ddl_test_error

-- Case 3: subtransaction block
DROP TABLE IF EXISTS online_ddl_test_error;
SELECT create_partitioned_table('online_ddl_test_error');
BEGIN;
SAVEPOINT sp1;
ALTER TABLE CONCURRENTLY online_ddl_test_error ALTER COLUMN value1 TYPE int; -- ERROR
ROLLBACK;
\d+ online_ddl_test_error

-- Case 4: subtransaction + set not null
DROP TABLE IF EXISTS online_ddl_test_error;
SELECT create_partitioned_table('online_ddl_test_error');
BEGIN;
SAVEPOINT sp1;
ALTER TABLE CONCURRENTLY online_ddl_test_error ALTER COLUMN value2 SET NOT NULL; -- ERROR
ROLLBACK;
\d+ online_ddl_test_error

-- Case 5: alter command with no concurrently gram
DROP TABLE IF EXISTS online_ddl_test_error;
SELECT create_partitioned_table('online_ddl_test_error');
ALTER TABLE CONCURRENTLY online_ddl_test_error RENAME COLUMN value1 TO value_1; -- ERROR
\d+ online_ddl_test_error

-- Case 6: alter column set not null with null value
DROP TABLE IF EXISTS online_ddl_test_not_null;
SELECT create_partitioned_table('online_ddl_test_not_null');
INSERT INTO online_ddl_test_not_null SELECT generate_series(1, 10), 'test', 111;
INSERT INTO online_ddl_test_not_null VALUES (11, 'test_null', NULL);
ALTER TABLE CONCURRENTLY online_ddl_test_not_null ALTER COLUMN value2 SET NOT NULL; -- ERROR
\d+ online_ddl_test_not_null

-- Case 7: alter column set range constraint with out of range value
DROP TABLE IF EXISTS online_ddl_test_range;
SELECT create_partitioned_table('online_ddl_test_range');
INSERT INTO online_ddl_test_range SELECT generate_series(1, 10), 'test', 9;
INSERT INTO online_ddl_test_range VALUES (11, 'test_out_of_range', 11);
ALTER TABLE CONCURRENTLY online_ddl_test_range ADD CONSTRAINT ck_online_ddl_test_range CHECK (value2 > 1 AND value2 < 10); -- ERROR
\d+ online_ddl_test_range

-- Case 9: alter command no need to rewrite table
DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip ALTER COLUMN id SET DEFAULT 100; -- SKIP
\d+ online_ddl_test_skip

DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip ADD COLUMN value3 int; -- SKIP
\d+ online_ddl_test_skip

DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip DROP COLUMN value3; -- SKIP
\d+ online_ddl_test_skip

DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip RENAME COLUMN value1 TO value_1; -- ERROR
\d+ online_ddl_test_skip

-- Add constraint unique
DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip ADD CONSTRAINT uq_online_ddl_test_skip UNIQUE (value2); -- SKIP
\d+ online_ddl_test_skip

-- Add primary key
DROP TABLE IF EXISTS online_ddl_test_skip;
SELECT create_partitioned_table('online_ddl_test_skip');
ALTER TABLE CONCURRENTLY online_ddl_test_skip ADD CONSTRAINT pk_online_ddl_test_skip PRIMARY KEY (id); -- SKIP
\d+ online_ddl_test_skip

-- Case 10: alter column add constraint with valid data
DROP TABLE IF EXISTS online_ddl_test_valid;
SELECT create_partitioned_table('online_ddl_test_valid');
INSERT INTO online_ddl_test_valid SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_valid ALTER COLUMN value2 SET NOT NULL; -- SUCCESS
\d+ online_ddl_test_valid

DROP TABLE IF EXISTS online_ddl_test_valid;
SELECT create_partitioned_table('online_ddl_test_valid');
INSERT INTO online_ddl_test_valid SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_valid ADD CONSTRAINT ck_online_ddl_test_valid CHECK (value2 > 1 AND value2 < 10); -- SUCCESS
\d+ online_ddl_test_valid

-- Case 11: alter table concurrently set row compression
-- No need to rewrite table
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compress_level = 0); -- SKIP
\d+ online_ddl_test_compress

DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
ALTER TABLE online_ddl_test_compress SET (compresstype=2, compress_level = 15);
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compresstype=2, compress_level = 15); -- SKIP
\d+ online_ddl_test_compress

-- No compress to compress
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compresstype=2, compress_level = 15); -- SUCCESS
\d+ online_ddl_test_compress

-- Indexed table no compress to compress
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
CREATE INDEX idx_online_ddl_test_compress_value1 ON online_ddl_test_compress USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_compress_value2 ON online_ddl_test_compress USING hash (value2) local;
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compresstype=2, compress_level = 15); -- SUCCESS
\d+ online_ddl_test_compress

-- Compress to no compress
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
ALTER TABLE online_ddl_test_compress SET (compresstype=2, compress_level = 15);
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress RESET (compresstype, compress_level); -- SUCCESS
\d+ online_ddl_test_compress

-- Indexed table compress to no compress
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
CREATE INDEX idx_online_ddl_test_compress_value1 ON online_ddl_test_compress USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_compress_value2 ON online_ddl_test_compress USING hash (value2) local;
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress RESET (compresstype, compress_level); -- SUCCESS
\d+ online_ddl_test_compress

-- Alter compress level
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
ALTER TABLE online_ddl_test_compress SET (compresstype=2, compress_level = 10);
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compress_level = 5); -- SUCCESS
\d+ online_ddl_test_compress

-- Indexed table alter compress level
DROP TABLE IF EXISTS online_ddl_test_compress;
SELECT create_partitioned_table('online_ddl_test_compress');
CREATE INDEX idx_online_ddl_test_compress_value1 ON online_ddl_test_compress USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_compress_value2 ON online_ddl_test_compress USING hash (value2) local;
ALTER TABLE online_ddl_test_compress SET (compresstype=2, compress_level = 10);
INSERT INTO online_ddl_test_compress SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_compress SET (compress_level = 5); -- SUCCESS
\d+ online_ddl_test_compress

-- Case 12: alter table concurrently alter column type with valid data
-- Int to varchar and varchar to int
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', '1000';
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE int;
\d+ online_ddl_test_alter_type

DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE varchar;
\d+ online_ddl_test_alter_type

-- Indexed table varchar to int
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
CREATE INDEX idx_online_ddl_test_alter_type_value1 ON online_ddl_test_alter_type USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_alter_type_value1_hash ON online_ddl_test_alter_type USING hash (value1) local;
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', '1000';
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE int;
\d+ online_ddl_test_alter_type

-- Int to bigint and bigint to int
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', 5;
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE bigint;
\d+ online_ddl_test_alter_type

-- Indexed table int to bigint
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
CREATE INDEX idx_online_ddl_test_alter_type_value1 ON online_ddl_test_alter_type USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_alter_type_value1_hash ON online_ddl_test_alter_type USING hash (value1) local;
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', 1000;
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE bigint;
\d+ online_ddl_test_alter_type

-- Indexed table huge number of rows
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
CREATE INDEX idx_online_ddl_test_alter_type_value1 ON online_ddl_test_alter_type USING btree (value1) local;
CREATE INDEX idx_online_ddl_test_alter_type_value1_hash ON online_ddl_test_alter_type USING hash (value1) local;
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 1000), 'test', 1000;
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE bigint;
\d+ online_ddl_test_alter_type
SELECT count(*) FROM online_ddl_test_alter_type;


-- Indexed table with toast data
DROP TABLE IF EXISTS online_ddl_test_alter_type_toast;
SELECT create_partitioned_table('online_ddl_test_alter_type_toast');
CREATE INDEX idx_online_ddl_test_alter_type_toast_value2 ON online_ddl_test_alter_type_toast USING btree (value2) local;
CREATE INDEX idx_online_ddl_test_alter_type_toast_value2_hash ON online_ddl_test_alter_type_toast USING hash (value2) local;
ALTER TABLE online_ddl_test_alter_type_toast ALTER value1 SET STORAGE EXTERNAL;
INSERT INTO online_ddl_test_alter_type_toast SELECT generate_series(1, 10), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz0123456789', '1000';
SELECT COUNT(*) FROM pg_class WHERE oid = (SELECT reltoastrelid FROM pg_class WHERE relname = 'online_ddl_test_alter_type_toast');
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type_toast ALTER COLUMN value2 TYPE int;
\d+ online_ddl_test_alter_type_toast

-- Case 13: : alter table concurrently alter column type with invalid data
DROP TABLE IF EXISTS online_ddl_test_alter_type;
SELECT create_partitioned_table('online_ddl_test_alter_type');
INSERT INTO online_ddl_test_alter_type SELECT generate_series(1, 10), 'test', 'not number';
ALTER TABLE CONCURRENTLY online_ddl_test_alter_type ALTER COLUMN value2 TYPE int;
\d+ online_ddl_test_alter_type

DROP SCHEMA IF EXISTS test_ddl CASCADE;