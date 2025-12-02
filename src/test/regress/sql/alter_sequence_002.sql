DROP SCHEMA IF EXISTS test_alter_seq_sche_02 CASCADE;
CREATE SCHEMA test_alter_seq_sche_02;
SET CURRENT_SCHEMA TO test_alter_seq_sche_02;

CREATE SEQUENCE seqa;
CREATE SEQUENCE seqb;

SELECT NEXTVAL('seqa');
-- error
ALTER SEQUENCE seqa RENAME TO seqb;
ALTER SEQUENCE seqa RENAME TO seqa1;
SELECT NEXTVAL('seqa');
-- state of sequence
SELECT NEXTVAL('seqa1');

SELECT sequence_name, start_value, increment_by, max_value, min_value FROM seqa;
SELECT sequence_name, start_value, increment_by, max_value, min_value FROM seqa1;

DROP SEQUENCE seqa1;
DROP SEQUENCE seqb;

-- serial, internal sequence
CREATE TABLE t1 (a serial, b int);
INSERT INTO t1 (b) VALUES (1);
ALTER SEQUENCE t1_a_seq RENAME to a_seq1;
-- sequence_name: a_seq1
SELECT sequence_name, start_value, increment_by, max_value, min_value FROM a_seq1;
INSERT INTO t1 (b) VALUES (1);
SELECT a, b FROM t1 order by a;

-- copy serial success
CREATE TABLE t2 (like t1 INCLUDING DEFAULTS);
\d+ t2;
INSERT INTO t2 (b) VALUES (1);
INSERT INTO t2 (b) VALUES (1);
SELECT a, b FROM t1 order by a;

DROP TABLE t1;
DROP TABLE t2;

DROP SCHEMA test_alter_seq_sche_02 CASCADE;
