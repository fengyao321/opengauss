-- BM25 parallel CREATE INDEX (heap parallel scan + parallel reorder workers). No ORDER BY queries (ties unstable).
-- Requires table parallel_workers > 0 and postmaster able to launch background workers.
SET client_min_messages = error;

DROP TABLE IF EXISTS bm25_parallel_build;

CREATE TABLE bm25_parallel_build (
    id int PRIMARY KEY,
    content text
) WITH (parallel_workers = 4);

INSERT INTO bm25_parallel_build(id, content)
SELECT g, ('tok' || (g % 80))::text
FROM generate_series(1, 8000) g;

CREATE INDEX bm25_parallel_build_idx ON bm25_parallel_build USING bm25(content);

DROP TABLE bm25_parallel_build;
