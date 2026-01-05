CREATE TABLE buffercache_test(
	id int,
	content text
);

INSERT INTO buffercache_test VALUES(generate_series(1, 10000), 'To make a prairie it takes a clover and one bee, One clover and a bee, And revery. The revery alone will do, If bees are few.');

checkpoint;

SELECT storage_type, relforknumber, relblocknumber, isdirty, isvalid, usage_count, pinning_backends
FROM
	(SELECT relfilenode, 
		bucketid, 
		storage_type, 
		reltablespace, 
		reldatabase, 
		relforknumber, 
		relblocknumber, 
		isdirty, 
		isvalid, 
		usage_count, 
		pinning_backends
	FROM pg_buffercache_pages()) P 
	INNER JOIN pg_class ON (P.relfilenode = pg_class.oid)
	INNER JOIN pg_namespace ON (pg_class.relnamespace = pg_namespace.oid)
WHERE pg_class.relname = 'buffercache_test'
  AND pg_namespace.nspname = 'public'
ORDER BY relforknumber, relblocknumber;

DROP TABLE buffercache_test;
