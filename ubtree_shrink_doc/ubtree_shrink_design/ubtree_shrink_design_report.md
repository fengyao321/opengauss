# UBTree 在线物理空间收缩（Online Shrink）高阶设计方案 (v3.0 生产级架构)

---

## 1. 目标定位与核心价值

直接面向**阶段三（Phase 3: Online Concurrent Shrink & Background Autonomics）**进行全架构演进：
* **业务零阻塞（Non-blocking DDL/Maintenance）**：搬迁阶段持有轻量级锁（`RowExclusiveLock` / `ShareUpdateExclusiveLock`），并发 `IndexScan`、`Insert`、`Delete` 正常执行。
* **微秒级截断锁切换（Micro-second Lock Escalation）**：仅在底层物理 `RelationTruncate` 阶段升级为短时排他锁，完成 Smgr 文件裁剪与共享 Buffer 失效，随后立即释放。
* **自治回收与防抖（Autonomic & Anti-Jitter）**：支持与 Autovacuum / 自动化调度器整合，设置回缩阈值与防抖滞后窗口，避免频繁 Truncate/Extend 乒乓效应。

---

## 2. 阶段三关键技术攻坚与深度设计

### 2.1 读写并发与拓扑动态竞争（Concurrent Tree Race）
* **并发分裂（Concurrent Split）冲突**：在锁定 `OldBlock` 与 `Parent` 期间，并发插入可能正在分裂 `Parent` 或 `OldBlock`。
* **解法：动态 LSN 与 Epoch 拓扑再校验**：
  1. 采用 **B-Tree 锁耦合与条件锁回退机制（Conditional Lock Coupling & Backoff Retry）**：
     - Step A: 锁定 `OldBlock` (BT_WRITE)。
     - Step B: 使用 `ConditionalLockBuffer(LeftBlock, BT_WRITE)`；若冲突则释放 `OldBlock` 随机退避重试，消除 AB-BA 死锁。
     - Step C: 顺着 UBTree 遍历堆栈寻找 `Parent` 并加写锁。加锁后立刻比对 `P_HIKEY` 和 Downlink 是否仍指向 `OldBlock`。若并发 Split 导致 Downlink 转移，放弃本次搬迁并重试。

### 2.2 瞬时锁升级截断协议（Two-Phase Lock Upgrade for Truncate）
物理截断 `RelationTruncate` 必须清理超过水位的 Buffer，不能有活跃 reader/writer。
* **Phase A（在线搬迁期）**：持 `ShareUpdateExclusiveLock`。搬迁数据至头部 URQ 空闲页，并发事务无感知。
* **Phase B（截断临界区）**：
  1. 调用 `ConditionalLockRelation(rel, AccessExclusiveLock)` 或短暂申请排他锁；
  2. 若有并发长查询持有 `AccessShareLock`，Shrink 线程等待最长 `shrink_lock_timeout`（如 100ms），超时则让出排他锁并延迟下一轮重试，**绝不阻塞正常业务查询**；
  3. 成功获取锁后，快速执行 `UBTreePurgeRecycleQueueAboveWatermark` 并调用 `RelationTruncate(rel, targetMaxBlock)`，立刻释放排他锁。

### 2.3 崩溃一致性与原子 5-Buffer WAL
* 在单次搬迁中原子写入 `XLOG_UBTREE_SHRINK_MOVE_LEAF`：
  - 注册 `NewBlock` (REGBUF_WILL_INIT)、`OldBlock`、`ParentBlock`、`LeftBlock`、`RightBlock`。
  - Redo 重放具备完全幂等性：基于各 Page LSN 判断是否需要 Replay，保证在任意时刻 Crash 重启后 B-Tree 拓扑强一致。

### 2.4 自适应防抖与后台自治触发（Autovacuum Integration）
* **触发判定**：
  - 条件 1：`freedTailBlocks >= ubtree_shrink_min_blocks`（例如至少有连续 128 个可截断页）。
  - 条件 2：尾部空闲比例超过 `ubtree_shrink_ratio_threshold`（例如 20%）。
  - 条件 3：距离上次扩展/写入超过静默时间窗口，避免“刚截断 1GB 紧接着大量 INSERT 再次扩盘”的写放大。

---

## 3. 在线收缩状态机与执行流程图

```
+-----------------------------------------------------------------------+
| 1. 在线评估与扫描 (ShareUpdateExclusiveLock)                            |
|    - 倒序扫描尾部 Block，确定可收缩边界 TargetMaxBlock                  |
|    - 筛选待搬迁 Leaf 节点队列 MigrationList                           |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| 2. 在线定向搬迁循环 (Page-Level Lock Coupling)                         |
|    - 从 URQ 获取 < TargetMaxBlock 的低位空闲页                        |
|    - 条件锁耦合: Old -> Left -> Right -> Parent (校验 LSN / Downlink) |
|    - 拷贝 Tuple，修正左右兄弟链表与父节点槽位                         |
|    - 记 XLOG_UBTREE_SHRINK_MOVE_LEAF WAL，提交 URQ 消费               |
|    - 逐页释放锁，周期性响应 QueryCancel / ProcDie 中断                |
+-----------------------------------------------------------------------+
                                  |
                                  v
+-----------------------------------------------------------------------+
| 3. 微秒级锁升级与物理裁剪 (Brief AccessExclusiveLock Window)           |
|    - 快速尝试获取排他锁 (带超时机制，不阻塞生产业务)                  |
|    - 清理 URQ 中 >= TargetMaxBlock 的残余项                           |
|    - 执行 RelationTruncate(rel, TargetMaxBlock) 物理裁剪 OS 文件       |
|    - 降级/释放排他锁，完成在线 Shrink                                 |
+-----------------------------------------------------------------------+
```

---

## 4. 接口与参数规范

### 4.1 SQL 系统接口
1. `gs_ubtree_shrink(relname text, is_online bool DEFAULT true) RETURNS bool`
2. `gs_ubtree_shrink_check(relname text) RETURNS text`

### 4.2 运维 GUC 参数支持（规划）
* `ubtree_shrink_lock_timeout`: 锁升级尝试的最大超时时间（默认 200ms）。
* `ubtree_shrink_max_pages_per_round`: 单轮搬迁的最大页面上限，支持大索引分批平滑收缩。
