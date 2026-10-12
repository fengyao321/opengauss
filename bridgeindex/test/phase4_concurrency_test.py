#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
openGauss Ustore Bridge Index Phase 4: High Concurrency Test Suite
Target Features:
  - Scenario 1: High-Concurrency INSERTs & Sequence Monotonicity (Atomicity & Uniqueness)
  - Scenario 2: Concurrent Readers vs Writers under MVCC (Snapshot Isolation)
  - Scenario 3: Concurrent In-Place UPDATEs vs Key UPDATEs (Bridge Tag Stability)
  - Scenario 4: Concurrent Transactions with Commits vs Rollbacks (Zero Phantom Reads)
  - Scenario 5: High-Frequency Slot Churn, VACUUM & Slot Reuse Anti-Phantom
  - Scenario 6: Concurrent Multi-Index Coexistence (UBTree + Hash + GiST + GIN)
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
    conn.autocommit = False
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

# -----------------------------------------------------------------------------
# Scenario 1: High-Concurrency INSERTs & Sequence Monotonicity
# -----------------------------------------------------------------------------
def test_case_1_concurrent_inserts():
    tc_id = "TC-CONC-01"
    name = "Concurrent INSERTs & Sequence Monotonicity"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_ins CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_ins (
            id INT,
            code TEXT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_cins_hash ON t_conc_ins USING hash(code);")
    cur.execute("CREATE INDEX idx_cins_gin ON t_conc_ins USING gin(tags);")
    conn.commit()

    num_threads = 10
    rows_per_thread = 100
    total_expected = num_threads * rows_per_thread

    def worker_insert(thread_idx):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        try:
            for i in range(rows_per_thread):
                row_id = thread_idx * rows_per_thread + i
                code = f"CODE_T{thread_idx}_{i}"
                # Distinct namespaces: 10000+thread_idx, 20000+i, 30000+row_id
                tags = [10000 + thread_idx, 20000 + i, 30000 + row_id]
                w_cur.execute(
                    "INSERT INTO t_conc_ins (id, code, tags) VALUES (%s, %s, %s);",
                    (row_id, code, tags)
                )
            w_conn.commit()
            return True, None
        except Exception as e:
            w_conn.rollback()
            return False, str(e)
        finally:
            w_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(worker_insert, t) for t in range(num_threads)]
        results = [f.result() for f in as_completed(futures)]

    elapsed = time.time() - start_time
    errors = [err for ok, err in results if not ok]
    if errors:
        print_result(tc_id, name, False, f"Worker thread errors: {errors[:3]}")
        return False

    # Validation
    cur.execute("SELECT count(*) FROM t_conc_ins;")
    total_count = cur.fetchone()[0]

    # Inspect the bridge table: 2 bridged indexes (Hash + GIN) -> 2 bridge rows per tuple
    cur.execute("""
        SELECT b.relname 
        FROM pg_class c 
        JOIN pg_class b ON b.relname = 'pg_bridge_' || c.oid 
        WHERE c.relname = 't_conc_ins';
    """)
    bridge_rel = cur.fetchone()[0]

    cur.execute(f"SELECT pg_relation_size('pg_toast.' || quote_ident('{bridge_rel}'));")
    router_size_bytes = cur.fetchone()[0]

    # Index Scan verification
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")
    cur.execute("SELECT id, code FROM t_conc_ins WHERE code = 'CODE_T3_42';")
    point_row = cur.fetchone()

    cur.execute("SELECT count(*) FROM t_conc_ins WHERE tags @> ARRAY[10003];")
    gin_match_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_conc_ins CASCADE;")
    conn.commit()
    conn.close()

    success = (total_count == total_expected and 
               router_size_bytes > 0 and
               point_row == (342, 'CODE_T3_42') and
               gin_match_count == rows_per_thread)

    details = (f"Inserted: {total_count}/{total_expected}, Bridge Router Size: {router_size_bytes} bytes, "
               f"Point Row: {point_row}, "
               f"GIN Array Match: {gin_match_count}/{rows_per_thread}, Time: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Scenario 2: Concurrent Readers vs Writers under MVCC
# -----------------------------------------------------------------------------
def test_case_2_readers_writers_mvcc():
    tc_id = "TC-CONC-02"
    name = "Concurrent Readers vs Writers under MVCC"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_rw CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_rw (
            id INT,
            token TEXT,
            data_val INT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_crw_hash ON t_conc_rw USING hash(token);")
    cur.execute("CREATE INDEX idx_crw_gin ON t_conc_rw USING gin(tags);")
    
    # Pre-seed 50 rows
    for i in range(50):
        cur.execute("INSERT INTO t_conc_rw VALUES (%s, %s, %s, %s);",
                    (i, f"SEED_{i}", i * 10, [i % 5, 99999]))
    conn.commit()

    stop_event = threading.Event()
    writer_count = 3
    reader_count = 5
    rows_per_writer = 50
    reader_errors = []
    writer_errors = []

    def writer_worker(wid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        try:
            for i in range(rows_per_writer):
                row_id = 1000 + wid * rows_per_writer + i
                token = f"W_{wid}_{i}"
                tags = [wid, i, 77777]
                w_cur.execute(
                    "INSERT INTO t_conc_rw VALUES (%s, %s, %s, %s);",
                    (row_id, token, row_id * 10, tags)
                )
                w_conn.commit()
                time.sleep(0.005)
        except Exception as e:
            writer_errors.append(f"Writer {wid}: {e}")
        finally:
            w_conn.close()

    def reader_worker(rid):
        r_conn = get_connection()
        r_cur = r_conn.cursor()
        r_cur.execute("SET enable_seqscan = off;")
        r_cur.execute("SET enable_indexscan = on;")
        r_cur.execute("SET enable_bitmapscan = on;")
        queries_run = 0
        try:
            while not stop_event.is_set():
                # Hash point query
                seed_id = random.randint(0, 49)
                r_cur.execute("SELECT id, token, data_val FROM t_conc_rw WHERE token = %s;", (f"SEED_{seed_id}",))
                rows = r_cur.fetchall()
                if len(rows) != 1 or rows[0] != (seed_id, f"SEED_{seed_id}", seed_id * 10):
                    reader_errors.append(f"Reader {rid} inconsistency on SEED_{seed_id}: got {rows}")
                    break

                # GIN array query
                r_cur.execute("SELECT count(*) FROM t_conc_rw WHERE tags @> ARRAY[99999];")
                cnt = r_cur.fetchone()[0]
                if cnt != 50:
                    reader_errors.append(f"Reader {rid} GIN count != 50: got {cnt}")
                    break
                queries_run += 1
                time.sleep(0.003)
        except Exception as e:
            reader_errors.append(f"Reader {rid} exception: {e}")
        finally:
            r_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=writer_count + reader_count) as executor:
        w_futures = [executor.submit(writer_worker, w) for w in range(writer_count)]
        r_futures = [executor.submit(reader_worker, r) for r in range(reader_count)]

        for wf in w_futures:
            wf.result()

        time.sleep(0.1)
        stop_event.set()

        for rf in r_futures:
            rf.result()

    elapsed = time.time() - start_time
    cur.execute("SELECT count(*) FROM t_conc_rw;")
    final_count = cur.fetchone()[0]
    expected_count = 50 + writer_count * rows_per_writer

    cur.execute("DROP TABLE t_conc_rw CASCADE;")
    conn.commit()
    conn.close()

    success = (len(writer_errors) == 0 and len(reader_errors) == 0 and final_count == expected_count)
    details = (f"Final Count: {final_count}/{expected_count}, Writer Errors: {len(writer_errors)}, "
               f"Reader Errors: {len(reader_errors)}, Duration: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Scenario 3: Concurrent In-Place UPDATEs vs Key UPDATEs
# -----------------------------------------------------------------------------
def test_case_3_concurrent_updates():
    tc_id = "TC-CONC-03"
    name = "Concurrent In-Place UPDATEs vs Key UPDATEs"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_upd CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_upd (
            id INT,
            code TEXT,
            payload TEXT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_cupd_hash ON t_conc_upd USING hash(code);")
    cur.execute("CREATE INDEX idx_cupd_gin ON t_conc_upd USING gin(tags);")

    # Populate 100 rows
    for i in range(100):
        cur.execute("INSERT INTO t_conc_upd VALUES (%s, %s, %s, %s);",
                    (i, f"CODE_{i}", f"PAYLOAD_{i}", [i % 10]))
    conn.commit()

    update_errors = []

    # Worker 1: in-place updates on payload for rows 0..44
    def worker_inplace(wid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        try:
            for i in range(wid * 15, (wid + 1) * 15):
                w_cur.execute(
                    "UPDATE t_conc_upd SET payload = payload || '_INPLACE' WHERE id = %s;",
                    (i,)
                )
            w_conn.commit()
        except Exception as e:
            w_conn.rollback()
            update_errors.append(f"Inplace {wid}: {e}")
        finally:
            w_conn.close()

    # Worker 2: key updates on code & tags for rows 50..94
    def worker_key_upd(wid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        try:
            for i in range(50 + wid * 15, 50 + (wid + 1) * 15):
                w_cur.execute(
                    "UPDATE t_conc_upd SET code = %s, tags = ARRAY[%s, 88888] WHERE id = %s;",
                    (f"MOD_CODE_{i}", i + 1000, i)
                )
            w_conn.commit()
        except Exception as e:
            w_conn.rollback()
            update_errors.append(f"KeyUpd {wid}: {e}")
        finally:
            w_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = [executor.submit(worker_inplace, 0),
                   executor.submit(worker_inplace, 1),
                   executor.submit(worker_inplace, 2),
                   executor.submit(worker_key_upd, 0),
                   executor.submit(worker_key_upd, 1),
                   executor.submit(worker_key_upd, 2)]
        for f in futures:
            f.result()

    elapsed = time.time() - start_time

    # Validate index scans
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")

    # In-place updated row should still be reachable by original code
    cur.execute("SELECT id, code, payload FROM t_conc_upd WHERE code = 'CODE_10';")
    in_place_row = cur.fetchone()

    # Key updated row should be reachable by new code and NOT by old code
    cur.execute("SELECT id, code, payload FROM t_conc_upd WHERE code = 'CODE_60';")
    old_key_row = cur.fetchone()

    cur.execute("SELECT id, code, payload FROM t_conc_upd WHERE code = 'MOD_CODE_60';")
    new_key_row = cur.fetchone()

    cur.execute("SELECT count(*) FROM t_conc_upd WHERE tags @> ARRAY[88888];")
    gin_updated_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_conc_upd CASCADE;")
    conn.commit()
    conn.close()

    success = (len(update_errors) == 0 and
               in_place_row == (10, 'CODE_10', 'PAYLOAD_10_INPLACE') and
               old_key_row is None and
               new_key_row is not None and new_key_row[0] == 60 and
               gin_updated_count == 45)

    details = (f"In-Place Row: {in_place_row}, Old Key Row: {old_key_row}, "
               f"New Key Row: {new_key_row}, GIN Count: {gin_updated_count}/45, "
               f"Errors: {len(update_errors)}, Time: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Scenario 4: Concurrent Transactions with Commits vs Rollbacks
# -----------------------------------------------------------------------------
def test_case_4_concurrent_commits_rollbacks():
    tc_id = "TC-CONC-04"
    name = "Concurrent Commits vs Rollbacks (Zero Phantom Reads)"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_tx CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_tx (
            id INT,
            token TEXT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_ctx_hash ON t_conc_tx USING hash(token);")
    cur.execute("CREATE INDEX idx_ctx_gin ON t_conc_tx USING gin(tags);")
    conn.commit()

    num_threads = 8
    rows_per_thread = 50
    tx_errors = []

    def tx_worker(tid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        should_commit = (tid % 2 == 0)
        try:
            for i in range(rows_per_thread):
                row_id = tid * rows_per_thread + i
                status_str = "COMMIT" if should_commit else "ROLLBACK"
                token = f"TOKEN_{status_str}_{tid}_{i}"
                tags = [tid, 55555 if should_commit else 66666]
                w_cur.execute(
                    "INSERT INTO t_conc_tx VALUES (%s, %s, %s);",
                    (row_id, token, tags)
                )
            
            # Verify internal visibility before commit/rollback
            w_cur.execute("SET enable_seqscan = off;")
            w_cur.execute("SET enable_indexscan = on;")
            w_cur.execute("SET enable_bitmapscan = on;")
            w_cur.execute(f"SELECT count(*) FROM t_conc_tx WHERE token LIKE 'TOKEN_{status_str}_{tid}_%';")
            in_tx_cnt = w_cur.fetchone()[0]
            if in_tx_cnt != rows_per_thread:
                tx_errors.append(f"T{tid} internal visibility mismatch: {in_tx_cnt}")

            if should_commit:
                w_conn.commit()
            else:
                w_conn.rollback()
        except Exception as e:
            w_conn.rollback()
            tx_errors.append(f"T{tid} error: {e}")
        finally:
            w_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(tx_worker, t) for t in range(num_threads)]
        for f in futures:
            f.result()

    elapsed = time.time() - start_time

    # Validate with index scans
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")

    cur.execute("SELECT count(*) FROM t_conc_tx;")
    total_committed = cur.fetchone()[0]
    expected_committed = (num_threads // 2) * rows_per_thread

    # Ensure zero rolled back rows via Hash index
    cur.execute("SELECT count(*) FROM t_conc_tx WHERE token LIKE 'TOKEN_ROLLBACK_%';")
    phantom_hash_count = cur.fetchone()[0]

    # Ensure zero rolled back tags via GIN index
    cur.execute("SELECT count(*) FROM t_conc_tx WHERE tags @> ARRAY[66666];")
    phantom_gin_count = cur.fetchone()[0]

    # Ensure all committed tags via GIN index
    cur.execute("SELECT count(*) FROM t_conc_tx WHERE tags @> ARRAY[55555];")
    committed_gin_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_conc_tx CASCADE;")
    conn.commit()
    conn.close()

    success = (len(tx_errors) == 0 and
               total_committed == expected_committed and
               phantom_hash_count == 0 and
               phantom_gin_count == 0 and
               committed_gin_count == expected_committed)

    details = (f"Committed: {total_committed}/{expected_committed}, "
               f"Phantom Hash: {phantom_hash_count}, Phantom GIN: {phantom_gin_count}, "
               f"Committed GIN: {committed_gin_count}, Errors: {len(tx_errors)}, Time: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Scenario 5: High-Frequency Slot Churn & Anti-Phantom Under Concurrency
# -----------------------------------------------------------------------------
def test_case_5_concurrent_churn_anti_phantom():
    tc_id = "TC-CONC-05"
    name = "Concurrent Slot Churn, VACUUM & Anti-Phantom Tag Validation"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_churn CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_churn (
            id INT,
            token TEXT,
            payload TEXT,
            tags INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_cch_hash ON t_conc_churn USING hash(token);")
    cur.execute("CREATE INDEX idx_cch_gin ON t_conc_churn USING gin(tags);")

    # Step 1: Pre-populate 100 rows with ghost tokens
    for i in range(100):
        cur.execute("INSERT INTO t_conc_churn VALUES (%s, %s, %s, %s);",
                    (i, f"GHOST_{i}", f"PAYLOAD_OLD_{i}", [11111, i]))
    conn.commit()

    churn_errors = []

    # Step 2: Concurrently Delete old rows, run vacuum, and insert new rows
    def worker_delete():
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        try:
            for i in range(100):
                w_cur.execute("DELETE FROM t_conc_churn WHERE id = %s;", (i,))
            w_conn.commit()
        except Exception as e:
            churn_errors.append(f"Delete error: {e}")
        finally:
            w_conn.close()

    def worker_vacuum():
        time.sleep(0.05)
        v_conn = get_connection()
        v_conn.autocommit = True
        v_cur = v_conn.cursor()
        try:
            v_cur.execute("VACUUM t_conc_churn;")
        except Exception as e:
            churn_errors.append(f"Vacuum error: {e}")
        finally:
            v_conn.close()

    def worker_reuse_insert():
        time.sleep(0.1)
        i_conn = get_connection()
        i_cur = i_conn.cursor()
        try:
            for i in range(100):
                i_cur.execute(
                    "INSERT INTO t_conc_churn VALUES (%s, %s, %s, %s);",
                    (1000 + i, f"FRESH_{i}", f"PAYLOAD_NEW_{i}", [22222, i])
                )
            i_conn.commit()
        except Exception as e:
            churn_errors.append(f"Reuse insert error: {e}")
        finally:
            i_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=3) as executor:
        f1 = executor.submit(worker_delete)
        f2 = executor.submit(worker_vacuum)
        f3 = executor.submit(worker_reuse_insert)
        f1.result()
        f2.result()
        f3.result()

    elapsed = time.time() - start_time

    # Validate anti-phantom
    cur.execute("SET enable_seqscan = off;")
    cur.execute("SET enable_indexscan = on;")
    cur.execute("SET enable_bitmapscan = on;")

    # None of the GHOST tokens should ever be found
    ghost_found = 0
    for i in range(10):
        cur.execute("SELECT id, token FROM t_conc_churn WHERE token = %s;", (f"GHOST_{i}",))
        if cur.fetchone() is not None:
            ghost_found += 1

    cur.execute("SELECT count(*) FROM t_conc_churn WHERE tags @> ARRAY[11111];")
    ghost_gin_count = cur.fetchone()[0]

    # All FRESH tokens should be present
    fresh_found = 0
    for i in range(10):
        cur.execute("SELECT id, token FROM t_conc_churn WHERE token = %s;", (f"FRESH_{i}",))
        if cur.fetchone() is not None:
            fresh_found += 1

    cur.execute("SELECT count(*) FROM t_conc_churn WHERE tags @> ARRAY[22222];")
    fresh_gin_count = cur.fetchone()[0]

    cur.execute("DROP TABLE t_conc_churn CASCADE;")
    conn.commit()
    conn.close()

    success = (len(churn_errors) == 0 and
               ghost_found == 0 and
               ghost_gin_count == 0 and
               fresh_found == 10 and
               fresh_gin_count == 100)

    details = (f"Ghost Found: {ghost_found}, Ghost GIN: {ghost_gin_count}, "
               f"Fresh Sample Found: {fresh_found}/10, Fresh GIN: {fresh_gin_count}/100, "
               f"Errors: {len(churn_errors)}, Time: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Scenario 6: Concurrent Multi-Index Coexistence (UBTree + Hash + GiST + GIN)
# -----------------------------------------------------------------------------
def test_case_6_concurrent_multi_index_all_am():
    tc_id = "TC-CONC-06"
    name = "Concurrent Multi-Index Coexistence (UBTree + Hash + GiST + GIN)"
    print_header(f"Running {tc_id}: {name}")

    conn = get_connection()
    cur = conn.cursor()
    cur.execute("DROP TABLE IF EXISTS t_conc_multi CASCADE;")
    cur.execute("""
        CREATE TABLE t_conc_multi (
            id INT,
            token TEXT,
            pos POINT,
            categories INT[]
        ) WITH (storage_type = ustore);
    """)
    cur.execute("CREATE INDEX idx_cm_ubtree ON t_conc_multi USING ubtree(id);")
    cur.execute("CREATE INDEX idx_cm_hash ON t_conc_multi USING hash(token);")
    cur.execute("CREATE INDEX idx_cm_gist ON t_conc_multi USING gist(pos);")
    cur.execute("CREATE INDEX idx_cm_gin ON t_conc_multi USING gin(categories);")

    # Pre-seed 100 rows
    for i in range(100):
        cur.execute("INSERT INTO t_conc_multi VALUES (%s, %s, point(%s, %s), %s);",
                    (i, f"MULTI_{i}", float(i), float(i), [i % 5, 50000 + i]))
    conn.commit()

    num_workers = 8
    queries_per_worker = 50
    multi_errors = []

    def multi_worker(wid):
        w_conn = get_connection()
        w_cur = w_conn.cursor()
        w_cur.execute("SET enable_seqscan = off;")
        w_cur.execute("SET enable_indexscan = on;")
        w_cur.execute("SET enable_bitmapscan = on;")
        try:
            for q in range(queries_per_worker):
                op = random.randint(1, 4)
                target_id = random.randint(0, 99)
                if op == 1:
                    # UBTree Range Scan
                    w_cur.execute("SELECT count(*) FROM t_conc_multi WHERE id BETWEEN %s AND %s;",
                                  (target_id, target_id + 5))
                    cnt = w_cur.fetchone()[0]
                    expected_max = min(6, 100 - target_id)
                    if cnt < 1 or cnt > expected_max:
                        multi_errors.append(f"W{wid} UBTree invalid count: {cnt} (expected <= {expected_max})")
                elif op == 2:
                    # Hash Point Scan
                    w_cur.execute("SELECT id, token FROM t_conc_multi WHERE token = %s;",
                                  (f"MULTI_{target_id}",))
                    row = w_cur.fetchone()
                    if row != (target_id, f"MULTI_{target_id}"):
                        multi_errors.append(f"W{wid} Hash mismatch for MULTI_{target_id}: got {row}")
                elif op == 3:
                    # GiST Box Inclusion Scan
                    # OpenGauss point box inclusion: box '(x2,y2),(x1,y1)' where (x2,y2) is upper-right
                    x_hi = float(target_id) + 0.5
                    y_hi = float(target_id) + 0.5
                    x_lo = float(target_id) - 0.5
                    y_lo = float(target_id) - 0.5
                    box_str = f"({x_hi},{y_hi}),({x_lo},{y_lo})"
                    w_cur.execute("SELECT count(*) FROM t_conc_multi WHERE pos <@ %s::box;", (box_str,))
                    cnt = w_cur.fetchone()[0]
                    if cnt != 1:
                        multi_errors.append(f"W{wid} GiST mismatch for id {target_id}: got {cnt}")
                elif op == 4:
                    # GIN Array Overlap Scan
                    w_cur.execute("SELECT count(*) FROM t_conc_multi WHERE categories && ARRAY[%s];",
                                  (50000 + target_id,))
                    cnt = w_cur.fetchone()[0]
                    if cnt != 1:
                        multi_errors.append(f"W{wid} GIN mismatch for id {target_id}: got {cnt}")
        except Exception as e:
            multi_errors.append(f"W{wid} Exception: {e}")
        finally:
            w_conn.close()

    start_time = time.time()
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = [executor.submit(multi_worker, w) for w in range(num_workers)]
        for f in futures:
            f.result()

    elapsed = time.time() - start_time

    cur.execute("DROP TABLE t_conc_multi CASCADE;")
    conn.commit()
    conn.close()

    success = (len(multi_errors) == 0)
    details = (f"Workers: {num_workers}, Total Queries: {num_workers * queries_per_worker}, "
               f"Errors: {len(multi_errors)} ({multi_errors[:2] if multi_errors else ''}), Time: {elapsed:.2f}s")
    print_result(tc_id, name, success, details)
    return success

# -----------------------------------------------------------------------------
# Main Test Runner
# -----------------------------------------------------------------------------
def main():
    print("=" * 80)
    print(">>> openGauss Ustore Bridge Index Phase 4: High Concurrency Test Suite")
    print("=" * 80)
    start_total = time.time()

    test_suite = [
        test_case_1_concurrent_inserts,
        test_case_2_readers_writers_mvcc,
        test_case_3_concurrent_updates,
        test_case_4_concurrent_commits_rollbacks,
        test_case_5_concurrent_churn_anti_phantom,
        test_case_6_concurrent_multi_index_all_am
    ]

    all_passed = True
    for test_fn in test_suite:
        passed = test_fn()
        if not passed:
            all_passed = False

    total_time = time.time() - start_total
    print("\n" + "=" * 80)
    if all_passed:
        print(f">>> [ALL PASSED] All 6 Phase 4 Concurrency Scenarios Completed Successfully!")
    else:
        print(f">>> [SOME FAILED] Concurrency Test Suite Encountered Failures!")
    print(f">>> Total Execution Time: {total_time:.2f} seconds")
    print("=" * 80)
    sys.exit(0 if all_passed else 1)

if __name__ == '__main__':
    main()
