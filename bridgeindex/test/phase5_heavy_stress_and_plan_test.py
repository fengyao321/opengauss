#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
openGauss Ustore Bridge Index Phase 5: Heavy Stress & Execution Plan Verification Test Suite
Target Features:
  - TC-STR-01: Hash Index High-Scale (20,000 Rows) Point & Batch Queries (IndexScan & BitmapScan Verification)
  - TC-STR-02: GiST Spatial Heavy Stress (10,000 Points) with Bounding Box Queries & Ground Truth Verification
  - TC-STR-03: GIN Array Heavy Stress (10,000 Rows) Containment & Overlap Queries with Ground Truth Verification
  - TC-STR-04: GIN Full-Text Search (tsvector/tsquery, 5,000 Docs) Complex Logic & Ground Truth Verification
  - TC-STR-05: Intensive In-Place Updates vs Key Updates Churn (5,000 DMLs) & Consistency Check
  - TC-STR-06: Brutal Transaction Rollback, DELETE, VACUUM Slot Reuse & Anti-Phantom Tag Validation
  - TC-STR-07: Concurrent 4-Index (UBTree + Hash + GiST + GIN) Multi-Threaded Stress & Plan Assertion
"""

import sys
import time
import random
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg2

DB_CONFIG = {
    'dbname': 'postgres',
    'port': 5432,
    'host': '/tmp'
}

def get_connection():
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn

def print_header(title):
    print("\n" + "=" * 80)
    print(f">>> {title}")
    print("=" * 80)

def print_result(tc_id, name, success, detail=""):
    status = "PASS [SUCCESS]" if success else "FAIL [ERROR]"
    print(f"[{status}] {tc_id}: {name}")
    if detail:
        print(f"       Details: {detail}")

def assert_plan_node(cur, query_sql, params, expected_node, forbidden_nodes=None):
    """
    Executes EXPLAIN (ANALYZE, COSTS OFF) and verifies that expected_node is present,
    and forbidden_nodes (like 'Seq Scan') are absent.
    Returns the parsed plan text.
    """
    explain_sql = f"EXPLAIN (ANALYZE, COSTS OFF) {query_sql}"
    cur.execute(explain_sql, params)
    plan_lines = [r[0] for r in cur.fetchall()]
    plan_text = "\n".join(plan_lines)

    if expected_node not in plan_text:
        raise AssertionError(f"Expected plan node '{expected_node}' not found in plan:\n{plan_text}")

    if forbidden_nodes:
        for f_node in forbidden_nodes:
            if f_node in plan_text:
                raise AssertionError(f"Forbidden plan node '{f_node}' detected in plan:\n{plan_text}")

    return plan_text

def execute_and_compare(cur, query_sql, params=None):
    """
    Executes query under forced Index Scan / Bitmap Scan (enable_seqscan = off)
    and under forced Seq Scan (enable_indexscan = off, enable_bitmapscan = off, enable_seqscan = on).
    Asserts both return identical rows.
    """
    # 1. Force Index / Bitmap Scan
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute(query_sql, params)
    index_rows = cur.fetchall()

    # 2. Force Ground Truth Sequential Scan
    cur.execute("SET enable_seqscan = on;")
    cur.execute("SET enable_indexscan = off;")
    cur.execute("SET enable_bitmapscan = off;")
    cur.execute(query_sql, params)
    seq_rows = cur.fetchall()

    # Reset
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")

    if sorted(index_rows) != sorted(seq_rows):
        raise AssertionError(
            f"Result mismatch!\nIndex Scan rows count: {len(index_rows)}\n"
            f"Seq Scan rows count: {len(seq_rows)}\n"
            f"Sample Index: {index_rows[:3]}\nSample Seq: {seq_rows[:3]}"
        )

    return index_rows

# -----------------------------------------------------------------------------
# TC-STR-01: Hash Index High-Scale (20,000 Rows) Stress & Plan Verification
# -----------------------------------------------------------------------------
def test_case_1_hash_heavy_stress():
    tc_id = "TC-STR-01"
    name = "Hash Index 20,000 Rows Stress & Execution Plan Assertion"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_hash CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_hash (
            id INT,
            code TEXT,
            payload TEXT
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sh_code ON t_str_hash USING hash(code);")

    # Bulk insert 20,000 rows
    start_time = time.time()
    cur.execute("""
        INSERT INTO t_str_hash
        SELECT g, 'SN_' || lpad(g::text, 8, '0'), 'PAYLOAD_' || (g * 7)
        FROM generate_series(1, 20000) g;
    """)
    insert_duration = time.time() - start_time

    # 1. Plan Verification for Point Query under Index Scan
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_bitmapscan = off;")
    cur.execute("SET enable_indexscan = on;")
    plan_idx = assert_plan_node(
        cur,
        "SELECT id, code, payload FROM t_str_hash WHERE code = %s;",
        ('SN_00012345',),
        expected_node="Index Scan using idx_sh_code",
        forbidden_nodes=["Seq Scan"]
    )

    # 2. Plan Verification for Point Query under Bitmap Index Scan
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute("SET enable_indexscan = off;")
    plan_bmp = assert_plan_node(
        cur,
        "SELECT id, code, payload FROM t_str_hash WHERE code = %s;",
        ('SN_00012345',),
        expected_node="Bitmap Index Scan on idx_sh_code",
        forbidden_nodes=["Seq Scan"]
    )

    # 3. Ground Truth Verification across 200 randomized queries
    random_samples = [random.randint(1, 20000) for _ in range(200)]
    verified_count = 0
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute("SET enable_indexscan = on;")
    for sample_id in random_samples:
        sn = f"SN_{sample_id:08d}"
        rows = execute_and_compare(
            cur,
            "SELECT id, code, payload FROM t_str_hash WHERE code = %s;",
            (sn,)
        )
        if len(rows) == 1 and rows[0] == (sample_id, sn, f"PAYLOAD_{sample_id * 7}"):
            verified_count += 1
        else:
            raise AssertionError(f"Invalid row fetched for {sn}: {rows}")

    cur.execute("DROP TABLE t_str_hash CASCADE;")
    conn.close()

    success = (verified_count == 200)
    details = (f"Table Rows: 20,000 (Inserted in {insert_duration:.2f}s), "
               f"IndexScan Plan: Verified, BitmapScan Plan: Verified, "
               f"Random Keys Verified: 200/200 100% matched with Ground Truth")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-02: GiST Spatial Heavy Stress (10,000 Points) with Bounding Box Queries
# -----------------------------------------------------------------------------
def test_case_2_gist_spatial_stress():
    tc_id = "TC-STR-02"
    name = "GiST Spatial 10,000 Points Stress & Execution Plan Assertion"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_gist CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_gist (
            id INT,
            loc POINT,
            label TEXT
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sg_loc ON t_str_gist USING gist(loc);")

    # Bulk insert 10,000 spatial points distributed across 0..100 grid
    start_time = time.time()
    cur.execute("""
        INSERT INTO t_str_gist
        SELECT g, point((g % 100)::numeric, ((g / 100) % 100)::numeric), 'LOC_' || g
        FROM generate_series(1, 10000) g;
    """)
    insert_duration = time.time() - start_time

    # 1. Plan Verification under Index Scan
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_bitmapscan = off;")
    cur.execute("SET enable_indexscan = on;")
    plan_idx = assert_plan_node(
        cur,
        "SELECT id, label FROM t_str_gist WHERE loc <@ '(60,60),(40,40)'::box;",
        None,
        expected_node="Index Scan using idx_sg_loc",
        forbidden_nodes=["Seq Scan"]
    )

    # 2. Plan Verification under Bitmap Index Scan
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute("SET enable_indexscan = off;")
    plan_bmp = assert_plan_node(
        cur,
        "SELECT id, label FROM t_str_gist WHERE loc <@ '(60,60),(40,40)'::box;",
        None,
        expected_node="Bitmap Index Scan on idx_sg_loc",
        forbidden_nodes=["Seq Scan"]
    )

    # 3. Ground Truth Verification across 20 different bounding box queries
    boxes = [
        ("'(10,10),(5,5)'::box", "Small Box A"),
        ("'(30,30),(20,20)'::box", "Medium Box B"),
        ("'(55,55),(45,45)'::box", "Center Box C"),
        ("'(85,85),(70,70)'::box", "Large Box D"),
        ("'(99,99),(95,95)'::box", "Corner Box E"),
        ("'(50,50),(50,50)'::box", "Single Point Box F"),
        ("'(200,200),(150,150)'::box", "Out of Bounds Box G")
    ]
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute("SET enable_indexscan = on;")
    box_test_count = 0
    total_matched_rows = 0
    for box_str, desc in boxes:
        rows = execute_and_compare(
            cur,
            f"SELECT id, label FROM t_str_gist WHERE loc <@ {box_str};",
            None
        )
        box_test_count += 1
        total_matched_rows += len(rows)

    cur.execute("DROP TABLE t_str_gist CASCADE;")
    conn.close()

    success = (box_test_count == len(boxes))
    details = (f"Points: 10,000 (Inserted in {insert_duration:.2f}s), "
               f"IndexScan Plan: Verified, BitmapScan Plan: Verified, "
               f"Box Queries Tested: {box_test_count}, Total Matched Rows: {total_matched_rows}, "
               f"100% matched with Seq Scan Ground Truth")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-03: GIN Array Heavy Stress (10,000 Rows) Containment & Overlap
# -----------------------------------------------------------------------------
def test_case_3_gin_array_stress():
    tc_id = "TC-STR-03"
    name = "GIN Array 10,000 Rows Stress & Execution Plan Assertion"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_gin_arr CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_gin_arr (
            id INT,
            categories INT[],
            title TEXT
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sga_cat ON t_str_gin_arr USING gin(categories);")

    # Bulk insert 10,000 rows with varying category vectors
    start_time = time.time()
    cur.execute("""
        INSERT INTO t_str_gin_arr
        SELECT g, 
               ARRAY[g % 20, 100 + (g % 50), 1000 + (g % 100), 5000 + (g % 10)],
               'ITEM_' || g
        FROM generate_series(1, 10000) g;
    """)
    insert_duration = time.time() - start_time

    # 1. Plan Verification for Array Containment (@>)
    cur.execute("SET enable_seqscan = off;")
    plan_cont = assert_plan_node(
        cur,
        "SELECT id, title FROM t_str_gin_arr WHERE categories @> ARRAY[15, 125];",
        None,
        expected_node="Bitmap Index Scan on idx_sga_cat",
        forbidden_nodes=["Seq Scan"]
    )

    # 2. Plan Verification for Array Overlap (&&)
    plan_over = assert_plan_node(
        cur,
        "SELECT id, title FROM t_str_gin_arr WHERE categories && ARRAY[5001, 5003];",
        None,
        expected_node="Bitmap Index Scan on idx_sga_cat",
        forbidden_nodes=["Seq Scan"]
    )

    # 3. Ground Truth Verification across multiple queries
    test_queries = [
        "SELECT id, title FROM t_str_gin_arr WHERE categories @> ARRAY[7];",
        "SELECT id, title FROM t_str_gin_arr WHERE categories @> ARRAY[14, 114];",
        "SELECT id, title FROM t_str_gin_arr WHERE categories @> ARRAY[1050];",
        "SELECT id, title FROM t_str_gin_arr WHERE categories && ARRAY[5002, 5008];",
        "SELECT id, title FROM t_str_gin_arr WHERE categories @> ARRAY[9999];"  # Non-existent
    ]
    cur.execute("SET enable_seqscan = off;")
    total_matched = 0
    for q in test_queries:
        rows = execute_and_compare(cur, q, None)
        total_matched += len(rows)

    cur.execute("DROP TABLE t_str_gin_arr CASCADE;")
    conn.close()

    success = True
    details = (f"Array Rows: 10,000 (Inserted in {insert_duration:.2f}s), "
               f"Containment Plan: Verified, Overlap Plan: Verified, "
               f"5 Complex Queries Matched {total_matched} rows 100% against Seq Scan")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-04: GIN Full-Text Search (tsvector, 5,000 Docs) Complex Logic
# -----------------------------------------------------------------------------
def test_case_4_gin_fts_stress():
    tc_id = "TC-STR-04"
    name = "GIN Full-Text Search (5,000 Docs) Stress & Plan Assertion"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_fts CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_fts (
            id INT,
            title TEXT,
            tsv TSVECTOR
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sfts_tsv ON t_str_fts USING gin(tsv);")

    # Insert 5,000 documents with realistic keyword distributions
    start_time = time.time()
    cur.execute("""
        INSERT INTO t_str_fts
        SELECT g, 
               'Document title ' || g,
               to_tsvector('english', 
                   CASE (g % 5)
                       WHEN 0 THEN 'opengauss kernel database storage engine btree ustore'
                       WHEN 1 THEN 'distributed cloud database router transaction recovery'
                       WHEN 2 THEN 'openGauss memory buffer cache hash index router'
                       WHEN 3 THEN 'spatial gist gin inverted index fulltext search'
                       ELSE 'high availability replication backup wal physical router'
                   END || ' document_id_' || g
               )
        FROM generate_series(1, 5000) g;
    """)
    insert_duration = time.time() - start_time

    # 1. Plan Verification for FTS
    cur.execute("SET enable_seqscan = off;")
    plan_fts = assert_plan_node(
        cur,
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'opengauss & kernel');",
        None,
        expected_node="Bitmap Index Scan on idx_sfts_tsv",
        forbidden_nodes=["Seq Scan"]
    )

    # 2. Ground Truth Comparison on complex boolean tsqueries
    queries = [
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'opengauss & kernel');",
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'router & (hash | memory)');",
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'spatial | fulltext');",
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'replication & recovery');",
        "SELECT id, title FROM t_str_fts WHERE tsv @@ to_tsquery('english', 'document_id_2468');"
    ]

    total_docs = 0
    for q in queries:
        rows = execute_and_compare(cur, q, None)
        total_docs += len(rows)

    cur.execute("DROP TABLE t_str_fts CASCADE;")
    conn.close()

    success = (total_docs > 0)
    details = (f"Documents: 5,000 (Inserted in {insert_duration:.2f}s), "
               f"FTS BitmapScan Plan: Verified, "
               f"Complex Tsqueries Tested: 5, Total Matched: {total_docs}, "
               f"100% matched with Ground Truth")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-05: Intensive In-Place Updates vs Key Updates Churn (5,000 DMLs)
# -----------------------------------------------------------------------------
def test_case_5_intensive_updates_churn():
    tc_id = "TC-STR-05"
    name = "Intensive In-Place & Key Updates (5,000 DMLs) & Plan Assertion"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_upd CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_upd (
            id INT,
            code TEXT,
            payload TEXT
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_supd_code ON t_str_upd USING hash(code);")

    # Pre-populate 2,000 rows
    cur.execute("""
        INSERT INTO t_str_upd
        SELECT g, 'KEY_' || g, 'ORIG_PAYLOAD_' || g
        FROM generate_series(1, 2000) g;
    """)

    # 1. Perform 1,500 in-place updates on payload (non-indexed column)
    start_time = time.time()
    cur.execute("""
        UPDATE t_str_upd
        SET payload = payload || '_MODIFIED'
        WHERE id <= 1500;
    """)

    # 2. Perform 1,000 key updates on code (indexed column)
    cur.execute("""
        UPDATE t_str_upd
        SET code = 'NEW_KEY_' || id
        WHERE id > 1000;
    """)
    upd_duration = time.time() - start_time

    # 3. Plan verification on updated rows
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    plan_upd = assert_plan_node(
        cur,
        "SELECT id, code, payload FROM t_str_upd WHERE code = %s;",
        ('KEY_500',),
        expected_node="idx_supd_code",
        forbidden_nodes=["Seq Scan"]
    )

    # 4. Verify Ground Truth across all partitions:
    # Part A: Rows 1..1000 still have 'KEY_x' and modified payload
    cur.execute("SELECT count(*) FROM t_str_upd WHERE code = 'KEY_500' AND payload = 'ORIG_PAYLOAD_500_MODIFIED';")
    cnt_a = cur.fetchone()[0]

    # Part B: Rows 1001..2000 old keys MUST be unreachable
    cur.execute("SELECT count(*) FROM t_str_upd WHERE code = 'KEY_1500';")
    cnt_b = cur.fetchone()[0]

    # Part C: Rows 1001..2000 new keys MUST be reachable
    cur.execute("SELECT count(*) FROM t_str_upd WHERE code = 'NEW_KEY_1500';")
    cnt_c = cur.fetchone()[0]

    # Full ground truth comparison
    cur.execute("SELECT count(*) FROM t_str_upd;")
    total_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_str_upd CASCADE;")
    conn.close()

    success = (cnt_a == 1 and cnt_b == 0 and cnt_c == 1 and total_count == 2000)
    details = (f"Initial Rows: 2,000, In-Place Updates: 1,500, Key Updates: 1,000 "
               f"(Completed in {upd_duration:.2f}s), Plan Verified: Hash IndexScan, "
               f"In-Place Row: Intact, Old Key: Purged (0), New Key: Hit (1), Total Rows: {total_count}")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-06: Brutal Rollback, DELETE, VACUUM Slot Reuse & Anti-Phantom Validation
# -----------------------------------------------------------------------------
def test_case_6_brutal_rollback_and_slot_reuse():
    tc_id = "TC-STR-06"
    name = "Brutal Rollback, DELETE, VACUUM Slot Reuse & Anti-Phantom Validation"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_churn CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_churn (
            id INT,
            token TEXT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sch_token ON t_str_churn USING hash(token);")
    cur.execute("CREATE INDEX idx_sch_tags ON t_str_churn USING gin(tags);")

    # Step 1: Pre-populate 1,000 committed baseline rows (Namespace: 100000, 200000+g)
    cur.execute("""
        INSERT INTO t_str_churn
        SELECT g, 'BASE_' || g, ARRAY[100000, 200000 + g]
        FROM generate_series(1, 1000) g;
    """)

    # Step 2: 500 rows inserted in transaction and ROLLED BACK (Namespace: 999999, 400000+i)
    r_conn = get_connection()
    r_conn.autocommit = False
    r_cur = r_conn.cursor()
    for i in range(1, 501):
        r_cur.execute(
            "INSERT INTO t_str_churn VALUES (%s, %s, %s);",
            (2000 + i, f"ROLLBACK_GHOST_{i}", [999999, 400000 + i])
        )
    r_conn.rollback()
    r_conn.close()

    # Step 3: Delete 500 baseline rows and run VACUUM
    cur.execute("DELETE FROM t_str_churn WHERE id <= 500;")
    cur.execute("VACUUM t_str_churn;")

    # Step 4: Insert 500 new rows reusing slots (Namespace: 888888, 500000+g)
    cur.execute("""
        INSERT INTO t_str_churn
        SELECT 5000 + g, 'REUSED_' || g, ARRAY[888888, 500000 + g]
        FROM generate_series(1, 500) g;
    """)

    # Step 5: Plan Verification
    cur.execute("SET enable_seqscan = off;")
    plan_hash = assert_plan_node(
        cur,
        "SELECT id, token FROM t_str_churn WHERE token = %s;",
        ('REUSED_100',),
        expected_node="idx_sch_token",
        forbidden_nodes=["Seq Scan"]
    )
    plan_gin = assert_plan_node(
        cur,
        "SELECT count(*) FROM t_str_churn WHERE tags @> ARRAY[888888];",
        None,
        expected_node="Bitmap Index Scan on idx_sch_tags",
        forbidden_nodes=["Seq Scan"]
    )

    # Step 6: Rigorous Anti-Phantom & Accuracy Checks
    # A: Rolled back rows MUST NEVER be visible via Hash or GIN
    cur.execute("SELECT count(*) FROM t_str_churn WHERE token LIKE 'ROLLBACK_GHOST_%';")
    ghost_rb_hash = cur.fetchone()[0]
    cur.execute("SELECT count(*) FROM t_str_churn WHERE tags @> ARRAY[999999];")
    ghost_rb_gin = cur.fetchone()[0]

    # B: Deleted rows (whose slots may have been reused) MUST NEVER be visible
    cur.execute("SELECT count(*) FROM t_str_churn WHERE token = 'BASE_250';")
    ghost_del_hash = cur.fetchone()[0]

    # C: Reused rows MUST be 100% visible
    cur.execute("SELECT count(*) FROM t_str_churn WHERE tags @> ARRAY[888888];")
    reused_gin_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_str_churn CASCADE;")
    conn.close()

    success = (ghost_rb_hash == 0 and ghost_rb_gin == 0 and ghost_del_hash == 0 and reused_gin_count == 500)
    details = (f"Rolled Back Ghost: {ghost_rb_hash} (Hash) / {ghost_rb_gin} (GIN), "
               f"Deleted Slot Ghost: {ghost_del_hash}, Reused Slot Rows: {reused_gin_count}/500, "
               f"Plans Verified: Hash & GIN, Tag Anti-Phantom: 100% Effective")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# TC-STR-07: Concurrent 4-Index (UBTree + Hash + GiST + GIN) Multi-Threaded Stress
# -----------------------------------------------------------------------------
def test_case_7_concurrent_four_index_stress():
    tc_id = "TC-STR-07"
    name = "Concurrent 4-Index (UBTree + Hash + GiST + GIN) Multi-Threaded Stress"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_str_all4 CASCADE;")
    cur.execute("""
        CREATE TABLE t_str_all4 (
            id INT,
            token TEXT,
            loc POINT,
            categories INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_sall_ubtree ON t_str_all4 USING ubtree(id);")
    cur.execute("CREATE INDEX idx_sall_hash ON t_str_all4 USING hash(token);")
    cur.execute("CREATE INDEX idx_sall_gist ON t_str_all4 USING gist(loc);")
    cur.execute("CREATE INDEX idx_sall_gin ON t_str_all4 USING gin(categories);")

    # Pre-seed 3,000 rows: loc is point(g % 100, g % 50)
    start_time = time.time()
    cur.execute("""
        INSERT INTO t_str_all4
        SELECT g, 
               'TOKEN_' || g, 
               point((g % 100)::numeric, (g % 50)::numeric), 
               ARRAY[g % 10, 1000 + (g % 100)]
        FROM generate_series(1, 3000) g;
    """)
    seed_duration = time.time() - start_time

    num_threads = 12
    queries_per_thread = 100
    worker_errors = []

    def multi_worker(tid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        w_cur.execute("SET enable_seqscan = off;")
        w_cur.execute("SET enable_indexscan = on;")
        w_cur.execute("SET enable_bitmapscan = on;")
        try:
            for q in range(queries_per_thread):
                target_id = random.randint(1, 2900)
                idx_choice = random.randint(1, 4)
                if idx_choice == 1:
                    # UBTree Range Scan
                    w_cur.execute("SELECT count(*) FROM t_str_all4 WHERE id BETWEEN %s AND %s;",
                                  (target_id, target_id + 5))
                    cnt = w_cur.fetchone()[0]
                    if cnt != 6:
                        worker_errors.append(f"T{tid} UBTree expected 6 got {cnt}")
                elif idx_choice == 2:
                    # Hash Point Query
                    w_cur.execute("SELECT id, token FROM t_str_all4 WHERE token = %s;",
                                  (f"TOKEN_{target_id}",))
                    row = w_cur.fetchone()
                    if row != (target_id, f"TOKEN_{target_id}"):
                        worker_errors.append(f"T{tid} Hash mismatch: {row}")
                elif idx_choice == 3:
                    # GiST Point/Box Query around (target_id % 100, target_id % 50)
                    x = float(target_id % 100)
                    y = float(target_id % 50)
                    box_str = f"({x + 0.1},{y + 0.1}),({x - 0.1},{y - 0.1})"
                    w_cur.execute(f"SELECT count(*) FROM t_str_all4 WHERE loc <@ '{box_str}'::box;")
                    cnt = w_cur.fetchone()[0]
                    if cnt < 1:
                        worker_errors.append(f"T{tid} GiST expected >= 1 got {cnt}")
                elif idx_choice == 4:
                    # GIN Array Containment Query
                    cat_val = 1000 + (target_id % 100)
                    w_cur.execute("SELECT count(*) FROM t_str_all4 WHERE categories @> ARRAY[%s];", (cat_val,))
                    cnt = w_cur.fetchone()[0]
                    if cnt < 1:
                        worker_errors.append(f"T{tid} GIN expected >= 1 got {cnt}")
        except Exception as e:
            worker_errors.append(f"T{tid} Exception: {e}")
        finally:
            w_conn.close()

    start_exec = time.time()
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(multi_worker, t) for t in range(num_threads)]
        for f in futures:
            f.result()
    exec_duration = time.time() - start_exec

    # Plan assertions on all 4 index access methods
    cur.execute("SET enable_seqscan = off;")
    p_ubtree = assert_plan_node(cur, "SELECT * FROM t_str_all4 WHERE id = 100;", None, "idx_sall_ubtree")
    p_hash = assert_plan_node(cur, "SELECT * FROM t_str_all4 WHERE token = 'TOKEN_100';", None, "idx_sall_hash")
    p_gist = assert_plan_node(cur, "SELECT * FROM t_str_all4 WHERE loc <@ '(10,10),(0,0)'::box;", None, "idx_sall_gist")
    p_gin = assert_plan_node(cur, "SELECT * FROM t_str_all4 WHERE categories @> ARRAY[1050];", None, "idx_sall_gin")

    cur.execute("DROP TABLE t_str_all4 CASCADE;")
    conn.close()

    success = (len(worker_errors) == 0)
    details = (f"Pre-seeded: 3,000 Rows, Concurrent Threads: {num_threads}, "
               f"Total Queries: {num_threads * queries_per_thread} (Completed in {exec_duration:.2f}s), "
               f"Errors: {len(worker_errors)}, Plans Verified on All 4 AMs: UBTree, Hash, GiST, GIN")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Main Test Harness
# -----------------------------------------------------------------------------
def main():
    print("=" * 80)
    print(">>> openGauss Ustore Bridge Index Phase 5: Heavy Stress & Plan Verification")
    print("=" * 80)
    start_total = time.time()

    suite = [
        test_case_1_hash_heavy_stress,
        test_case_2_gist_spatial_stress,
        test_case_3_gin_array_stress,
        test_case_4_gin_fts_stress,
        test_case_5_intensive_updates_churn,
        test_case_6_brutal_rollback_and_slot_reuse,
        test_case_7_concurrent_four_index_stress
    ]

    all_passed = True
    for test_fn in suite:
        passed = test_fn()
        if not passed:
            all_passed = False

    total_time = time.time() - start_total
    print("\n" + "=" * 80)
    if all_passed:
        print(">>> [ALL PASSED] All 7 Heavy Stress & Plan Verification Scenarios Completed Successfully!")
    else:
        print(">>> [SOME FAILED] Heavy Stress Test Suite Encountered Failures!")
    print(f">>> Total Execution Time: {total_time:.2f} seconds")
    print("=" * 80)
    sys.exit(0 if all_passed else 1)

if __name__ == '__main__':
    main()
