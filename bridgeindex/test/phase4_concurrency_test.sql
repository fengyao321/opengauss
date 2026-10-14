-- ============================================================================
-- openGauss Ustore Bridge Index Phase 4: Concurrency Verification Guide & SQL Spec
-- Target Feature: Multi-Session Concurrency, Atomic Sequence Allocation,
--                 MVCC Readers vs Writers, Concurrent In-Place/Key Updates,
--                 Rollback Isolation, and 4-Index Simultaneous Execution.
-- ============================================================================

\echo '>>> [INFO] openGauss Bridge Index Concurrency Test Specification (Phase 4)'

-- ----------------------------------------------------------------------------
-- Scenario 1: Concurrent High-Throughput INSERTs & Monotonic Sequence Check
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   Multiple concurrent worker sessions simultaneously insert rows into
--   a Ustore table equipped with Hash and GIN bridged indexes.
--
-- Session Setup:
DROP TABLE IF EXISTS t_conc_ins CASCADE;
CREATE TABLE t_conc_ins (
    id INT,
    code TEXT,
    tags INT[]
) WITH (storage_type = ustore);

CREATE INDEX idx_cins_hash ON t_conc_ins USING hash(code);
CREATE INDEX idx_cins_gin ON t_conc_ins USING gin(tags);

-- Concurrency Invariant:
--   1. pg_atomic_fetch_add_u64保证g_bridge_seq在多线程/多会话并发插入时严格原子递增。
--   2. 伴生桥接表 pg_toast.pg_bridge_<oid> 中的 bridge_seq 全局唯一，无任何冲突碰撞。
--   3. 每个桥接索引独立生成映射记录，保障两阶段解引用数据精确匹配。

-- ----------------------------------------------------------------------------
-- Scenario 2: Concurrent Readers vs Writers under MVCC Snapshot Isolation
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   - Writer Sessions: 持续向 Ustore 表插入新增记录并提交。
--   - Reader Sessions: 并发使用 Hash 点查与 GIN 包含查询 (@>)。
--
-- Verification Target:
--   - 验证两阶段物理解引用（BridgeLookupAndVerifyVisibility）遵守快照可见性。
--   - 读会话绝不崩溃、绝不读到半写入元组，无幽灵元组。

-- ----------------------------------------------------------------------------
-- Scenario 3: Concurrent In-Place UPDATE vs Key UPDATE (Bridge Tag Stability)
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   - Session A: 对非索引列 payload 进行高频原地更新（In-Place Update）。
--   - Session B: 对索引列 code/tags 进行键值变更更新（Key Update）。
--   - Session C: 并发执行索引扫描。
--
-- Verification Target:
--   - 原地更新共享原有 ctid 与 bridge_seq，Tag 校验通过，零锁冲突。
--   - 键值更新生成新版本元组及新桥接映射，旧键无法查出，新键可查。

-- ----------------------------------------------------------------------------
-- Scenario 4: Concurrent Transactions with Mixed Commits and Rollbacks
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   - Even Sessions: BEGIN -> INSERT -> 事务内可见性自检 -> COMMIT
--   - Odd Sessions:  BEGIN -> INSERT -> 事务内可见性自检 -> ROLLBACK
--
-- Verification Target:
--   - 已回滚会话分配的 bridge_seq 在伴生结构中随事务回滚对外部读会话不可见。
--   - 外部 Hash/GIN 扫描对已回滚元组实现 100% 过滤，零脏读。

-- ----------------------------------------------------------------------------
-- Scenario 5: High-Frequency Slot Churn, VACUUM & Anti-Phantom Tag Validation
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   - Session A: 批量删除元组 (DELETE)
--   - Session B: 触发 VACUUM 清理空间
--   - Session C: 快速插入新元组复用空闲槽位 (Slot Reuse)
--   - Session D: 持续以已删除键发起索引查询
--
-- Verification Target:
--   - UHeapDiskTupleSetBridgeTag 将 bridge_seq 低 16 位写入元组头。
--   - 解引用时严格比对 Tag，彻底防止槽位被复用后的“幽灵元组”串读。

-- ----------------------------------------------------------------------------
-- Scenario 6: Concurrent Multi-Index Coexistence (UBTree + Hash + GiST + GIN)
-- ----------------------------------------------------------------------------
-- Test Architecture:
--   单张 Ustore 表同时挂载 UBTree (B树)、Hash (哈希)、GiST (空间)、GIN (倒排)。
--   并发会话混合执行范围扫描、哈希点查、多边形外包盒包含检索、数组重叠运算。
--
-- Verification Target:
--   - 原生 UBTree 走标准 Ustore 引擎。
--   - Hash、GiST、GIN 并发走 Bridge 伴生桥接路由与 BitmapScan 解引用。
--   - 四类索引在极限并发读写下零死锁、零内存泄漏、数据一致性 100%。

\echo '>>> [INFO] To run the automated multi-threaded concurrency harness, execute:'
\echo '>>>        bash bridgeindex/test/run_concurrency_test.sh'
