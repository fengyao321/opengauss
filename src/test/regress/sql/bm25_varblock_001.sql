-- BM25 VarBlock: online build + multi-chunk + vacuum empty token + update/reindex (merged)
SET client_min_messages = error;

DROP TABLE IF EXISTS bm25_varblock_001;

CREATE TABLE bm25_varblock_001 (
    id int PRIMARY KEY,
    content text
);

CREATE INDEX bm25_varblock_001_bm25_idx ON bm25_varblock_001 USING bm25(content);

-- Online insert after index (building=false posting updates).
INSERT INTO bm25_varblock_001(id, content)
SELECT g, 'apple'::text
FROM generate_series(1, 25) g;

INSERT INTO bm25_varblock_001(id, content)
SELECT g, 'banana'::text
FROM generate_series(26, 50) g;

SET enable_seqscan = off;
SET enable_indexscan = on;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'apple' DESC
      LIMIT 25) TO STDOUT;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'apple banana' DESC
      LIMIT 50) TO STDOUT;

-- Grow postings to span multiple VarBlock chunks (same token mass insert).
INSERT INTO bm25_varblock_001(id, content)
SELECT g, 'apple'::text
FROM generate_series(51, 210) g;

INSERT INTO bm25_varblock_001(id, content)
SELECT g, 'banana'::text
FROM generate_series(211, 370) g;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'apple' DESC
      LIMIT 5) TO STDOUT;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'banana' DESC
      LIMIT 5) TO STDOUT;

-- Partial delete + vacuum (subset rebuild).
DELETE FROM bm25_varblock_001
WHERE id <= 60 OR (id >= 211 AND id <= 270);

VACUUM bm25_varblock_001;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'apple' DESC
      LIMIT 5) TO STDOUT;

-- Delete all apple docs: posting chain for token should go empty.
DELETE FROM bm25_varblock_001 WHERE id <= 210;
VACUUM bm25_varblock_001;

COPY (SELECT COALESCE((
            SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
            FROM bm25_varblock_001
            ORDER BY content <&> 'apple' DESC
            LIMIT 1
        ), -1)) TO STDOUT;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'banana' DESC
      LIMIT 5) TO STDOUT;

INSERT INTO bm25_varblock_001(id, content)
SELECT g, 'apple'::text
FROM generate_series(371, 430) g;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'apple' DESC
      LIMIT 5) TO STDOUT;

-- Update-driven posting moves + reindex.
UPDATE bm25_varblock_001
SET content = 'grape'
WHERE id BETWEEN 380 AND 410;

VACUUM bm25_varblock_001;

REINDEX INDEX bm25_varblock_001_bm25_idx;

SET enable_seqscan = off;
SET enable_indexscan = on;

COPY (SELECT /*+ indexscan(bm25_varblock_001 bm25_varblock_001_bm25_idx) */ id
      FROM bm25_varblock_001
      ORDER BY content <&> 'banana' DESC
      LIMIT 5) TO STDOUT;

DROP TABLE bm25_varblock_001;
