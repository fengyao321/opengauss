CREATE TABLE tst (i int4, t text);

CREATE INDEX bloomidx ON tst USING bloom (i, t) WITH (col1 = 3, col2 = 3);
INSERT INTO tst SELECT i%10, substr(md5(i::text), 1, 1) FROM generate_series(1,100000) i;

ALTER INDEX bloomidx SET (col1 = 3, col2 = 3);
INSERT INTO tst SELECT i%10, substr(md5(i::text), 1, 1) FROM generate_series(1,100000) i;

SET enable_seqscan=on;
SET enable_bitmapscan=off;
SET enable_indexscan=off;

SELECT count(*) FROM tst WHERE i = 7;
SELECT count(*) FROM tst WHERE t = '5';
SELECT count(*) FROM tst WHERE i = 7 AND t = '5';

SET enable_seqscan=off;
SET enable_bitmapscan=on;
SET enable_indexscan=on;

EXPLAIN (COSTS OFF) SELECT count(*) FROM tst WHERE i = 7;
EXPLAIN (COSTS OFF) SELECT count(*) FROM tst WHERE t = '5';
EXPLAIN (COSTS OFF) SELECT count(*) FROM tst WHERE i = 7 AND t = '5';

SELECT count(*) FROM tst WHERE i = 7;
SELECT count(*) FROM tst WHERE t = '5';
SELECT count(*) FROM tst WHERE i = 7 AND t = '5';

DELETE FROM tst;
INSERT INTO tst SELECT i%10, substr(md5(i::text), 1, 1) FROM generate_series(1,100000) i;
VACUUM ANALYZE tst;

SELECT count(*) FROM tst WHERE i = 7;
SELECT count(*) FROM tst WHERE t = '5';
SELECT count(*) FROM tst WHERE i = 7 AND t = '5';

VACUUM FULL tst;

SELECT count(*) FROM tst WHERE i = 7;
SELECT count(*) FROM tst WHERE t = '5';
SELECT count(*) FROM tst WHERE i = 7 AND t = '5';

RESET enable_seqscan;
RESET enable_bitmapscan;
RESET enable_indexscan;

DROP TABLE tst;

create table bloom_table (id1 int, id2 int, id3 text);
insert into bloom_table values (1,11,'111'),(2,22,'222');
CREATE INDEX bloom_index ON bloom_table USING bloom (id1,id2,id3) WITH (length=4096, col1=2, col2=2, col3=4);
drop index bloom_index;
drop table bloom_table;
