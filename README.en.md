# openGauss UBTree Physical Online Shrink & Targeted Page Compaction

English | [简体中文](./README.md)

---

## 1. Feature Background & Problem Statement

In openGauss's in-place update engine (Ustore), the UBTree (Undo-based B-Tree) serves as the core index access method, supporting multi-version transaction rollback and page-level recycling via the Undo Recycle Queue (URQ). Under typical enterprise workloads with high-frequency updates and bulk deletions (such as historical data archiving, batch log cleanup, and regular purging), UBTree indexes often retain a large number of empty or low-density physical pages at the tail of the relation file, resulting in severe **Index Bloat**.

Limitations of traditional openGauss index space reclamation:
1. **Standard VACUUM**: Cleans dead tuples and registers empty pages into the URQ for future reuse, but **cannot lower the physical High-Water Mark (HWM)** of the relation file. Disk space is never returned to the operating system.
2. **VACUUM FULL**: Rebuilds the entire table and all associated indexes to reclaim disk space, but requires an **AccessExclusiveLock** on the entire table. This blocks all concurrent application reads and writes for prolonged periods, incurring heavy I/O and CPU overhead.
3. **REINDEX**: Reconstructs the B-Tree index from scratch, which also requires an exclusive lock and blocks data ingestion. Execution latency on large datasets is unacceptable for mission-critical services.

To resolve these challenges, openGauss introduces **UBTree Physical Online Shrink & Targeted Page Compaction (`gs_ubtree_shrink`)**, enabling millisecond-level physical file truncation and disk space reclamation while maintaining high-concurrency client workloads.

---

## 2. Core Architecture & Design

### 2.1 Two-Pointer Compaction Feasibility Analysis
The core inspection routine `UBTreeShrinkCheckInternal` employs a bidirectional two-pointer scan:
- **Right Pointer (Tail-Backwards Scan)**: Probes backward from `totalBlocks - 1` to identify completely empty pages and migration-eligible pages, establishing the theoretical physical truncation boundary.
- **Left Pointer (Low-Watermark Free Slot Probe)**: Scans below the truncation cutoff for reusable pages already marked `BTP_DELETED` or available in the URQ.
- **Dynamic Cost Model**: Accepts a cost-benefit ratio (`costRatio`, default 0.50) and a migration quota (`maxPages`, default 512). Targeted migration and file truncation are only triggered when the space recovered by migrating a small number of active pages meets ROI expectations, preventing unnecessary I/O.

### 2.2 Level-Aware Parent Downlink Relocation & Sibling Link Repair
When migrating high-watermark active victim pages (`UBTreeMigrateOnePage`) into lower-numbered free blocks:
- **Top-Down Parent Downlink Relocation**: For non-rightmost leaf pages, `UBTreeSearch` with the high key is used to traverse the B-Tree stack. For rightmost pages or non-leaf internal pages, an innovative **Level-Aware Parent Locator** (`UBTreeGetEndPoint` + `UBTreeGetStackBuf`) scans across the parent level, locating and locking the parent downlink without depending on user key attributes.
- **Deadlock-Free Lock Coupling Hierarchy**: Adheres strictly to the lock order: `Parent (BT_WRITE) -> Victim (BT_WRITE) -> Left Sibling (BT_WRITE) -> Right Sibling (BT_WRITE) -> New Target (BT_WRITE)`, completely preventing deadlocks with concurrent transactions.
- **Atomic Pointer Relocation**: Within a critical section, the left sibling's `btpo_next`, right sibling's `btpo_prev`, and the parent's `Downlink` are updated to point to the new block, and the victim block is marked `BTP_DELETED`.

### 2.3 Multi-Round Cascading Compaction
When leaf pages are migrated to lower offsets, internal branch pages may become completely empty and congregate near the file tail. `UBTreeShrink` features an iterative multi-round compaction loop (up to 10 rounds) that re-evaluates tree boundaries after each round, achieving **bottom-up cascading compaction across multiple index levels**.

### 2.4 Microsecond Lock Escalation & Online Truncation
- **Non-Blocking Concurrent Operations**: During the inspection and page migration phases, user `Index Scan`, `Insert`, and `Update` operations proceed concurrently under standard lightweight buffer locks.
- **Instant Physical Truncation**: Only when invoking `RelationTruncate` to physically trim trailing file blocks does the engine perform a microsecond-duration escalation to `AccessExclusiveLock`, cleaning buffer pool entries (`DropRelFileNodeBuffers`) and immediately dropping the lock, resulting in zero noticeable impact on application TPS.

### 2.5 Atomic WAL Logging & Crash Recovery
- Migrations are logged atomically via resource manager `RM_UBTREE2_ID` using `XLOG_UBTREE2_SHRINK_MOVE_LEAF`.
- The record encapsulates full page images or delta updates for the target block, victim block, siblings, and parent downlink.
- During database crash recovery or physical replication on standby instances, the `UBTree2Redo` routine idempotently replays topology repairs, ensuring zero data loss and strict structural consistency.

---

## 3. SQL Interfaces & Usage

### 3.1 Pre-Shrink Inspection (`gs_ubtree_shrink_check`)
Evaluates whether a target index will benefit from physical compaction and returns statistical metrics:
```sql
-- Standard inspection with default settings (maxPages=512, costRatio=0.50)
SELECT gs_ubtree_shrink_check('idx_user_log_id');

-- Inspection with custom tuning: max 1024 pages, cost-benefit ratio 0.30
SELECT gs_ubtree_shrink_check('idx_user_log_id', 1024, 0.30);
```
**Sample Output**:
```text
TotalBlocks: 387, TargetMaxBlock: 81, FreeTailBlocks: 306, MigratedBlocks: 1
```

### 3.2 Physical Online Shrink (`gs_ubtree_shrink`)
Executes targeted page migration and truncates trailing file blocks:
```sql
-- Online shrink (default isOnline=true, maxPages=512, costRatio=0.50)
SELECT gs_ubtree_shrink('idx_user_log_id');

-- Offline shrink (holds exclusive lock, skips conditional lock checks, ideal for maintenance windows)
SELECT gs_ubtree_shrink('idx_user_log_id', false);

-- Online shrink with customized tuning parameters
SELECT gs_ubtree_shrink('idx_user_log_id', true, 1024, 0.40);
```

---

## 4. Test Status & Performance Benchmarks

### 4.1 Regression Suite Verification
The built-in regression test suite is located at `src/test/regress/sql/test_ubtree_shrink.sql` and **passes 100%** (~3015 ms), verifying:
1. **Boundary Protection**: Safe handling of empty indexes, single-page trees, and root-only indexes;
2. **Consecutive Tail Compaction**: Direct physical truncation of trailing dead pages after bulk deletion;
3. **Targeted Page Migration & Topology Repair**: Cross-level page relocations with sibling and parent pointer validation;
4. **Concurrent MVCC Visibility**: Snapshot isolation guarantees with no missed, phantom, or corrupted rows during reads;
5. **Defensive Validation**: Protection against invalid OIDs, non-UBTree index types, and out-of-range parameters.

### 4.2 End-to-End Performance Benchmarks

Benchmark scripts are provided in `perf.sql`, with full logs recorded in `perf_results_phase1_2.out`:

| Scenario | Workload Pattern | `gs_ubtree_shrink` | `VACUUM FULL` | `REINDEX` | Space Reclamation (`gs_ubtree_shrink`) | Integrity Check |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Scenario 1** | 100K rows, 80% tail deleted | **7.75 ms** | 190.63 ms | 37.73 ms | **3096 kB → 640 kB (-79.3%)** | 100% Match (20,000 rows) |
| **Scenario 2** | 500K rows, 90% deleted | **13.19 ms** | 168.66 ms | 62.83 ms | 15 MB → 14 MB (Leaf-level migration) | 100% Match (50,000 rows) |
| **Scenario 3** | 200K rows, 50% scattered delete | **4.08 ms** | 301.68 ms | 120.14 ms | 6200 kB → 6200 kB (No tail hole; safe skip) | 100% Match (100,000 rows) |
| **Scenario 4** | 1M rows, 95% extreme delete | **18.40 ms** | 178.90 ms | 74.81 ms | 30 MB → 30 MB (Skipped with zero overhead) | 100% Match (50,000 rows) |

#### Key Performance Highlights:
- **Ultra-Fast Execution**: In typical shrink scenarios, `gs_ubtree_shrink` executes in **7.75 ms**, running **24.6x faster than `VACUUM FULL`** and **4.9x faster than `REINDEX`**;
- **Zero Query Degradation**: In range scans post-compaction (Index Only Scan on 9001 rows), `gs_ubtree_shrink` records **12.17 ms**, matching `REINDEX` (11.71 ms) and `VACUUM` (12.96 ms);
- **Guaranteed Physical Data Integrity**: Point queries, index-only scans, aggregate counts, and sequential scans show exact tuple counts and order preservation.

---

## 5. Open Source License

The openGauss core codebase and this feature are licensed under the **[Mulan Permissive Software License, Version 2 (MulanPSL-2.0)](http://license.coscl.org.cn/MulanPSL2)**.

You are free to copy, use, modify, and distribute this software and its documentation, with or without modification, provided that you adhere to the terms and conditions of MulanPSL-2.0. For complete licensing terms, please refer to the [License](./License) file.
