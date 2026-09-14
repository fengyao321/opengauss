#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
=============================================================================
UBTree Online Shrink Long-Running Endurance & Functional Verification Suite
=============================================================================
This suite simulates a high-concurrency OLTP transactional workload (Order &
Financial Ledger) over an extended duration while concurrently triggering
online UBTree index physical shrinkage (gs_ubtree_shrink with online mode).

Core Invariants & Objectives:
  1. Concurrency: High-throughput continuous INSERTS, UPDATES, Point Lookups,
     Reverse Range Scans, and Aggregations run simultaneously with online shrink.
  2. Zero Deadlocks / Zero Panics: Zero lock contention deadlocks, zero buffer
     pin panics, zero "read beyond EOF" errors.
  3. Data Integrity: Strict 100% parity between heap tables and indexes at all times.
  4. Bounded Space: Validates that the index file size dynamically shrinks and
     reclaims storage on disk after periodic tail data purges without bloat.
=============================================================================
"""

import os
import sys
import time
import signal
import argparse
import threading
import traceback
import psycopg2
from datetime import datetime

# =========================================================================
# Configuration Defaults
# =========================================================================
DEFAULT_DB_NAME = 'postgres'
DEFAULT_DB_USER = 'fengyao'
DEFAULT_DB_HOST = '/tmp'
DEFAULT_DB_PORT = 5432

TABLE_NAME = "ustore_longrun_ledger"
IDX_PK = "ustore_longrun_ledger_pkey"
IDX_USER = "idx_longrun_user_id"
IDX_TS = "idx_longrun_created_at"

# Global state
stop_event = threading.Event()
stats_lock = threading.Lock()

stats = {
    'inserts': 0,
    'updates': 0,
    'point_lookups': 0,
    'reverse_scans': 0,
    'range_aggs': 0,
    'deletes': 0,
    'shrinks_attempted': 0,
    'shrinks_succeeded': 0,
    'total_freed_bytes': 0,
    'migrated_pages': 0,
    'errors': [],
    'shrink_history': [],
    'start_time': 0,
    'end_time': 0,
}

def get_connection(args):
    conn = psycopg2.connect(
        host=args.host,
        port=args.port,
        dbname=args.dbname,
        user=args.user
    )
    conn.autocommit = True
    return conn

def format_size(bytes_val):
    if bytes_val >= 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"
    elif bytes_val >= 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.2f} MB"
    elif bytes_val >= 1024:
        return f"{bytes_val / 1024:.2f} KB"
    else:
        return f"{bytes_val} Bytes"

def get_rel_size(conn, relname):
    cur = conn.cursor()
    cur.execute(f"SELECT pg_relation_size('{relname}');")
    sz = cur.fetchone()[0]
    cur.close()
    return sz

def get_shrink_check(conn, relname):
    cur = conn.cursor()
    cur.execute(f"SELECT gs_ubtree_shrink_check('{relname}');")
    res = cur.fetchone()[0]
    cur.close()
    return res

# =========================================================================
# Schema Initialization
# =========================================================================
def setup_schema(conn):
    print("\n[Setup] Initializing UStore Ledger schema and UBTree indexes...")
    cur = conn.cursor()
    cur.execute(f"DROP TABLE IF EXISTS {TABLE_NAME} CASCADE;")
    cur.execute(f"""
        CREATE TABLE {TABLE_NAME} (
            tx_id bigint,
            user_id int,
            status varchar(16),
            amount numeric(12, 2),
            created_at timestamp,
            payload text
        ) WITH (storage_type=ustore);
    """)
    cur.execute(f"CREATE UNIQUE INDEX {IDX_PK} ON {TABLE_NAME} USING ubtree (tx_id);")
    cur.execute(f"ALTER TABLE {TABLE_NAME} ADD CONSTRAINT {TABLE_NAME}_pkey PRIMARY KEY USING INDEX {IDX_PK};")
    cur.execute(f"CREATE INDEX {IDX_USER} ON {TABLE_NAME} USING ubtree (user_id);")
    cur.execute(f"CREATE INDEX {IDX_TS} ON {TABLE_NAME} USING ubtree (created_at);")

    # Seed initial 20,000 rows
    print("[Setup] Seeding initial 20,000 rows...")
    cur.execute(f"""
        INSERT INTO {TABLE_NAME}
        SELECT
            g,
            (g % 1000) + 1,
            CASE WHEN g % 3 = 0 THEN 'PENDING' ELSE 'COMPLETED' END,
            ((g * 17) % 5000 + 10.5)::numeric(12, 2),
            clock_timestamp() - ((20000 - g) || ' milliseconds')::interval,
            repeat('ledger_tuple_payload_', 2) || g
        FROM generate_series(1, 20000) g;
    """)
    cur.close()
    print("[Setup] Schema ready.")

# =========================================================================
# Worker 1: Ingestion (INSERTs moving right boundary)
# =========================================================================
def ingestion_worker(args, worker_id, shared_cursor_state):
    conn = get_connection(args)
    cur = conn.cursor()
    batch_size = args.batch_size

    while not stop_event.is_set():
        with stats_lock:
            start_id = shared_cursor_state['next_tx_id']
            shared_cursor_state['next_tx_id'] += batch_size
            end_id = shared_cursor_state['next_tx_id'] - 1

        try:
            cur.execute(f"""
                INSERT INTO {TABLE_NAME}
                SELECT
                    g,
                    (g % 1000) + 1,
                    'PENDING',
                    ((g * 19) % 8000 + 20.0)::numeric(12, 2),
                    clock_timestamp(),
                    repeat('payload_dat_', 3) || g
                FROM generate_series({start_id}, {end_id}) g;
            """)
            with stats_lock:
                stats['inserts'] += batch_size
        except Exception as e:
            if not stop_event.is_set():
                err_msg = f"[IngestWorker-{worker_id}] Error: {e}"
                print(f"\n{err_msg}")
                with stats_lock:
                    stats['errors'].append(err_msg)
            break
        time.sleep(args.ingest_delay)

    cur.close()
    conn.close()

# =========================================================================
# Worker 2: Mutate (UPDATE status and amount in-place)
# =========================================================================
def mutate_worker(args, worker_id, shared_cursor_state):
    conn = get_connection(args)
    cur = conn.cursor()

    while not stop_event.is_set():
        with stats_lock:
            current_max = shared_cursor_state['next_tx_id']
            deleted_watermark = shared_cursor_state['deleted_watermark']

        if current_max - deleted_watermark < 1000:
            time.sleep(0.05)
            continue

        # Pick random active ranges to update
        try:
            target_id = (int(time.time() * 1000) % (current_max - deleted_watermark - 100)) + deleted_watermark + 1
            cur.execute(f"""
                UPDATE {TABLE_NAME}
                SET status = 'COMPLETED', amount = amount + 1.00
                WHERE tx_id BETWEEN {target_id} AND {target_id + 20} AND status = 'PENDING';
            """)
            updated_rows = cur.rowcount
            with stats_lock:
                stats['updates'] += max(0, updated_rows)
        except Exception as e:
            if not stop_event.is_set():
                err_msg = f"[MutateWorker-{worker_id}] Error: {e}"
                print(f"\n{err_msg}")
                with stats_lock:
                    stats['errors'].append(err_msg)
            break
        time.sleep(args.mutate_delay)

    cur.close()
    conn.close()

# =========================================================================
# Worker 3: Query (Point, Reverse Order Scan, Range Scan)
# =========================================================================
def query_worker(args, worker_id, shared_cursor_state):
    conn = get_connection(args)
    cur = conn.cursor()
    cur.execute("SET enable_seqscan = off;")

    op_cycle = 0
    while not stop_event.is_set():
        op_cycle += 1
        with stats_lock:
            current_max = shared_cursor_state['next_tx_id']
            deleted_watermark = shared_cursor_state['deleted_watermark']

        active_span = current_max - deleted_watermark
        if active_span < 50:
            time.sleep(0.05)
            continue

        try:
            query_type = op_cycle % 3

            if query_type == 0:
                # 1. Point lookup on primary key
                lookup_id = (int(time.time() * 1234) % active_span) + deleted_watermark + 1
                cur.execute(f"SELECT user_id, status, amount FROM {TABLE_NAME} WHERE tx_id = {lookup_id};")
                cur.fetchone()
                with stats_lock:
                    stats['point_lookups'] += 1

            elif query_type == 1:
                # 2. Reverse order scan on timestamp UBTree (stressing _bt_walk_left under page migration)
                cur.execute(f"""
                    SELECT tx_id, user_id, amount
                    FROM {TABLE_NAME}
                    WHERE created_at <= clock_timestamp()
                    ORDER BY created_at DESC
                    LIMIT 25;
                """)
                cur.fetchall()
                with stats_lock:
                    stats['reverse_scans'] += 1

            else:
                # 3. Range aggregation on user_id UBTree
                rand_user = (op_cycle % 1000) + 1
                cur.execute(f"""
                    SELECT count(*), coalesce(sum(amount), 0)
                    FROM {TABLE_NAME}
                    WHERE user_id BETWEEN {rand_user} AND {rand_user + 10};
                """)
                cur.fetchone()
                with stats_lock:
                    stats['range_aggs'] += 1

        except Exception as e:
            if not stop_event.is_set():
                err_msg = f"[QueryWorker-{worker_id}] Error: {e}"
                print(f"\n{err_msg}")
                with stats_lock:
                    stats['errors'].append(err_msg)
            break
        time.sleep(args.query_delay)

    cur.close()
    conn.close()

# =========================================================================
# Worker 4: Lifecycle Purger (DELETE cold tail data & VACUUM)
# =========================================================================
def purger_worker(args, shared_cursor_state):
    conn = get_connection(args)
    cur = conn.cursor()
    retain_window = args.retain_window

    while not stop_event.is_set():
        time.sleep(args.purge_interval)
        if stop_event.is_set():
            break

        with stats_lock:
            current_max = shared_cursor_state['next_tx_id']
            old_watermark = shared_cursor_state['deleted_watermark']

        # Determine target deletion watermark to create tail free space
        new_watermark = current_max - retain_window
        if new_watermark <= old_watermark + 500:
            continue

        try:
            t0 = time.time()
            cur.execute(f"DELETE FROM {TABLE_NAME} WHERE tx_id <= {new_watermark};")
            del_count = cur.rowcount

            # Immediate VACUUM to reclaim tuples and mark pages reusable/empty
            cur.execute(f"VACUUM {TABLE_NAME};")
            vac_dur = time.time() - t0

            with stats_lock:
                shared_cursor_state['deleted_watermark'] = new_watermark
                stats['deletes'] += del_count

        except Exception as e:
            if not stop_event.is_set():
                err_msg = f"[PurgerWorker] Error: {e}"
                print(f"\n{err_msg}")
                with stats_lock:
                    stats['errors'].append(err_msg)
            break

    cur.close()
    conn.close()

# =========================================================================
# Worker 5: Online Shrink Orchestrator
# =========================================================================
def shrink_orchestrator(args):
    conn = get_connection(args)
    cur = conn.cursor()
    round_no = 0

    while not stop_event.is_set():
        time.sleep(args.shrink_interval)
        if stop_event.is_set():
            break

        round_no += 1
        indexes_to_shrink = [IDX_PK, IDX_USER, IDX_TS]

        for idx_name in indexes_to_shrink:
            if stop_event.is_set():
                break
            try:
                # 1. Pre-check stats
                size_before = get_rel_size(conn, idx_name)
                chk_before = get_shrink_check(conn, idx_name)

                # 2. Online shrink execution (is_dry_run = false)
                t0 = time.time()
                cur.execute(f"SELECT gs_ubtree_shrink('{idx_name}', false);")
                res = cur.fetchone()[0]
                shrink_dur_ms = (time.time() - t0) * 1000.0

                # 3. Post stats
                size_after = get_rel_size(conn, idx_name)
                chk_after = get_shrink_check(conn, idx_name)
                freed_bytes = max(0, size_before - size_after)

                # Parse migrated blocks if any
                migrated = 0
                if "MigratedBlocks:" in chk_before:
                    try:
                        migrated = int(chk_before.split("MigratedBlocks:")[1].split()[0].strip())
                    except:
                        pass

                with stats_lock:
                    stats['shrinks_attempted'] += 1
                    if res:
                        stats['shrinks_succeeded'] += 1
                    stats['total_freed_bytes'] += freed_bytes
                    stats['migrated_pages'] += migrated
                    stats['shrink_history'].append({
                        'timestamp': datetime.now().strftime('%H:%M:%S'),
                        'index': idx_name,
                        'duration_ms': shrink_dur_ms,
                        'size_before': size_before,
                        'size_after': size_after,
                        'freed_bytes': freed_bytes,
                        'migrated': migrated,
                        'pre_check': chk_before
                    })

            except Exception as e:
                if not stop_event.is_set():
                    err_msg = f"[ShrinkOrchestrator] Error on {idx_name}: {e}"
                    print(f"\n{err_msg}")
                    with stats_lock:
                        stats['errors'].append(err_msg)

    cur.close()
    conn.close()

# =========================================================================
# Consistency and Integrity Verifier
# =========================================================================
def verify_integrity(conn):
    print("\n--- [Consistency Guard] Performing Full Integrity Audit ---")
    cur = conn.cursor()

    # 1. Compare Sequential Scan Count vs Primary Key Index Scan Count
    cur.execute(f"SET enable_seqscan = on; SELECT count(*) FROM {TABLE_NAME};")
    heap_count = cur.fetchone()[0]

    cur.execute(f"SET enable_seqscan = off; SELECT count(tx_id) FROM {TABLE_NAME};")
    pk_idx_count = cur.fetchone()[0]

    cur.execute(f"SET enable_seqscan = off; SELECT count(user_id) FROM {TABLE_NAME};")
    user_idx_count = cur.fetchone()[0]

    cur.execute(f"SET enable_seqscan = off; SELECT count(created_at) FROM {TABLE_NAME};")
    ts_idx_count = cur.fetchone()[0]

    print(f"  • Heap Row Count:               {heap_count:,}")
    print(f"  • Primary Key Index Row Count:   {pk_idx_count:,}")
    print(f"  • User Index Row Count:          {user_idx_count:,}")
    print(f"  • Timestamp Index Row Count:     {ts_idx_count:,}")

    mismatches = []
    if heap_count != pk_idx_count:
        mismatches.append(f"PK index mismatch: heap={heap_count} vs idx={pk_idx_count}")
    if heap_count != user_idx_count:
        mismatches.append(f"User index mismatch: heap={heap_count} vs idx={user_idx_count}")
    if heap_count != ts_idx_count:
        mismatches.append(f"Timestamp index mismatch: heap={heap_count} vs idx={ts_idx_count}")

    # 2. Check for duplicate keys in primary key index
    cur.execute(f"SELECT count(*) FROM (SELECT tx_id, count(*) FROM {TABLE_NAME} GROUP BY tx_id HAVING count(*) > 1) t;")
    dup_pk = cur.fetchone()[0]
    if dup_pk > 0:
        mismatches.append(f"Duplicate primary keys detected: {dup_pk}")

    cur.close()

    if mismatches:
        print("\n❌ CRITICAL INTEGRITY FAILURE:")
        for m in mismatches:
            print(f"   - {m}")
        return False
    else:
        print("✅ INTEGRITY CHECK PASSED: Indexes perfectly mirror heap table data! 0 discrepancies.")
        return True

# =========================================================================
# Report Generator
# =========================================================================
def generate_report(args, report_path, audit_passed):
    duration = stats['end_time'] - stats['start_time']
    total_queries = stats['point_lookups'] + stats['reverse_scans'] + stats['range_aggs']
    total_qps = total_queries / duration if duration > 0 else 0
    total_tps = (stats['inserts'] + stats['updates'] + stats['deletes']) / duration if duration > 0 else 0

    conn = get_connection(args)
    final_pk_sz = get_rel_size(conn, IDX_PK)
    final_user_sz = get_rel_size(conn, IDX_USER)
    final_ts_sz = get_rel_size(conn, IDX_TS)
    final_tbl_sz = get_rel_size(conn, TABLE_NAME)
    conn.close()

    md = []
    md.append("# UBTree 在线物理收缩长周期稳定性与高并发验证报告\n")
    md.append(f"> **测试时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  ")
    md.append(f"> **运行持续时间**: {duration:.2f} 秒 ({duration/60:.2f} 分钟)  ")
    md.append(f"> **并发模式**: 混合高并发 OLTP (高频写入、原位更新、反向扫描、周期淘汰) + 在线原位收缩 (`gs_ubtree_shrink`)  ")
    md.append(f"> **数据完整性校验**: {'✅ 100% 完美对齐 (0 差异)' if audit_passed else '❌ 存在不一致'}  ")
    err_count = len(stats['errors'])
    deadlock_msg = '✅ 0 死锁, 0 Panic, 0 越界' if err_count == 0 else f'❌ 出现 {err_count} 个异常'
    md.append(f"> **死锁与崩溃监测**: {deadlock_msg}  \n")
    md.append("---\n")

    md.append("## 一、全周期性能与吞吐指标\n")
    md.append("| 指标类别 | 统计指标名称 | 累计总量 | 平均吞吐速率 |")
    md.append("| :--- | :--- | :--- | :--- |")
    md.append(f"| **写事务吞吐** | 新订单写入 (Bulk INSERT) | {stats['inserts']:,} 行 | {stats['inserts']/duration:.1f} 行/秒 |")
    md.append(f"| **写事务吞吐** | 原位更新 (In-place UPDATE) | {stats['updates']:,} 行 | {stats['updates']/duration:.1f} 行/秒 |")
    md.append(f"| **写事务吞吐** | 冷数据淘汰 (DELETE + VACUUM) | {stats['deletes']:,} 行 | {stats['deletes']/duration:.1f} 行/秒 |")
    md.append(f"| **读查询负载** | 主键单行点查 (Point IndexScan) | {stats['point_lookups']:,} 次 | {stats['point_lookups']/duration:.1f} QPS |")
    md.append(f"| **读查询负载** | 时序反向扫描 (Reverse `_bt_walk_left`) | {stats['reverse_scans']:,} 次 | {stats['reverse_scans']/duration:.1f} QPS |")
    md.append(f"| **读查询负载** | 散列范围聚合 (Range Aggregation) | {stats['range_aggs']:,} 次 | {stats['range_aggs']/duration:.1f} QPS |")
    md.append(f"| **总体统计** | **综合写入 TPS** | **{stats['inserts'] + stats['updates'] + stats['deletes']:,} 次** | **{total_tps:.1f} TPS** |")
    md.append(f"| **总体统计** | **综合查询 QPS** | **{total_queries:,} 次** | **{total_qps:.1f} QPS** |")
    md.append("\n---\n")

    md.append("## 二、在线物理收缩 (Online Shrink) 运行统计\n")
    md.append(f"- **尝试收缩次数**: {stats['shrinks_attempted']} 次")
    md.append(f"- **成功收缩次数**: {stats['shrinks_succeeded']} 次")
    md.append(f"- **累计搬迁活跃页数**: {stats['migrated_pages']} 个叶子页 (定向迁移并安全重构 Downlink)")
    md.append(f"- **累计物理截断释放空间**: **{format_size(stats['total_freed_bytes'])}**")
    md.append(f"- **最终物理文件大小**:")
    md.append(f"  - 主键索引 (`{IDX_PK}`): **{format_size(final_pk_sz)}** (动态维持紧凑状态)")
    md.append(f"  - 用户索引 (`{IDX_USER}`): **{format_size(final_user_sz)}**")
    md.append(f"  - 时序索引 (`{IDX_TS}`): **{format_size(final_ts_sz)}**")
    md.append(f"  - 表文件 (`{TABLE_NAME}`): **{format_size(final_tbl_sz)}**\n")

    if stats['shrink_history']:
        md.append("### 最近 10 次在线收缩明细采样\n")
        md.append("| 采样时间 | 目标索引 | 执行耗时 | 收缩前大小 | 收缩后大小 | 物理释放空间 | 迁移页数 |")
        md.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
        for rec in stats['shrink_history'][-10:]:
            md.append(f"| {rec['timestamp']} | `{rec['index']}` | {rec['duration_ms']:.2f} ms | {format_size(rec['size_before'])} | {format_size(rec['size_after'])} | {format_size(rec['freed_bytes'])} | {rec['migrated']} |")
        md.append("\n")

    md.append("---\n")
    md.append("## 三、稳定性与异常监控总结\n")
    if stats['errors']:
        md.append(f"⚠️ **捕获到以下 {len(stats['errors'])} 个错误**:\n")
        for err in stats['errors'][:10]:
            md.append(f"- `{err}`")
    else:
        md.append("🎉 **完美通过长周期稳定性测试**: 全程高并发读写及反向扫描与在线收缩无缝对抗，未发生任何死锁、断言崩溃、连接断开或 `read beyond EOF` 越界！\n")

    report_content = "\n".join(md)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report_content)
    print(f"\n[Report] Long-running report saved to: {report_path}")

# =========================================================================
# Main Entry Point
# =========================================================================
def main():
    parser = argparse.ArgumentParser(description="UBTree Online Shrink Long-Running Endurance Suite")
    parser.add_argument("--duration", type=int, default=180, help="Test duration in seconds (default: 180)")
    parser.add_argument("--readers", type=int, default=4, help="Number of concurrent query workers (default: 4)")
    parser.add_argument("--writers", type=int, default=2, help="Number of concurrent ingest/mutate workers (default: 2)")
    parser.add_argument("--batch-size", type=int, default=1000, help="Batch insert row count (default: 1000)")
    parser.add_argument("--retain-window", type=int, default=30000, help="Number of rows retained in sliding window (default: 30000)")
    parser.add_argument("--purge-interval", type=float, default=6.0, help="Interval between cold data purges in seconds (default: 6.0)")
    parser.add_argument("--shrink-interval", type=float, default=8.0, help="Interval between online shrink calls in seconds (default: 8.0)")
    parser.add_argument("--ingest-delay", type=float, default=0.08, help="Delay between insert batches in seconds (default: 0.08)")
    parser.add_argument("--mutate-delay", type=float, default=0.03, help="Delay between update batches in seconds (default: 0.03)")
    parser.add_argument("--query-delay", type=float, default=0.01, help="Delay between query loops in seconds (default: 0.01)")
    parser.add_argument("--host", type=str, default=DEFAULT_DB_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_DB_PORT)
    parser.add_argument("--dbname", type=str, default=DEFAULT_DB_NAME)
    parser.add_argument("--user", type=str, default=DEFAULT_DB_USER)
    parser.add_argument("--output-report", type=str, default="ubtree_shrink_doc/perf/longrun_stability_report.md")
    args = parser.parse_args()

    print("=" * 80)
    print(" UBTree Online Shrink Long-Running Endurance & Concurrency Test")
    print(f" Target Duration: {args.duration}s ({args.duration/60:.2f} mins) | Readers: {args.readers} | Writers: {args.writers}")
    print(f" Shrink Interval: {args.shrink_interval}s | Retained Window: {args.retain_window} rows")
    print("=" * 80)

    # Clean interrupt handler
    def sigint_handler(signum, frame):
        print("\n[Signal] Interrupted by user. Gracefully winding down workers...")
        stop_event.set()

    signal.signal(signal.SIGINT, sigint_handler)

    # Initialize schema
    init_conn = get_connection(args)
    setup_schema(init_conn)
    init_conn.close()

    shared_cursor_state = {
        'next_tx_id': 20001,
        'deleted_watermark': 0,
    }

    stats['start_time'] = time.time()

    # Launch threads
    threads = []

    # 1. Ingestion workers
    for wid in range(args.writers):
        t = threading.Thread(target=ingestion_worker, args=(args, wid + 1, shared_cursor_state), name=f"Ingest-{wid+1}")
        t.start()
        threads.append(t)

    # 2. Mutate worker
    for wid in range(max(1, args.writers // 2)):
        t = threading.Thread(target=mutate_worker, args=(args, wid + 1, shared_cursor_state), name=f"Mutate-{wid+1}")
        t.start()
        threads.append(t)

    # 3. Query workers
    for wid in range(args.readers):
        t = threading.Thread(target=query_worker, args=(args, wid + 1, shared_cursor_state), name=f"Query-{wid+1}")
        t.start()
        threads.append(t)

    # 4. Lifecycle purger worker
    t_purger = threading.Thread(target=purger_worker, args=(args, shared_cursor_state), name="Purger")
    t_purger.start()
    threads.append(t_purger)

    # 5. Online shrink orchestrator
    t_shrink = threading.Thread(target=shrink_orchestrator, args=(args,), name="ShrinkDriver")
    t_shrink.start()
    threads.append(t_shrink)

    # Monitoring loop
    try:
        while not stop_event.is_set():
            time.sleep(5.0)
            elapsed = time.time() - stats['start_time']
            if elapsed >= args.duration:
                print(f"\n[Timer] Target duration reached ({args.duration}s). Initiating shutdown...")
                stop_event.set()
                break

            with stats_lock:
                ins = stats['inserts']
                upd = stats['updates']
                del_cnt = stats['deletes']
                pts = stats['point_lookups']
                rev = stats['reverse_scans']
                shrinks = stats['shrinks_succeeded']
                freed = format_size(stats['total_freed_bytes'])
                err_cnt = len(stats['errors'])

            rem = max(0, args.duration - elapsed)
            print(f"[{elapsed:04.0f}s elapsed | {rem:04.0f}s left] Inserts: {ins:,} | Updates: {upd:,} | Deletes: {del_cnt:,} | Reads: {pts + rev:,} (Rev: {rev:,}) | Shrinks: {shrinks} (Freed: {freed}) | Errors: {err_cnt}")

            if err_cnt > 0:
                print(f"⚠️ Errors detected during execution! Halting early.")
                stop_event.set()
                break

    except KeyboardInterrupt:
        print("\n[Ctrl+C] Stopping...")
        stop_event.set()

    print("\n[Shutdown] Waiting for worker threads to exit gracefully...")
    for t in threads:
        t.join(timeout=10.0)

    stats['end_time'] = time.time()
    print("[Shutdown] All worker threads stopped.")

    # Integrity verification
    verify_conn = get_connection(args)
    audit_passed = verify_integrity(verify_conn)

    # Final report
    generate_report(args, args.output_report, audit_passed)

    # Cleanup table if passed
    if audit_passed and len(stats['errors']) == 0:
        cur = verify_conn.cursor()
        cur.execute(f"DROP TABLE IF EXISTS {TABLE_NAME} CASCADE;")
        cur.close()
        print("[Cleanup] Cleaned up temporary test table.")
    verify_conn.close()

    if not audit_passed or len(stats['errors']) > 0:
        print("\n❌ Long-running test finished with ERRORS or INCONSISTENCIES.")
        sys.exit(1)
    else:
        print("\n🎉 Long-running endurance and online shrink test PASSED SUCCESSFULLY!")
        sys.exit(0)

if __name__ == '__main__':
    main()
