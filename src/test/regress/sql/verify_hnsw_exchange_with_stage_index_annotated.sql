\set ON_ERROR_STOP on
\pset pager off

\echo ==== Step 0: Environment ====
SELECT current_user, current_database(), version();

\echo ==== Step 1: Cleanup old objects ====
DROP TABLE IF EXISTS public.embedding_hnsw_exchange_parent_script_demo CASCADE;
DROP TABLE IF EXISTS public.embedding_hnsw_exchange_stage_script_demo CASCADE;

\echo ==== Step 2: Create parent table with two partitions ====
CREATE TABLE public.embedding_hnsw_exchange_parent_script_demo (
    id int,
    part_key int,
    title text,
    embedding vector(3)
)
PARTITION BY RANGE (part_key)
(
    PARTITION p1 VALUES LESS THAN (50),
    PARTITION p2 VALUES LESS THAN (100)
);

INSERT INTO public.embedding_hnsw_exchange_parent_script_demo VALUES
    (1, 1, 'seed-1', '[1,2,3]'),
    (2, 2, 'seed-2', '[2,3,4]'),
    (51, 51, 'seed-51', '[51,52,53]'),
    (52, 52, 'seed-52', '[52,53,54]');

SELECT 'parent_seed_rows' AS check_name, p.relname AS partition_name, count(*) AS row_count
FROM public.embedding_hnsw_exchange_parent_script_demo t
JOIN pg_partition p ON p.oid = t.tableoid
GROUP BY p.relname
ORDER BY p.relname;

\echo ==== Step 3: Create LOCAL HNSW index on parent table ====
CREATE INDEX embedding_hnsw_exchange_parent_script_idx
ON public.embedding_hnsw_exchange_parent_script_demo
USING hnsw (embedding vector_l2_ops)
LOCAL
(
    PARTITION p1_hnsw_idx,
    PARTITION p2_hnsw_idx
);

SELECT pg_get_indexdef('public.embedding_hnsw_exchange_parent_script_idx'::regclass, true);

SELECT 'parent_index_parts_initial' AS check_name, relname, indisusable
FROM pg_partition
WHERE parentid = 'public.embedding_hnsw_exchange_parent_script_idx'::regclass
ORDER BY relname;

\echo ==== Step 4: Create stage table without vector index ====
CREATE TABLE public.embedding_hnsw_exchange_stage_script_demo (
    id int,
    part_key int,
    title text,
    embedding vector(3)
);

SELECT 'stage_index_count_before' AS check_name, count(*) AS idx_count
FROM pg_index
WHERE indrelid = 'public.embedding_hnsw_exchange_stage_script_demo'::regclass;

\echo ==== Step 5: COPY 100 rows into stage table ====
COPY public.embedding_hnsw_exchange_stage_script_demo (id, part_key, title, embedding)
FROM STDIN WITH (FORMAT csv);
101,101,doc-101,"[101,102,103]"
102,102,doc-102,"[102,103,104]"
103,103,doc-103,"[103,104,105]"
104,104,doc-104,"[104,105,106]"
105,105,doc-105,"[105,106,107]"
106,106,doc-106,"[106,107,108]"
107,107,doc-107,"[107,108,109]"
108,108,doc-108,"[108,109,110]"
109,109,doc-109,"[109,110,111]"
110,110,doc-110,"[110,111,112]"
111,111,doc-111,"[111,112,113]"
112,112,doc-112,"[112,113,114]"
113,113,doc-113,"[113,114,115]"
114,114,doc-114,"[114,115,116]"
115,115,doc-115,"[115,116,117]"
116,116,doc-116,"[116,117,118]"
117,117,doc-117,"[117,118,119]"
118,118,doc-118,"[118,119,120]"
119,119,doc-119,"[119,120,121]"
120,120,doc-120,"[120,121,122]"
121,121,doc-121,"[121,122,123]"
122,122,doc-122,"[122,123,124]"
123,123,doc-123,"[123,124,125]"
124,124,doc-124,"[124,125,126]"
125,125,doc-125,"[125,126,127]"
126,126,doc-126,"[126,127,128]"
127,127,doc-127,"[127,128,129]"
128,128,doc-128,"[128,129,130]"
129,129,doc-129,"[129,130,131]"
130,130,doc-130,"[130,131,132]"
131,131,doc-131,"[131,132,133]"
132,132,doc-132,"[132,133,134]"
133,133,doc-133,"[133,134,135]"
134,134,doc-134,"[134,135,136]"
135,135,doc-135,"[135,136,137]"
136,136,doc-136,"[136,137,138]"
137,137,doc-137,"[137,138,139]"
138,138,doc-138,"[138,139,140]"
139,139,doc-139,"[139,140,141]"
140,140,doc-140,"[140,141,142]"
141,141,doc-141,"[141,142,143]"
142,142,doc-142,"[142,143,144]"
143,143,doc-143,"[143,144,145]"
144,144,doc-144,"[144,145,146]"
145,145,doc-145,"[145,146,147]"
146,146,doc-146,"[146,147,148]"
147,147,doc-147,"[147,148,149]"
148,148,doc-148,"[148,149,150]"
149,149,doc-149,"[149,150,151]"
150,150,doc-150,"[150,151,152]"
151,151,doc-151,"[151,152,153]"
152,152,doc-152,"[152,153,154]"
153,153,doc-153,"[153,154,155]"
154,154,doc-154,"[154,155,156]"
155,155,doc-155,"[155,156,157]"
156,156,doc-156,"[156,157,158]"
157,157,doc-157,"[157,158,159]"
158,158,doc-158,"[158,159,160]"
159,159,doc-159,"[159,160,161]"
160,160,doc-160,"[160,161,162]"
161,161,doc-161,"[161,162,163]"
162,162,doc-162,"[162,163,164]"
163,163,doc-163,"[163,164,165]"
164,164,doc-164,"[164,165,166]"
165,165,doc-165,"[165,166,167]"
166,166,doc-166,"[166,167,168]"
167,167,doc-167,"[167,168,169]"
168,168,doc-168,"[168,169,170]"
169,169,doc-169,"[169,170,171]"
170,170,doc-170,"[170,171,172]"
171,171,doc-171,"[171,172,173]"
172,172,doc-172,"[172,173,174]"
173,173,doc-173,"[173,174,175]"
174,174,doc-174,"[174,175,176]"
175,175,doc-175,"[175,176,177]"
176,176,doc-176,"[176,177,178]"
177,177,doc-177,"[177,178,179]"
178,178,doc-178,"[178,179,180]"
179,179,doc-179,"[179,180,181]"
180,180,doc-180,"[180,181,182]"
181,181,doc-181,"[181,182,183]"
182,182,doc-182,"[182,183,184]"
183,183,doc-183,"[183,184,185]"
184,184,doc-184,"[184,185,186]"
185,185,doc-185,"[185,186,187]"
186,186,doc-186,"[186,187,188]"
187,187,doc-187,"[187,188,189]"
188,188,doc-188,"[188,189,190]"
189,189,doc-189,"[189,190,191]"
190,190,doc-190,"[190,191,192]"
191,191,doc-191,"[191,192,193]"
192,192,doc-192,"[192,193,194]"
193,193,doc-193,"[193,194,195]"
194,194,doc-194,"[194,195,196]"
195,195,doc-195,"[195,196,197]"
196,196,doc-196,"[196,197,198]"
197,197,doc-197,"[197,198,199]"
198,198,doc-198,"[198,199,200]"
199,199,doc-199,"[199,200,201]"
200,200,doc-200,"[200,201,202]"
\.

SELECT 'stage_rows_after_copy' AS check_name,
       count(*) AS row_count,
       min(part_key) AS min_part_key,
       max(part_key) AS max_part_key
FROM public.embedding_hnsw_exchange_stage_script_demo;

\echo ==== Step 6: Create HNSW index on stage table ====
CREATE INDEX embedding_hnsw_exchange_stage_script_idx
ON public.embedding_hnsw_exchange_stage_script_demo
USING hnsw (embedding vector_l2_ops);

SELECT pg_get_indexdef('public.embedding_hnsw_exchange_stage_script_idx'::regclass, true);

SELECT 'stage_index_count_after' AS check_name, count(*) AS idx_count
FROM pg_index
WHERE indrelid = 'public.embedding_hnsw_exchange_stage_script_demo'::regclass;

\echo ==== Step 7: Add new partition p3 to parent table ====
ALTER TABLE public.embedding_hnsw_exchange_parent_script_demo
ADD PARTITION p3 VALUES LESS THAN (201);

SELECT 'parent_rows_before_exchange' AS check_name, p.relname AS partition_name, count(*) AS row_count
FROM public.embedding_hnsw_exchange_parent_script_demo t
JOIN pg_partition p ON p.oid = t.tableoid
GROUP BY p.relname
ORDER BY p.relname;

SELECT 'parent_index_parts_before_exchange' AS check_name, relname, indisusable
FROM pg_partition
WHERE parentid = 'public.embedding_hnsw_exchange_parent_script_idx'::regclass
ORDER BY relname;

SELECT 'stage_rows_before_exchange' AS check_name, count(*) AS row_count
FROM public.embedding_hnsw_exchange_stage_script_demo;

\echo ==== Step 8: EXCHANGE stage table into parent partition p3 ====
ALTER TABLE public.embedding_hnsw_exchange_parent_script_demo
EXCHANGE PARTITION (p3) WITH TABLE public.embedding_hnsw_exchange_stage_script_demo;

SELECT 'parent_rows_after_exchange' AS check_name, p.relname AS partition_name, count(*) AS row_count
FROM public.embedding_hnsw_exchange_parent_script_demo t
JOIN pg_partition p ON p.oid = t.tableoid
GROUP BY p.relname
ORDER BY p.relname;

SELECT 'stage_rows_after_exchange' AS check_name, count(*) AS row_count
FROM public.embedding_hnsw_exchange_stage_script_demo;

SELECT 'parent_index_parts_after_exchange' AS check_name, relname, indisusable
FROM pg_partition
WHERE parentid = 'public.embedding_hnsw_exchange_parent_script_idx'::regclass
ORDER BY relname;

SELECT pg_get_indexdef('public.embedding_hnsw_exchange_parent_script_idx'::regclass, true);

\echo ==== Step 9: Verify ANN query plan and query result on exchanged partition ====
SET enable_seqscan = off;
EXPLAIN
SELECT id, part_key, title
FROM public.embedding_hnsw_exchange_parent_script_demo
WHERE part_key >= 100 AND part_key < 201
ORDER BY embedding <-> '[150,151,152]'::vector
LIMIT 5;
RESET enable_seqscan;

SELECT id, part_key, title
FROM public.embedding_hnsw_exchange_parent_script_demo
WHERE part_key >= 100 AND part_key < 201
ORDER BY embedding <-> '[150,151,152]'::vector
LIMIT 5;


-- ===== Verified Output =====
-- Pager usage is off.
-- ==== Step 0: Environment ====
--  current_user | current_database |                                                      version                                                       
-- --------------+------------------+--------------------------------------------------------------------------------------------------------------------
--  s00524258    | postgres         | openGauss 7.0.0-RC1 (openGauss 7.0.0-RC1 build cef85e40) compiled at 2026-03-11 09:54:51 commit 0 last mr  release
-- (1 row)
-- 
-- ==== Step 1: Cleanup old objects ====
-- gsql:/home/s00524258/openGauss-server/verify_hnsw_exchange_with_stage_index.sql:8: NOTICE:  table "embedding_hnsw_exchange_parent_script_demo" does not exist, skipping
-- DROP TABLE
-- gsql:/home/s00524258/openGauss-server/verify_hnsw_exchange_with_stage_index.sql:9: NOTICE:  table "embedding_hnsw_exchange_stage_script_demo" does not exist, skipping
-- DROP TABLE
-- ==== Step 2: Create parent table with two partitions ====
-- CREATE TABLE
-- INSERT 0 4
--     check_name    | partition_name | row_count 
-- ------------------+----------------+-----------
--  parent_seed_rows | p1             |         2
--  parent_seed_rows | p2             |         2
-- (2 rows)
-- 
-- ==== Step 3: Create LOCAL HNSW index on parent table ====
-- CREATE INDEX
--                                                                                                    pg_get_indexdef                                                                                                    
-- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  CREATE INDEX embedding_hnsw_exchange_parent_script_idx ON embedding_hnsw_exchange_parent_script_demo USING hnsw (embedding vector_l2_ops) LOCAL(PARTITION p1_hnsw_idx, PARTITION p2_hnsw_idx)  TABLESPACE pg_default
-- (1 row)
-- 
--          check_name         |   relname   | indisusable 
-- ----------------------------+-------------+-------------
--  parent_index_parts_initial | p1_hnsw_idx | t
--  parent_index_parts_initial | p2_hnsw_idx | t
-- (2 rows)
-- 
-- ==== Step 4: Create stage table without vector index ====
-- CREATE TABLE
--         check_name        | idx_count 
-- --------------------------+-----------
--  stage_index_count_before |         0
-- (1 row)
-- 
-- ==== Step 5: COPY 100 rows into stage table ====
--       check_name       | row_count | min_part_key | max_part_key 
-- -----------------------+-----------+--------------+--------------
--  stage_rows_after_copy |       100 |          101 |          200
-- (1 row)
-- 
-- ==== Step 6: Create HNSW index on stage table ====
-- CREATE INDEX
--                                                                         pg_get_indexdef                                                                        
-- ---------------------------------------------------------------------------------------------------------------------------------------------------------------
--  CREATE INDEX embedding_hnsw_exchange_stage_script_idx ON embedding_hnsw_exchange_stage_script_demo USING hnsw (embedding vector_l2_ops) TABLESPACE pg_default
-- (1 row)
-- 
--        check_name        | idx_count 
-- -------------------------+-----------
--  stage_index_count_after |         1
-- (1 row)
-- 
-- ==== Step 7: Add new partition p3 to parent table ====
-- ALTER TABLE
--          check_name          | partition_name | row_count 
-- -----------------------------+----------------+-----------
--  parent_rows_before_exchange | p1             |         2
--  parent_rows_before_exchange | p2             |         2
-- (2 rows)
-- 
--              check_name             |     relname      | indisusable 
-- ------------------------------------+------------------+-------------
--  parent_index_parts_before_exchange | p1_hnsw_idx      | t
--  parent_index_parts_before_exchange | p2_hnsw_idx      | t
--  parent_index_parts_before_exchange | p3_embedding_idx | t
-- (3 rows)
-- 
--          check_name         | row_count 
-- ----------------------------+-----------
--  stage_rows_before_exchange |       100
-- (1 row)
-- 
-- ==== Step 8: EXCHANGE stage table into parent partition p3 ====
-- gsql:/home/s00524258/openGauss-server/verify_hnsw_exchange_with_stage_index.sql:207: NOTICE:  Command without UPDATE GLOBAL INDEX will disable global index
-- ALTER TABLE
--          check_name         | partition_name | row_count 
-- ----------------------------+----------------+-----------
--  parent_rows_after_exchange | p1             |         2
--  parent_rows_after_exchange | p2             |         2
--  parent_rows_after_exchange | p3             |       100
-- (3 rows)
-- 
--         check_name         | row_count 
-- ---------------------------+-----------
--  stage_rows_after_exchange |         0
-- (1 row)
-- 
--             check_name             |     relname      | indisusable 
-- -----------------------------------+------------------+-------------
--  parent_index_parts_after_exchange | p1_hnsw_idx      | t
--  parent_index_parts_after_exchange | p2_hnsw_idx      | t
--  parent_index_parts_after_exchange | p3_embedding_idx | t
-- (3 rows)
-- 
--                                                                                                                  pg_get_indexdef                                                                                                                  
-- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  CREATE INDEX embedding_hnsw_exchange_parent_script_idx ON embedding_hnsw_exchange_parent_script_demo USING hnsw (embedding vector_l2_ops) LOCAL(PARTITION p1_hnsw_idx, PARTITION p2_hnsw_idx, PARTITION p3_embedding_idx)  TABLESPACE pg_default
-- (1 row)
-- 
-- ==== Step 9: Verify ANN query plan and query result on exchanged partition ====
-- SET
--                                                                                 QUERY PLAN                                                                                
-- --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--  Limit  (cost=4.73..68.76 rows=4 width=72)
--    ->  Partition Iterator  (cost=4.73..68.76 rows=4 width=72)
--          Iterations: 1
--          ->  Partitioned Ann Index Scan using embedding_hnsw_exchange_parent_script_idx on embedding_hnsw_exchange_parent_script_demo  (cost=4.73..68.75 rows=4 width=72)
--                Order By: (embedding <-> '[150,151,152]'::vector)
--                Filter: ((part_key >= 100) AND (part_key < 201))
--                Selected Partitions:  3
-- (7 rows)
-- 
-- RESET
--  id  | part_key |  title  
-- -----+----------+---------
--  150 |      150 | doc-150
--  151 |      151 | doc-151
--  149 |      149 | doc-149
--  148 |      148 | doc-148
--  152 |      152 | doc-152
-- (5 rows)
-- 
-- total time: 394  ms
