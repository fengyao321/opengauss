# PostgreSQL Hackers Review: UBTree Online Physical Shrink & Targeted Page Migration

**Reviewer**: PostgreSQL Hackers Community Perspective (pgsql-hackers / Core Storage & Concurrency Mindset)  
**Subject**: Re: [PATCH/RFC] openGauss UBTree Online Physical Shrink & Targeted Migration  
**Status**: **NACK with reservation** (Needs fundamental architectural rethink on concurrency & WAL recovery before upstreaming)

---

## 0. 总结与评审裁决 (Executive Verdict)

**Verdict**: **NACK (暂不建议合并)**。

这个补丁实现了一套用于 UBTree 的物理文件在线收缩与定向页迁移机制（Targeted Migration + URQ Compaction + Online Lock Escalation Truncate），试图解决 B-Tree 索引长期以来“尾部空间难以安全归还 OS”的顽疾。该特性的工程动机完全成立，算法原型的思路也具有启发性。

然而，从 PostgreSQL / 数据库内核工程的核心原则——**正确性绝对优先、零数据损坏容忍、无并发死锁风险、崩溃恢复一致性**的角度审视，当前实现存在多处破坏存储引擎核心契约的严重设计缺陷：
1. **违背 B-Tree 加锁层级，引入直接且致命的 AB-BA 死锁路径**；
2. **缺乏并发读事务 Pin-count 安全栅栏，可能导致并发 Index Scan 触发操作系统级 `read beyond EOF` 或脏页刷盘 Panic**；
3. **URQ 水位线物理清理未记 WAL，导致 Standby 备机重放后元数据与物理文件撕裂**；
4. **肆意污染 Session 级别的全局事务可见性水位线（`RecentGlobalDataXmin`）**；
5. **单条 WAL 记录跨 5 个 Block 且强制全页写入，严重破坏备机并行回放流水线**。

在这些基础设计缺陷得到彻底解决之前，该代码无法满足企业级生产环境的稳定性要求。

---

## 1. 并发与锁协议缺陷 (Locking & Concurrency Issues)

### 1.1 页面锁逆序与 AB-BA 致命死锁
- **相关代码**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` (`UBTreeMigrateOnePage`)
- **代码行为**:
  在 `UBTreeMigrateOnePage()` 中，函数加锁顺序如下：
  1. 通过 `UBTreeSearch` 或 `UBTreeGetStackBuf` 获取并持有 `parentBuf` 的 `BT_WRITE` 锁；
  2. 保持 `parentBuf` 写锁不放，向下申请 `victimBuf` 的 `BT_WRITE` 锁；
  3. 保持上述锁不放，向左申请 `leftBuf` 的 `BT_WRITE` 锁（自右向左加锁）；
  4. 保持上述锁不放，申请 `rightBuf` 的 `BT_WRITE` 锁；
  5. 申请 `newBuf` 的 `BT_WRITE` 锁。

- **根本缺陷 (Hacker's Analysis)**:
  标准 B-Tree（Lehman & Yao 并发协议及 PostgreSQL 变体）中，为了杜绝死锁，严格规定了加锁方向：
  - **横向扫描与分裂链**：必须严格遵循**自左向右 (Left-to-Right)** 加锁；
  - **向下遍历与树修正**：查找自顶向下（持读锁或松散耦合），而分裂与页面删除自底向上（Bottom-Up）。
  
  当前代码持有父节点写锁的同时，不仅向下去锁子节点（Top-Down Write Locking），还向左去锁左兄弟（Right-to-Left Write Locking）。
  
  **推演死锁场景**：
  * **进程 A (Shrink Worker)**: 持有 `parentBuf` 写锁，正准备加锁 `victimBuf` 或 `leftBuf`。
  * **进程 B (并发写事务/Split)**: 正在对 `victimBuf` 或 `leftBuf` 执行插入，页面装满触发 `_bt_split`，持有 `victimBuf` / `leftBuf` 的排他写锁，正向上调用 `_bt_insert_parent` 试图获取 `parentBuf` 的排他写锁。
  * **结果**：**瞬时构成 AB-BA 死锁**。
  
  虽然代码在 `isOnline == true` 时使用了 `ConditionalLockBuffer` 退避，但：
  - 在 `isOnline == false`（离线收缩模式）下，直接调用阻塞式 `LockBuffer(..., BT_WRITE)`，**百分之百会导致不可恢复的死锁**；
  - 即便在 `isOnline` 模式下，当 `ConditionalLockBuffer` 失败退避时，由于父节点写锁在搜索阶段被长时间持有，高频并发下的退避率极高，严重阻断正常读写业务。

---

### 1.2 缺乏 Pin-count 安全保证与并发扫描丢数据风险 (Pin Invalidation & I/O Panic)
- **相关代码**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` (`UBTreeOnlineTruncate`)
- **代码行为**:
  ```cpp
  LockRelationForExtension(rel, ExclusiveLock);
  BlockNumber currentTotal = RelationGetNumberOfBlocks(rel);
  if (currentTotal > targetMaxBlock) {
      RelationTruncate(rel, targetMaxBlock);
  }
  UnlockRelationForExtension(rel, ExclusiveLock);
  ```
- **根本缺陷 (Hacker's Analysis)**:
  `UBTreeOnlineTruncate` 仅使用带超时的 `ConditionalLockRelation(rel, AccessExclusiveLock)` 尝试获取表级锁。获取到锁后，**立即调用 `RelationTruncate` 缩容物理文件**。
  
  然而，在 PostgreSQL / openGauss 中，索引扫描（`IndexScan` / `BitmapIndexScan`）的读事务并发模型是：
  1. 读事务持有 `AccessShareLock`（或者已经越过了锁检查点）；
  2. 读事务固定 Buffer（`IncrBufferRefCount` / 持有 Pin），释放 Buffer Content Lock，读取数据；
  3. 通过 `opaque->btpo_next` 准备读取下一个物理块。
  
  如果一个长查询正在读取 `victimBlk` 或物理尾部的某个 Block，即便它释放了 Buffer Lock，它的 Pin 依然挂在 Buffer Pool 中！
  此时 Shrink 进程拿到几毫秒的 `AccessExclusiveLock` 并立即将 OS 文件截断：
  - 该长查询唤醒后，若尝试重新读取或重校验该页，或者脏页刷盘线程（Buffer Sync / Checkpointer）试图将残留在内存池中的尾部脏页刷回磁盘时，底层的 `smgrwrite` / `smgrread` 将直接报出 **`seeking/reading beyond EOF`**，在很多内核路径中这会直接升级为 **PANIC**！
  - **对比 PG 规范做法**：PostgreSQL 在做 `VACUUM` 截断表尾时，必须调用 `heap_truncate_find_min_clean` 等机制，检查 Buffer Pool 中每个 Block 的 Pin 状态与活跃事务，只有证明没有 Backend 在使用尾部 Block 时，才允许物理 Truncate。

---

## 2. 崩溃恢复与 WAL 契约缺陷 (Crash Recovery & WAL Protocol)

### 2.1 URQ 水位线清理完全缺失 WAL (Standby Corruption Hole)
- **相关代码**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` (`UBTreePurgeRecycleQueueAboveWatermark`) 与 `src/gausskernel/storage/access/ubtree/ubtxlog.cpp`
- **代码行为**:
  在截断文件前，主库调用了 `UBTreePurgeRecycleQueueAboveWatermark(rel, targetMaxBlock)`，遍历并删除了 URQ 队列中所有大于等于 `targetMaxBlock` 的条目。
  但是，该函数**没有记录任何专属 WAL**，也没有在事务日志中留下记录。
- **灾难推演 (Hacker's Analysis)**:
  1. 主库执行 Shrink：清理了主库自身的 URQ 内存/页面元数据，随后调用 `RelationTruncate`，写了一条 `XLOG_SMGR_TRUNCATE`。
  2. 备机（Standby）接收到 WAL 并重放 `XLOG_SMGR_TRUNCATE`：备机的底层索引物理文件被截断到了 `targetMaxBlock`。
  3. **然而，备机上的 URQ 页面从未被清理！** 备机上的 URQ 仍然记录着大量大于 `targetMaxBlock` 的“空闲块”。
  4. 一旦发生主备倒换（Failover），备机升主，新的主库在后续插入需要申请新页时，从 URQ 中弹出了一个 BlockNumber（例如原来尾部的 1500 号块）。
  5. 此时文件实际大小只有 500 个块，内核直接对 1500 号块执行写入，导致文件空洞（File Hole）、数据错乱，或者在无稀疏文件支持的文件系统上抛出严重 I/O 错误。

---

### 2.2 多块复合 WAL 原子性代价与备机回放停顿 (Multi-Block Redo Stall)
- **相关代码**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` (`UBTreeMigrateOnePage`)
- **代码行为**:
  ```cpp
  XLogRegisterBuffer(0, newBuf, REGBUF_FORCE_IMAGE | REGBUF_STANDARD);
  XLogRegisterBuffer(1, victimBuf, REGBUF_STANDARD);
  XLogRegisterBuffer(2, leftBuf, REGBUF_STANDARD);
  XLogRegisterBuffer(3, rightBuf, REGBUF_STANDARD);
  XLogRegisterBuffer(4, parentBuf, REGBUF_STANDARD);
  recptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_MOVE_LEAF);
  ```
- **架构审查 (Hacker's Analysis)**:
  单条 WAL 记录一次性注册 5 个 Block，且对 `newBuf` 强制使用了 `REGBUF_FORCE_IMAGE`（整页 8KB 写入）：
  1. **WAL 膨胀**：每迁移 1 个 Page，WAL 记录大小至少为 8KB + 额外开销。如果迁移 512 个 Page，将瞬时产生 > 4.5MB 的 WAL 写入，这在高频 OLTP 场景下会造成不必要的日志暴增。
  2. **并行回放瓶颈 (Parallel Redo Pipeline Stall)**：现代数据库（包括 openGauss 的 Parallel Recovery）采用基于 Page ID 哈希的工作分发模型。当一条 WAL 记录同时引用 5 个不同的 Block 时，Dispatcher 必须对这 5 个 Worker 线程执行全局同步栅栏（Barrier Synchronization），导致备机回放吞吐急剧恶化。

---

## 3. 全局状态污染与架构反模式 (Global State Contamination)

### 3.1 肆意篡改 Session 级事务水位线 (`RecentGlobalDataXmin`)
- **相关代码**:
  - `src/gausskernel/storage/access/ubtree/ubtshrink.cpp`: 行 494-498, 1015-1019, 1188-1192
- **代码行为**:
  ```cpp
  TransactionId oldestXmin = GetOldestXminForUndo(&recycleXmin);
  if (TransactionIdIsValid(recycleXmin)) {
      u_sess->utils_cxt.RecentGlobalDataXmin = recycleXmin;
  } else if (TransactionIdIsValid(oldestXmin)) {
      u_sess->utils_cxt.RecentGlobalDataXmin = oldestXmin;
  }
  ```
- **核心原则警告 (Unacceptable Pattern)**:
  `RecentGlobalDataXmin` 是内核中用来判定元组可见性、Undo 链回收和快照有效性的全局关键变量。它的推进由事务管理器（Transaction Engine）和全局水位心跳统一维护。
  一个底层的索引维护函数（Shrink）**绝对不能在局部逻辑中直接覆盖修改 Session 的全局变量**！
  这种修改会产生难以追踪的副作用（Side-effects），可能导致同一 Session 在执行完 Shrink 后，后续的查询采用被意外推进的水位线，引发严重脏读或 Undo 悬空引用。
  **正确方案**：必须将 `oldestXmin` 作为局部只读参数在调用栈中显式传递。

---

### 3.2 级联循环中的非收敛与雪崩风险 (Compaction Thrashing)
- **相关代码**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` (`UBTreeShrink`)
- **代码行为**:
  ```cpp
  int migrationRounds = 0;
  while (stats->migratedBlocks > 0 && migrationRounds < 10) {
      ...
      UBTreeMigratePages(rel, stats, isOnline);
      migrationRounds++;
      UBTreeShrinkCheckInternal(rel, stats, maxPages, costRatio);
      ...
  }
  ```
- **权衡核算 (Trade-off & Regression Risk)**:
  在在线高并发负载下，下层空闲页的腾挪插入可能引发下层内部节点的重新分裂，进而分配新的尾部物理块。此时写死 10 轮循环可能会导致系统在尾部剧烈颠簸（Thrashing），消耗大量 I/O 和 CPU，而最终物理截断却因水位线漂移而失败（Abort）。缺乏自适应放弃机制和清晰的资源配额管控。

---

## 4. 改进路线图 (Required Refactor Roadmap)

如果要使该特性达到进入生产主干的代码质量，必须完成以下重构：

| 优先级 | 缺陷领域 | 重构方案与行动项 |
| :--- | :--- | :--- |
| **P0** | **加锁协议重构** | 废黜自顶向下加写锁的危险模式。参考 `_bt_pagedel` 的两阶段协议：采用自底向上获取锁；如果父节点发生变更或兄弟节点无法非阻塞锁定，立即释放所有锁重新定位，绝不跨层级反向持有写锁。 |
| **P0** | **WAL 一致性补齐** | 引入专用的 `XLOG_UBTREE2_URQ_PURGE` 日志，记录 `targetMaxBlock` 的物理截断水位线，确保 Standby 节点在回放时同步剔除失效的 URQ 空闲块。 |
| **P0** | **Pin-count 截断保护** | 在 `RelationTruncate` 之前，必须加入全局 Buffer Pool 检查（或强制与 ProcArray 活跃扫描器握手），确保待截断物理块的 Pin-count 严格归零，杜绝 `read beyond EOF`。 |
| **P1** | **全局状态解耦** | 彻底移除对 `u_sess->utils_cxt.RecentGlobalDataXmin` 的直接赋值，所有快照与回收可见性计算均通过局部参数传递。 |
| **P1** | **WAL 负载轻量化** | 避免对 `newBuf` 强制整页写入（除非处于 Checkpoint 后的首次写入场景），将多块操作分解为幂等的有序状态机，减轻备机并行重放的同步停顿。 |

---

## 5. 结语 (Conclusion)

UBTree 在线物理收缩是一项极具生产价值的特性，但底层存储引擎的审查准则是：**数据正确性与崩溃恢复能力是一票否决项**。
建议作者退回当前补丁，严格对照 PostgreSQL / openGauss 的并发与恢复模型，重构锁协议与 WAL 设计后重新提交 RFC。
