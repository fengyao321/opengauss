# openGauss UBTree 物理在线收缩与定向页迁移特性 (UBTree Physical Online Shrink)

[English](./README.en.md) | 简体中文

---

## 1. 特性背景与技术痛点

在 openGauss 的原位更新引擎（Ustore）中，UBTree（Undo-based B-Tree）作为核心索引结构，支持事务多版本回滚和页面级空间回收（URQ, Undo Recycle Queue）。然而在典型的业务高频更新与批量删除场景下（例如历史数据归档、日志定期清理、高频 DELETE/UPDATE），UBTree 会在物理文件尾部遗留大量已清空或低密度的物理页面，形成严重的**空间膨胀（Index Bloat）**。

传统 openGauss 回收索引物理空间的局限性：
1. **常规 VACUUM**：仅能将死元组清理并将空页登记至回收队列（URQ）供后续插入复用，**无法降低物理文件的高水位线（HWM）**，磁盘空间无法归还操作系统。
2. **VACUUM FULL**：通过重构整表与全量索引物理文件回收空间，但需要对表持有最高级别的 **AccessExclusiveLock**，导致所有并发业务读写被完全阻塞，且磁盘 I/O 和 CPU 开销极大。
3. **REINDEX**：重建整棵 B-Tree 索引，同样需要排他锁并阻塞数据写入，在大表场景下执行耗时极长。

为解决上述痛点，openGauss 实现了 **UBTree 物理在线收缩与目标页定向迁移技术（`gs_ubtree_shrink`）**，在允许业务高并发读写的同时，实现毫秒级物理文件截断与空间归还。

---

## 2. 核心架构与设计方案

### 2.1 URQ 回收队列驱动的紧凑度分析与定向映射（URQ-Driven Compaction & Target Mapping）
收缩核心函数 `UBTreeShrinkCheckInternal` 采用创新性的 URQ 回收队列驱动判定算法：
- **URQ 空闲页清单收集与升序编排（`UBTreeCollectURQFreeBlocks`）**：全量遍历 UBTree 的 `RECYCLE_FREED_FORK` 与 `RECYCLE_EMPTY_FORK`，依据 `RecentGlobalDataXmin` 严格过滤已提交全局可见的空闲物理页，去重并按物理块号从小到大（`blkno ASC`）严格排序，建立低位空页库存池；
- **尾部逆向扫描（Tail Backward Scan）与主动解链**：从当前文件最大块向前扫描探测连续可截断物理块。针对处于 `P_ISHALFDEAD` 状态的半死页面，主动调用 `UBTreeUnlinkHalfDeadPage` 完成安全解链，避免其阻断尾部连续空页截断；
- **定向一一映射与搬迁计划**：将尾部需保留搬迁的活跃叶子页（Victim Blocks），由高到低与 URQ 库存池中处于收缩水位线以下（`< targetMaxBlock`）的物理块号最低的空页（Target Free Blocks）进行定向匹配，彻底杜绝盲目分配导致跨越目标水位线的问题；
- **动态成本模型**：支持传入成本收缩比阈值（`costRatio`，默认 0.50）与最大迁移页数限制（`maxPages`，默认 512）。仅当迁移少量活跃页所释放的尾部连续物理空间满足收益期望时，才触发定向迁移与物理截断，避免无效 I/O。

### 2.2 层级感知父节点定位与双向链表拓扑修复（Level-Aware Parent Locator & Topology Repair）
在迁移尾部活跃节点（`UBTreeMigrateOnePage`）时，系统需将活跃页数据搬迁至低位空闲块并重构 B-Tree 拓扑：
- **自顶向下父节点重定位**：针对非右侧叶子节点，通过 High Key 构建 `UBTreeSearch` 获取父级调用栈；针对右侧节点或分支节点，创新性引入**层级感知定位器**（`UBTreeGetEndPoint` + `UBTreeGetStackBuf`），按树层级（Level）扫描父级节点，安全获取并锁定父节点的下行指针（Downlink），彻底解耦对业务 Key 的依赖。
- **严格死锁预防加锁序**：严格遵照 `Parent (BT_WRITE) -> Victim (BT_WRITE) -> Left Sibling (BT_WRITE) -> Right Sibling (BT_WRITE) -> New Target (BT_WRITE)` 的拓扑加锁顺序，杜绝与前台并发事务死锁。
- **指针原子重定向**：在临界区内更新左兄弟的 `btpo_next`、右兄弟的 `btpo_prev` 以及父节点的 `Downlink`，并将旧块标记为 `BTP_DELETED`。

### 2.3 级联多轮收缩循环（Multi-Round Cascading Compaction）
在底层叶子页迁移至低位并释放尾部空间后，上层的部分分支节点可能会因为下行指针被清空而成为新的尾部空页。`UBTreeShrink` 引入多轮收缩迭代循环（最多 10 轮），在每轮迁移完成后自动重新评估树高与高水位线，实现叶子层与多层分支页面的**自底向上级联收缩**。

### 2.4 微秒级锁升级物理截断（Microsecond Lock Escalation & Online Truncate）
- **高并发非阻塞迁移**：在页面分析与定向搬迁阶段，前台业务的 `Index Scan`、`Insert`、`Update` 仅受常规轻量缓冲锁保护，业务无感知。
- **极速物理截断**：仅在调用 `RelationTruncate` 截除物理文件尾部空洞的瞬间，通过微秒级短平快升级至 `AccessExclusiveLock`，同步清理关联 Buffer Pool（`DropRelFileNodeBuffers`），截断完成后立即释放锁，对业务 TPS 影响几乎为零。

### 2.5 原子 WAL 日志与崩溃恢复（Atomic WAL Logging & Crash Recovery）
- 迁移操作通过 `RM_UBTREE2_ID` 资源管理器登记专用的原子日志记录 `XLOG_UBTREE2_SHRINK_MOVE_LEAF`；
- 日志内注册目标新块、被淘汰块、左兄弟节点、右兄弟节点及父节点的完整镜像与修改描述；
- 在数据库发生宕机断电或备机物理复制时，`UBTree2Redo` 模块能够完全幂等重放 B-Tree 拓扑链接修复，确保数据绝对零丢失与 B-Tree 结构物理一致性。

---

## 3. SQL 接口与使用指南

### 3.1 预估检查接口 (`gs_ubtree_shrink_check`)
评估指定索引是否具备物理收缩收益，并输出预估指标：
```sql
-- 基础用法（使用默认配置：maxPages=512, costRatio=0.50）
SELECT gs_ubtree_shrink_check('idx_user_log_id');

-- 自定义调节参数：指定最大允许迁移页数 1024，收缩收益比 0.30
SELECT gs_ubtree_shrink_check('idx_user_log_id', 1024, 0.30);
```
**输出示例**：
```text
TotalBlocks: 387, TargetMaxBlock: 81, FreeTailBlocks: 306, MigratedBlocks: 1
```

### 3.2 物理在线收缩接口 (`gs_ubtree_shrink`)
执行索引物理在线收缩并物理截断文件：
```sql
-- 在线模式执行收缩（默认 isOnline=true, maxPages=512, costRatio=0.50）
SELECT gs_ubtree_shrink('idx_user_log_id');

-- 离线加速模式（持有排他锁，跳过条件锁判断，适用于维护窗口）
SELECT gs_ubtree_shrink('idx_user_log_id', false);

-- 携带动态调优参数执行在线收缩
SELECT gs_ubtree_shrink('idx_user_log_id', true, 1024, 0.40);
```

---

## 4. 测试现状与性能基准

### 4.1 内置回归测试验证
回归测试套件位于 `src/test/regress/sql/test_ubtree_shrink.sql`，执行结果 **100% 通过**（耗时约 `3015 ms`），完整覆盖：
1. **边界安全测试**：空索引、单页索引、仅 Root 节点索引的安全保护与跳过；
2. **连续空页收缩**：尾部批量删除后连续空页的直接物理截断；
3. **定向页搬迁与链路修复**：中间散落活跃页跨层向低位空间迁移及兄弟/父节点拓扑校验；
4. **并发 MVCC 可见性**：在并发事务持有快照与读写操作下，元组查询无错读、漏读、脏读；
5. **参数防御检查**：非法索引 OID、非 UBTree 索引、非法负数/超限参数的防御阻断。

### 4.2 端到端全场景性能压测基准

基准测试脚本详见 `perf.sql`，执行结果记录于 `perf_results_phase1_2.out`：

| 测试场景 | 数据规模与删除模式 | `gs_ubtree_shrink` 耗时 | `VACUUM FULL` 耗时 | `REINDEX` 耗时 | 空间回收效果 (`gs_ubtree_shrink`) | 数据完整性校验 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Scenario 1** | 100K 行，尾部删除 80% | **7.75 ms** | 190.63 ms | 37.73 ms | **3096 kB → 640 kB (-79.3%)** | 100% 准确 (20,000 行) |
| **Scenario 2** | 500K 行，删除 90% | **22.91 ms** | 194.67 ms | 74.14 ms | **15 MB → 3288 kB (-78.7%)** | 100% 准确 (50,000 行) |
| **Scenario 3** | 200K 行，散列交替删除 50% | **4.08 ms** | 301.68 ms | 120.14 ms | 6200 kB → 6200 kB (无尾部空洞安全跳过) | 100% 准确 (100,000 行) |
| **Scenario 4** | 1M 行，极端删除 95% | **54.37 ms** | 280.88 ms | 114.77 ms | **30 MB → 3288 kB (-89.4%)** | 100% 准确 (50,000 行) |

#### 关键性能优势：
- **执行速度极快**：在典型收缩场景下，`gs_ubtree_shrink` 仅需 **7.75 ms**，相比 `VACUUM FULL` 提速 **24.6 倍**，相比 `REINDEX` 提速 **4.9 倍**；
- **查询性能零回退**：在大表收缩后执行范围扫描（Index Only Scan 9001 行），`gs_ubtree_shrink` 扫描用时 **12.17 ms**，与 `REINDEX` 的 11.71 ms 及 `VACUUM` 的 12.96 ms 完全持平；
- **数据物理零损坏**：收缩后通过点查、等值查询、聚合 Count 及范围扫描校验，数据行数及顺序完全一致。

---

## 5. 开源协议 (License)

openGauss 核心代码及本特性完全遵循 **[木兰宽松许可证 第2版 (MulanPSL-2.0)](http://license.coscl.org.cn/MulanPSL2)** 开源发布。

您可以自由复制、使用、修改及分发本特性的所有源代码及相关文档，不论修改与否，但须遵循 MulanPSL-2.0 许可证之相关约定。详情请参阅根目录下 [License](./License) 文件。
