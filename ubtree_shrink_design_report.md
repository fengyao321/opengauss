# UBTree 索引空间收缩（Shrink）方案设计与可行性分析报告

---

## 1. 背景与设计目标

### 1.1 背景
在 openGauss / PostgreSQL 存储引擎中，UBTree（Undo-Based B-Tree）作为支持多版本并发控制（MVCC）的高性能索引结构，配置了**回收队列（Recycle Queue）**机制。回收队列使已标记废弃/空闲的索引 Block 能够被迅速重新分配利用。

然而，在业务经历大规模删除（`DELETE`）或数据生命周期清理后，虽然索引内部产生了大量空闲 Block，但由于操作系统的文件截断（`File Truncate`）只支持从文件尾部（高 Block ID 区域）进行物理裁剪，若索引尾部依然零星占用着活跃数据 Block，整个索引文件的磁盘空间就无法释放。

### 1.2 设计目标
借鉴 Oracle 的 `ALTER INDEX ... SHRINK SPACE` 思想，设计一套适用于 UBTree 的 **在线空间收缩（Index Shrink）机制**：
1. **数据迁移**：识别尾部高 Block ID 的活跃 Leaf / Internal Node，通过页内数据搬迁或分裂（Split）的方式，将其存量数据迁移至头部空闲 Block（优先从 Recycle Queue 获取）。
2. **尾部清空**：递归/逐级更新父节点 Downlink，清空尾部连续的 Block 并将其从 Recycle Queue 中注销。
3. **物理截断**：安全截断文件尾部空闲 Block，将磁盘空间还给操作系统，提升 I/O 效率并降低存储成本。

---

## 2. 可行性分析与核心难点

### 2.1 可行性分析
1. **Recycle Queue 提供头部空闲 Block 分配基础**：Recycle Queue 中记录了大量已释放的空闲 Block ID，可优先筛选出 `BlockID < TargetMaxBlock` 的页面作为迁移目标页。
2. **B-Tree 分裂与合并机制成熟**：UBTree 本身具备完备的 Page Split、Page Merge、Parent Downlink Update 机制，搬迁数据本质上是定向的分裂与重组。
3. **底层 Smgr 支持 Truncate 操作**：openGauss smgr 存储层已原生支持 `smgrtruncate()` 接口，具备尾部物理裁剪能力。

### 2.2 核心技术难点与挑战

#### 难点 1：并发与一致性保障（Concurrent Index Access）
* **挑战**：Shrink 操作进行时，并发的 `IndexScan`、`Insert`、`Delete` 可能正在读取或修改尾部 Block。
* **风险**：若直接搬迁并废弃尾部 Block，并发 Scan 沿着 Downlink 读取可能发生读空、读到非法内存或数据不一致。

#### 难点 2：父节点及祖先节点指针更新（Ancestors Downlink Fix up）
* **挑战**：B-Tree 是层次结构，Leaf Node 搬迁到新 Block 后，必须更新其 Parent Node 中的 Downlink 和 High Key。
* **极度复杂情况**：如果 Parent Node 本身也在尾部需截断区域，则需要自底向上递归搬迁整条路径上的所有 Block。

#### 难点 3：WAL 记录与崩溃恢复（Atomicity & Crash Safety）
* **挑战**：“数据搬迁 + 父节点修改 + 尾部页废弃 + 文件截断” 涉及多页修改，必须保证原子性。
* **风险**：若在物理截断前数据库 Crash，系统重启后重放 WAL 必须保证索引结构的逻辑拓扑完整，不能出现 orphan block 或死锁。

#### 难点 4：UBTree 关联 Undo 机制
* **挑战**：UBTree 的 Tuple 包含 MVCC Undo 信息，涉及未提交事务/长事务对旧 Tuple 的引用。
* **防护**：搬迁时需确保相关 Undo 记录处于已提交且全局可见状态（不可迁移存在未提交事务活跃 Undo 的 Tuple）。

---

## 3. UBTree Shrink 详细技术方案设计

### 3.1 总体执行流程

```
[阶段一: 准备与候选识别] ──> [阶段二: 尾部 Block 数据定向搬迁] ──> [阶段三: 物理收尾与截断]
         │                                    │                                 │
  扫描索引尾部 Block                  从 Recycle Queue 申请              申请 Extension/Exclusive 锁
  确定 TargetMaxBlock                 头部空闲 Block 并写入数据            安全执行 File Truncate
```

---

### 3.2 阶段一：尾部 Block 识别与搬迁候选选取

1. **确定截断目标边界（Target Block Selection）**：
   * 获取当前索引总 Block 数 `TotalBlocks`。
   * 计算期望收缩目标 `TargetMaxBlock`（如物理文件的后 20%~50% 区域）。
2. **识别尾部活跃 Block 集合**：
   * 从 `TotalBlocks - 1` 倒序扫描到 `TargetMaxBlock`。
   * 区分 Block 类型：
     * **全空/已在 Recycle Queue 中**：直接标记待截断。
     * **活跃 Leaf Page / Internal Page**：加入搬迁候选队列 `MigrationList`。

---

### 3.3 阶段二：数据搬迁与索引树更新（Data Migration & Tree Rebalance）

对于 `MigrationList` 中的每一个尾部 Block（记为 `OldBlock`）：

#### Step 1：申请头部空闲 Block
* 从 UBTree Recycle Queue 中取出一个 Block ID（记为 `NewBlock`），保证 `NewBlock < TargetMaxBlock`。
* 若 Recycle Queue 中无可用 Block，则向扩展区申请（必须位于 `TargetMaxBlock` 之前）。

#### Step 2：Tuple 搬迁与页内重组
1. 对 `OldBlock` 加 `ExclusiveLock`，读取其中全部有效 Tuple。
2. 校验 MVCC 状态：确保 Tuple 无活跃未提交事务锁/Undo 冲突。
3. 将 Tuple 拷贝写入 `NewBlock`，并初始化 `NewBlock` 的 Header、High Key、Special Space。

#### Step 3：父节点与兄弟节点 Downlink 更新
1. **加锁顺序**：按照 B-Tree 标准从上到下/自左向右加锁，防止死锁（Lock Coupling）。
2. **更新 Parent**：找到 `OldBlock` 的 Parent Node，将指向 `OldBlock` 的 Downlink 修改为指向 `NewBlock`。
3. **更新 Sibling**：若 UBTree 存在 Leaf 双向链表（Left/Right Link），同步更新 `OldBlock->prev` 的 `next` 指针和 `OldBlock->next` 的 `prev` 指针。

#### Step 4：释放与标记 OldBlock
1. 记 WAL（`WAL_UBTREE_SHRINK_MOVE`），将 `NewBlock` 设为 Valid，`OldBlock` 设为 Dead/Invalid。
2. 将 `OldBlock` 从 Recycle Queue 中彻底清理（标记为待物理截断状态，不可再分配）。

---

### 3.4 阶段三：物理截断与收尾（Physical Truncation）

1. **申请全局排他锁**：
   * 申请索引 Relation 的 `AccessExclusiveLock` 或 `ExtensionLock`，阻止新的扩展与并发写入。
2. **终极安全校验（Sanity Check）**：
   * 再次确认从 `TargetMaxBlock` 到当前文件末尾的所有 Block 均已无任何有效数据与引用指针。
3. **物理文件截断（smgrtruncate）**：
   * 物理裁剪文件：调用 `smgrtruncate(rel, MAIN_FORKNUM, TargetMaxBlock)`。
   * 刷新 Smgr 与 Relation Cache (`rd_smgr` / `relpages`)。
4. **记录 WAL 并释放锁**：
   * 写入 `WAL_UBTREE_TRUNCATE` 记录。
   * 释放排他锁，完成 Shrink 操作。

---

## 4. WAL 日志与崩溃恢复设计

为了保障 ACID 与 Crash Recovery：

1. **迁移原子性日志（`WAL_UBTREE_SHRINK_MOVE`）**：
   * 一条 WAL 需包含：`OldBlock` ID、`NewBlock` ID、Parent Block ID、修改的 Downlink 槽位及 Tuple 数据。
   * **Redo 逻辑**：如果崩溃重启，系统根据 WAL 重新在 `NewBlock` 填充 Tuple 并修正 Parent/Sibling 指针。
2. **截断日志（`WAL_UBTREE_TRUNCATE`）**：
   * 包含截断后的 `TargetMaxBlock` 块数。
   * **Redo 逻辑**：重放 `smgrtruncate`，保证备机（Standby）与主机物理文件大小严格一致。

---

## 5. 触发机制设计：手动触发 vs 被动触发分析与推荐方案

### 5.1 两种触发模式深度对比

| 评估维度 | 手动触发（Explicit Command） | 被动触发（Passive Auto Background） |
| :--- | :--- | :--- |
| **典型代表** | Oracle `ALTER INDEX ... SHRINK SPACE`<br>PostgreSQL `REINDEX / VACUUM FULL` | Autovacuum 后台截断<br>RocksDB Auto-Compaction |
| **系统可控性** | **极高**。DBA 可安排在业务低峰期（如凌晨）执行，避免抢占正常业务资源。 | **较低**。可能在业务高峰期突然触发，造成 CPU、I/O PSL 飙升。 |
| **并发锁风险** | **可预测/可避让**。结合运维窗口，允许短时间的锁等待或轻微阻塞。 | **高风险**。后台线程若在写高并发时申请 Downlink / 截断锁，容易引发事务延迟突增甚至死锁。 |
| **乒乓效应（Ping-Pong）**| **无**。手动评估后再收缩。 | **严重**。刚自动 Shrink 截断了 1GB，几分钟后大量并发 `INSERT` 又迫使文件再次物理 Expansion，带来严重的写放大和文件增长开销。 |
| **运维自动化程度** | 需要人工干预或配置定时任务（Cron）。 | 真正的“自健康/自我管理（Self-Managing）”数据库。 |

### 5.2 核心设计权衡
1. **数据搬迁开销非免费（Not Free）**：Recycle Queue 逻辑回收仅修改指针，极轻量；但 Shrink 涉及真实 Tuple 搬迁、WAL 记录与磁盘 Truncate，属于重度 I/O 操作。
2. **避免频繁物理 Expansion/Truncate 抖动**：自动触发易引起物理扩展与物理裁剪频繁交替的乒乓效应。

### 5.3 推荐分层落地架构（两阶段策略）
* **第一阶段（MVP 阶段）**：**纯手动/显式触发 + 膨胀评估函数**。
  - 提供 DDL / 函数：`ALTER INDEX <name> SHRINK SPACE;` 或 `gs_index_shrink('index_name')`。
  - 提供评估工具：`gs_index_shrink_check('index_name')` 评估物理文件尾部空闲量与预期收益。
* **第二阶段（进阶阶段）**：**分级被动触发（轻量 vs 重量）**。
  - **轻量级被动收缩（Zero-Migration Truncate）**：若尾部节点本身已全空（全在 Recycle Queue），Autovacuum 在扫描后直接调用 `smgrtruncate` 截断（无搬迁开销）。
  - **重量级被动收缩（Data-Migration Shrink）**：仅在严格系统闲置条件（如低高峰期且空缩率 $>40\%$）下，才由后台作业小规模搬迁。

---

## 6. 方案总结与可行性结论

| 维度 | 评价与结论 |
| :--- | :--- |
| **可行性结论** | **完全可行**。基于现有的 UBTree Recycle Queue 和 B-Tree 分裂重组机制，通过自底向上的数据搬迁与 Downlink 修正，可以安全清空尾部物理 Block 并完成截断。 |
| **核心优势** | 1. 物理缩小索引磁盘体积，释放存储空间。<br>2. 提升 Buffer Pool 命中率与顺序扫描效率。 |
| **推荐实施步骤** | **第一阶段**：实现离线/排他锁模式下的 Shrink（粗粒度锁，验证数据搬迁与 Downlink 更新逻辑），采用手动触发 API与评估工具。<br>**第二阶段**：引入细粒度 Lock Coupling 与在线并发控制，实现高并发下的 Online Index Shrink 与分级自动被动收缩。 |
