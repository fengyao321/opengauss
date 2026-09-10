# UBTree 阶段三后续定向搬迁（Targeted Migration & Page Compaction）设计方案

---

## 1. 方案背景与核心目标

### 1.1 现状痛点
当前 UBTree 物理收缩（Phase 3 物理截断期）仅能裁剪**物理文件末尾连续的死块/空块（FreeTailBlocks）**。但在生产高频离散 `DELETE / UPDATE` 场景下：
- 索引文件内部页面变稀疏（Fragmented）；
- 文件尾部通常散落着**少量活跃页（Active Pages）**；
- 只要文件尾部存在 1 个活跃页，物理截断边界就无法前移，导致物理文件体积无法回缩。

### 1.2 核心目标
设计**在线定向页面搬迁（Targeted Migration）机制**：
1. **定向搬迁（Targeted Migration）**：将文件尾部（高水位区）的存活活跃叶子页（Active Leaf Pages），在线迁移到文件头部（低水位区）由 URQ 管理的空闲页或稀疏页中。
2. **拓扑一致与读写无感知**：搬迁过程持有轻量行锁/页面锁，原子修正左右兄弟双向链表与父节点 Downlink，并发 `IndexScan`、`Insert`、`Delete` 正常执行。
3. **物理空间最大化回收**：搬迁后高位全为空/死页，触发微秒级瞬时锁升级物理截断（`RelationTruncate`），使离散删除场景下的磁盘回收率达到与全量重构（`REINDEX`）接近的效果。

---

## 2. 总体架构与数据流图

```
+---------------------------------------------------------------------------------+
| Step 1: 扫描与搬迁规划 (Planning Phase)                                          |
|  - 确定目标压缩水位 TargetWatermark (如预期保留前 60% blocks)                    |
|  - 扫描 TargetWatermark 以上的所有活跃叶子页 -> 形成 Migration Candidate Queue  |
+---------------------------------------------------------------------------------+
                                      |
                                      v
+---------------------------------------------------------------------------------+
| Step 2: 在线定向搬迁循环 (Online Page Migration Loop)                           |
|  For each VictimBlock (> TargetWatermark):                                      |
|    1. 从 URQ 获取一个 < TargetWatermark 的空闲页 NewBlock                        |
|    2. 锁耦合锁定: VictimBlock -> LeftSib -> RightSib -> Parent                   |
|    3. 校验 LSN & Downlink (防并发 Split 竞争)                                    |
|    4. 拷贝元组到 NewBlock，更新 Left/Right 指向与 Parent Downlink                |
|    5. 记录 XLOG_UBTREE_SHRINK_MOVE_LEAF 5-Buffer WAL 原子日志                   |
|    6. 标记 VictimBlock 为 DELETED 并加入回收链表                                 |
+---------------------------------------------------------------------------------+
                                      |
                                      v
+---------------------------------------------------------------------------------+
| Step 3: 微秒级锁升级物理截断 (Lock Escalation & Physical Truncation)            |
|  - 申请短时 AccessExclusiveLock (带超时与退避)                                  |
|  - 清理 URQ 中 >= TargetWatermark 的残余条目                                     |
|  - RelationTruncate(rel, TargetWatermark) 裁剪物理 OS 文件                       |
|  - 释放锁，完成收缩                                                             |
+---------------------------------------------------------------------------------+
```

---

## 3. 核心机制详细设计

### 3.1 锁耦合协议与防死锁设计（Lock Coupling & Deadlock Prevention）

在 B-Tree 中修改一个叶子页的物理位置，需要同时更新：
1. **源节点**：`VictimBlock`（待搬迁的尾部页）
2. **新节点**：`NewBlock`（头部空闲分配页）
3. **左兄弟**：`LeftSibling`（将其 `btpo_next` 从 `VictimBlock` 改为 `NewBlock`）
4. **右兄弟**：`RightSibling`（将其 `btpo_prev` 从 `VictimBlock` 改为 `NewBlock`；若为 `P_RIGHTMOST` 则无右兄弟）
5. **父节点**：`ParentBlock`（将其指向 `VictimBlock` 的 Downlink 和 Key 槽位更新为 `NewBlock`）

#### 加锁与退避协议（数学无死锁保证）：
- **加锁顺序**：严格按照 `VictimBlock (Exclusive)` $\rightarrow$ `LeftSibling (Conditional Lock)` $\rightarrow$ `RightSibling (Conditional Lock)` $\rightarrow$ `ParentBlock (Conditional Lock)`。
- **全条件非阻塞获取**：对 `LeftSibling`、`RightSibling` 和 `ParentBlock` 的加锁**全部使用 `ConditionalLockBuffer`**（绝不使用阻塞式的 `_bt_getbuf(rel, blk, BT_WRITE)`）。
- **主动退避与重试**：若任一关联 Buffer 获取锁失败（可能存在并发扫描、写入或 Split），立即成对释放已持有的全部 Buffer 锁，休眠随机时间（2~5ms）后重试或跳过该页。通过破坏死锁的“请求与保持（Hold and Wait）”条件，彻底杜绝死锁。

---

### 3.2 右边界页（`P_RIGHTMOST`）与普通叶子页的安全搬迁

针对此前 `P_RIGHTMOST` 阻碍尾部截断的关键瓶颈：
1. **常规叶子页搬迁**：
   - 拷贝全部元组及 Special 结构到 `NewBlock`；
   - 更新 `LeftSibling->btpo_next = NewBlock`；
   - 更新 `RightSibling->btpo_prev = NewBlock`；
   - 更新 `ParentBlock` 对应 Downlink 为 `NewBlock`。
2. **右边界页（`P_RIGHTMOST`）搬迁**：
   - `NewBlock` 继承 `P_RIGHTMOST` 属性，设置 `newOpaque->btpo_next = P_NONE`；
   - 更新 `LeftSibling->btpo_next = NewBlock`；
   - 更新 `ParentBlock` 对应 Downlink 为 `NewBlock`；
   - 树整体依然拥有合法的右无穷大边界，但物理承载块成功由文件末尾转移至头部。

---

### 3.3 崩溃恢复与原子 5-Buffer WAL 日志

为了保证在搬迁任意中间时刻发生系统宕机（Crash）时，B-Tree 拓扑强一致且备机可精确重放：

#### (1) WAL 记录定义
在 `RM_UBTREE2_ID`（UBTree2）中分配专用操作码：
`#define XLOG_UBTREE2_SHRINK_MOVE_LEAF 0x50`

```c
typedef struct xl_ubtree2_shrink_move_leaf {
    BlockNumber victimBlk;
    BlockNumber newBlk;
    BlockNumber leftBlk;
    BlockNumber rightBlk;
    BlockNumber parentBlk;
    OffsetNumber parentOff;
    bool isRightMost;
} xl_ubtree2_shrink_move_leaf;
```

#### (2) 原子多 Buffer 注册
在单次 WAL 写入中原子注册 5 个 Buffer：
- Buffer 0: `NewBlock`（`REGBUF_WILL_INIT`，包含整页数据拷贝）
- Buffer 1: `VictimBlock`（`REGBUF_STANDARD`，标记为 `BTP_DELETED`）
- Buffer 2: `LeftSibling`（`REGBUF_STANDARD`，若存在则更新 `btpo_next = NewBlock`）
- Buffer 3: `RightSibling`（`REGBUF_STANDARD`，若非 `P_RIGHTMOST` 则更新 `btpo_prev = NewBlock`）
- Buffer 4: `ParentBlock`（`REGBUF_STANDARD`，更新 Downlink 指针）

#### (3) 幂等 Redo 重放实现（`UBTree2XlogShrinkMoveLeaf`）
- 依据各 Buffer 的 `PageGetLSN(page)` 独立判定是否重放；
- 备机根据该日志原子完成 5 个页面的更新，与主机拓扑保持严格强一致。

---

### 3.4 搬迁阈值与防抖调度（Anti-Jitter & Autonomics）

为了防止频繁搬迁和截断造成的 I/O 抖动（乒乓效应）：
1. **搬迁比例阈值**：仅当尾部活跃页搬迁代价合理时触发，例如：
   $$\frac{\text{VictimPages}}{\text{FreeTailGain}} \le 0.3$$
   （即搬迁不超过 30 个活跃页能换取至少 100 个物理页的截断空间）。
2. **批量上限保护**：单次收缩操作限制最大搬迁页面数（如单轮最多搬迁 256 页），支持超大索引渐进式平滑收缩，避免单次事务长耗时。

---

## 4. 接口与统计增强规划

### 4.1 SQL 接口扩展
```sql
-- 增强 gs_ubtree_shrink_check：输出可搬迁页数与预期收益
SELECT * FROM gs_ubtree_shrink_check('idx_name');
-- 输出: TotalBlocks: 1000, TargetMaxBlock: 600, FreeTailBlocks: 200, MigratedBlocks: 45

-- 增强 gs_ubtree_shrink：支持指定最大搬迁页面数与压缩比
SELECT gs_ubtree_shrink('idx_name', is_online => true, max_migrate_pages => 256);
```

### 4.2 GUC 控制参数
* `ubtree_shrink_migrate_limit`: 单次在线收缩允许搬迁的最大叶子页上限（默认 512）。
* `ubtree_shrink_ratio_threshold`: 触发定向搬迁的最小收益比阈值（默认 20%）。
