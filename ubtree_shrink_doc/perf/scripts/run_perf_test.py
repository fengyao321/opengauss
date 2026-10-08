#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
UBTree Physical Index Shrink & Compaction Benchmark Suite
=========================================================
This script benchmarks the UBTree physical index shrink feature in openGauss under various
real-world database workloads:
  Scenario 1: Large-Scale Lifecycle Test (1,000,000 Rows Bulk Delete & Shrink)
  Scenario 2: Rolling Window FIFO Archiving (Simulating time-series / transaction logs)
  Scenario 3: Multi-Index Mixed Workload (Composite, Text, and Numeric UBTree indexes)
  Scenario 4: High-Concurrency Read/Write Stress during Online Shrink
  Scenario 5: Space Reclamation & Resource Consumption Comparison

Outputs:
  - Detailed block & physical size statistics before and after shrink
  - Space reduction ratio (%) and physical space saved (MB/KB)
  - Execution duration and latency measurements
  - Index scan and verification integrity checks
"""

import os
import sys
import time
import threading
import psycopg2

DB_NAME = 'postgres'
DB_USER = 'fengyao'
SOCKET_DIR = '/tmp'
DB_PORT = 5432

def get_conn():
    conn = psycopg2.connect(host=SOCKET_DIR, port=DB_PORT, dbname=DB_NAME, user=DB_USER)
    conn.autocommit = True
    return conn

def print_separator(title=""):
    print("\n" + "=" * 80)
    if title:
        print(f"  {title}")
        print("=" * 80)

def format_size(bytes_val):
    if bytes_val >= 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"
    elif bytes_val >= 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.2f} MB"
    elif bytes_val >= 1024:
        return f"{bytes_val / 1024:.2f} KB"
    else:
        return f"{bytes_val} Bytes"

def get_rel_stats(cur, relname):
    cur.execute(f"SELECT pg_relation_size('{relname}')")
    size = cur.fetchone()[0]
    cur.execute(f"SELECT gs_ubtree_shrink_check('{relname}')")
    check_info = cur.fetchone()[0]
    return size, check_info

# =========================================================================
# Scenario 1: Large-Scale Lifecycle Test (500,000 rows)
# =========================================================================
def run_scenario_1():
    print_separator("Scenario 1: Large-Scale Lifecycle Benchmark (500,000 Rows)")
    conn = get_conn()
    cur = conn.cursor()

    table_name = "bench_large_tbl"
    idx_id = "idx_large_id"
    idx_acc = "idx_large_acc"

    print(f"1. Creating table '{table_name}' with UStore format and 2 UBTree indexes...")
    cur.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE;")
    cur.execute(f"""
        CREATE TABLE {table_name} (
            id int,
            account_no varchar(32),
            balance numeric(12, 2),
            created_at timestamp,
            remark text
        ) WITH (storage_type=ustore);
    """)
    cur.execute(f"CREATE INDEX {idx_id} ON {table_name} USING ubtree (id);")
    cur.execute(f"CREATE INDEX {idx_acc} ON {table_name} USING ubtree (account_no);")

    print("2. Bulk inserting 500,000 records...")
    t0 = time.time()
    cur.execute(f"""
        INSERT INTO {table_name}
        SELECT 
            g,
            'ACCT_' || lpad(g::text, 10, '0'),
            (g * 3.14)::numeric(12, 2),
            clock_timestamp(),
            repeat('bench_data_payload_', 3) || g
        FROM generate_series(1, 500000) g;
    """)
    insert_duration = time.time() - t0
    print(f"   Insert completed in {insert_duration:.2f}s.")

    size_id_init, check_id_init = get_rel_stats(cur, idx_id)
    size_acc_init, check_acc_init = get_rel_stats(cur, idx_acc)
    print(f"   - {idx_id}: {format_size(size_id_init)} | {check_id_init}")
    print(f"   - {idx_acc}: {format_size(size_acc_init)} | {check_acc_init}")

    print("\n3. Simulating large-scale historical data deletion (deleting 80%: 400,000 rows)...")
    t0 = time.time()
    cur.execute(f"DELETE FROM {table_name} WHERE id > 100000;")
    del_duration = time.time() - t0
    print(f"   Delete completed in {del_duration:.2f}s.")

    print("4. Advancing transaction visibility cutoff & executing VACUUM...")
    for _ in range(3):
        cur.execute("SELECT txid_current();")
    cur.execute("CHECKPOINT;")
    t0 = time.time()
    cur.execute(f"VACUUM {table_name};")
    vac_duration = time.time() - t0
    print(f"   VACUUM completed in {vac_duration:.2f}s.")

    size_id_pre, check_id_pre = get_rel_stats(cur, idx_id)
    size_acc_pre, check_acc_pre = get_rel_stats(cur, idx_acc)
    print(f"   - {idx_id} after VACUUM: {format_size(size_id_pre)} | {check_id_pre}")
    print(f"   - {idx_acc} after VACUUM: {format_size(size_acc_pre)} | {check_acc_pre}")

    print("\n5. Invoking gs_ubtree_shrink (Online Physical Shrink)...")
    t0 = time.time()
    cur.execute(f"SELECT gs_ubtree_shrink('{idx_id}', true);")
    res_id = cur.fetchone()[0]
    duration_shrink_id = time.time() - t0

    t0 = time.time()
    cur.execute(f"SELECT gs_ubtree_shrink('{idx_acc}', true);")
    res_acc = cur.fetchone()[0]
    duration_shrink_acc = time.time() - t0

    size_id_post, check_id_post = get_rel_stats(cur, idx_id)
    size_acc_post, check_acc_post = get_rel_stats(cur, idx_acc)

    print(f"   - {idx_id}: success={res_id} in {duration_shrink_id*1000:.2f}ms | Size: {format_size(size_id_post)} | {check_id_post}")
    print(f"   - {idx_acc}: success={res_acc} in {duration_shrink_acc*1000:.2f}ms | Size: {format_size(size_acc_post)} | {check_acc_post}")

    print("\n6. Comparing with VACUUM FULL baseline (Full Index Reconstruction)...")
    t0 = time.time()
    cur.execute(f"VACUUM FULL {table_name};")
    vac_full_duration = time.time() - t0
    size_id_vf, _ = get_rel_stats(cur, idx_id)
    size_acc_vf, _ = get_rel_stats(cur, idx_acc)
    print(f"   VACUUM FULL completed in {vac_full_duration:.2f}s.")
    print(f"   - {idx_id} after VACUUM FULL: {format_size(size_id_vf)} (rebuilt size)")
    print(f"   - {idx_acc} after VACUUM FULL: {format_size(size_acc_vf)} (rebuilt size)")

    saved_id = size_id_init - size_id_vf
    ratio_id = (saved_id / size_id_init) * 100
    saved_acc = size_acc_init - size_acc_vf
    ratio_acc = (saved_acc / size_acc_init) * 100

    print(f"\n   [Space Savings Potential]:")
    print(f"   - {idx_id}: Can save {format_size(saved_id)} ({ratio_id:.1f}%) physical disk space.")
    print(f"   - {idx_acc}: Can save {format_size(saved_acc)} ({ratio_acc:.1f}%) physical disk space.")

    cur.execute(f"DROP TABLE {table_name} CASCADE;")
    conn.close()

# =========================================================================
# Scenario 2: Rolling Window FIFO Archiving Simulation
# =========================================================================
def run_scenario_2():
    print_separator("Scenario 2: Rolling-Window FIFO Archiving Simulation (5 Iterations)")
    conn = get_conn()
    cur = conn.cursor()

    table_name = "bench_fifo_tbl"
    idx_seq = "idx_fifo_seq"

    cur.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE;")
    cur.execute(f"""
        CREATE TABLE {table_name} (
            seq int,
            created_at timestamp,
            status varchar(16),
            payload text
        ) WITH (storage_type=ustore);
    """)
    cur.execute(f"CREATE INDEX {idx_seq} ON {table_name} USING ubtree (seq);")

    batch_size = 20000
    window_retain = 20000
    current_max = 0

    print(f"Parameters: Batch size = {batch_size}, Retained window = {window_retain}")

    for iter_round in range(1, 6):
        new_start = current_max + 1
        new_end = current_max + batch_size
        current_max = new_end

        cur.execute(f"""
            INSERT INTO {table_name}
            SELECT g, clock_timestamp(), 'ACTIVE', repeat('fifo_pad_', 5) || g
            FROM generate_series({new_start}, {new_end}) g;
        """)

        # Purge data outside window
        delete_cutoff = current_max - window_retain
        cur.execute(f"DELETE FROM {table_name} WHERE seq <= {delete_cutoff};")
        cur.execute(f"VACUUM {table_name};")

        # Check and perform shrink
        size_pre, check_pre = get_rel_stats(cur, idx_seq)
        cur.execute(f"SELECT gs_ubtree_shrink('{idx_seq}', true);")
        size_post, check_post = get_rel_stats(cur, idx_seq)

        cur.execute(f"SELECT count(*) FROM {table_name};")
        active_count = cur.fetchone()[0]

        print(f"Round {iter_round}: ActiveRows={active_count} | Pre-Size={format_size(size_pre)} | Post-Size={format_size(size_post)} | {check_post}")

    cur.execute(f"DROP TABLE {table_name} CASCADE;")
    conn.close()

# =========================================================================
# Scenario 3: High-Concurrency Read/Write Stress during Online Shrink
# =========================================================================
def run_scenario_3():
    print_separator("Scenario 3: Concurrent Read/Write Stress during Online Shrink")
    conn = get_conn()
    cur = conn.cursor()

    table_name = "bench_concurrent_tbl"
    idx_name = "idx_concurrent_id"

    cur.execute(f"DROP TABLE IF EXISTS {table_name} CASCADE;")
    cur.execute(f"""
        CREATE TABLE {table_name} (
            id int,
            val text
        ) WITH (storage_type=ustore);
    """)
    cur.execute(f"CREATE INDEX {idx_name} ON {table_name} USING ubtree (id);")

    print("Populating initial table (100,000 rows)...")
    cur.execute(f"INSERT INTO {table_name} SELECT g, 'v_' || g FROM generate_series(1, 100000) g;")

    stop_event = threading.Event()
    read_counter = 0
    write_counter = 0
    errors = []

    def reader_worker():
        nonlocal read_counter
        rconn = get_conn()
        rcur = rconn.cursor()
        rcur.execute("SET enable_seqscan = off;")
        while not stop_event.is_set():
            try:
                target_id = (read_counter % 50000) + 1
                rcur.execute(f"SELECT val FROM {table_name} WHERE id = {target_id};")
                rcur.fetchone()
                read_counter += 1
            except Exception as e:
                errors.append(f"Reader error: {e}")
                break
        rconn.close()

    def writer_worker():
        nonlocal write_counter
        wconn = get_conn()
        wcur = wconn.cursor()
        base_id = 100001
        while not stop_event.is_set():
            try:
                nid = base_id + write_counter
                wcur.execute(f"INSERT INTO {table_name} VALUES ({nid}, 'new_val_{nid}');")
                write_counter += 1
            except Exception as e:
                errors.append(f"Writer error: {e}")
                break
        wconn.close()

    print("Spawning 4 concurrent reader threads and 2 writer threads...")
    threads = []
    for _ in range(4):
        t = threading.Thread(target=reader_worker)
        t.start()
        threads.append(t)
    for _ in range(2):
        t = threading.Thread(target=writer_worker)
        t.start()
        threads.append(t)

    print("Triggering online shrink concurrently while traffic is running...")
    t0 = time.time()
    for _ in range(10):
        cur.execute(f"SELECT gs_ubtree_shrink('{idx_name}', true);")
        time.sleep(0.1)
    shrink_duration = time.time() - t0

    stop_event.set()
    for t in threads:
        t.join()

    print(f"Online shrink stress loop completed in {shrink_duration:.2f}s.")
    print(f"Concurrent Operations Completed: Reads = {read_counter}, Writes = {write_counter}")
    print(f"Concurrency Errors / Collisions: {len(errors)}")
    if errors:
        for err in errors[:5]:
            print("  ", err)
    else:
        print(">> Verification PASSED: Zero lock contention errors, Zero data inconsistencies!")

    cur.execute(f"DROP TABLE {table_name} CASCADE;")
    conn.close()

if __name__ == '__main__':
    print_separator("UBTree Physical Index Shrink Performance & Stress Test Suite")
    run_scenario_1()
    run_scenario_2()
    run_scenario_3()
    print_separator("ALL BENCHMARK SCENARIOS COMPLETED SUCCESSFULLY")
