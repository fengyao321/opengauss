# UBTree URQ 回收队列驱动紧凑度分析与定向页迁移设计方案

---

## 1. 背景与问题诊断

### 1.1 历史版本的空间回收瓶颈
在 UBTree 早期定向页迁移（Phase 3 Targeted Migration）实现中，针对 100K 行数据尾部删除 80% 的场景（场景 1），成功实现了 79.3% 的空间回收。但在以下高频重度膨胀场景中，空间回收表现不理想：
1. **场景 2 (500K 行，删除 90%)**：物理大小保持在 14 MB (初始 15 MB)，空间回收率接近 0%；
2. **场景 4 (1M 行，删除 95%)**：物理大小保持在 30 MB (初始 30 MB)，仅释放了 262 kB。

### 1.2 根本原因剖析
经过内核代码深入调试与执行路径追踪，确认根本原因如下：
1. **低位盲目线性扫描失效**：
   - 早期 `lowScan` 采用自块号 1 向前的线性扫描，用于探测低位可复用块。
   - 在 `DELETE WHERE id > 50000` 场景中，低位物理块（如 Block 1..400）全部存储未被删除的活跃元组（`id <= 50000`），未发生任何删除，因此 `lowScan` 在这些块中找不到任何空页。
2. **URQ 盲目分配与未消费导致的死循环**：
   - 依赖 `UBTreeGetAvailablePage` 分配空页，当其内部探测到块号大于目标截断水位线 `targetMaxBlock` 的页面时，仅执行 `continue` 放弃而不从 URQ 页面中移除该槽位；
   - 随后的 50 次重试全部重复读取到同一个高位块，最终导致页面分配失败（返回 `InvalidBlockNumber`），触发安全降级退出，未能完成尾部活跃页搬迁。
3. **半死页（Half-Dead Page）阻断尾部截断**：
   - VACUUM 清理死元组后，部分页面可能处于 `P_ISHALFDEAD` 状态（已被逻辑标记删除但尚未从父节点或兄弟链表中物理摘除）；
   - 尾部截断扫描探测到半死页时，因其既非完全空页也非普通叶子页而提前终止，导致整段尾部无法物理截断。

---

## 2. 总体架构设计与核心机制

针对上述痛点，设计了 **URQ 回收队列驱动的紧凑度分析与确定性定向迁移方案**，整体流程如下：

```
+-----------------------------------------------------------------------------------------+
| Step 1: URQ 空页清单收集与全局升序排序 (UBTreeCollectURQFreeBlocks)                         |
|  - 遍历 RECYCLE_FREED_FORK 与 RECYCLE_EMPTY_FORK                                        |
|  - 依据 RecentGlobalDataXmin 严格校验事务可见性                                          |
|  - 过滤、去重，按 blkno ASC 升序排列 -> 形成精确低位空闲库存池 UBTreeURQInventory           |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
| Step 2: 尾部反向扫描与半死页主动解链 (Tail Backward Scan & Active Unlinking)             |
|  - 从 totalBlocks - 1 向前逆向探测连续空块与尾部待搬迁活跃页 (Victims)                    |
|  - 若遇到 P_ISHALFDEAD 半死页，主动调用 UBTreeUnlinkHalfDeadPage 完成物理解链并加入空闲池   |
|  - 若遇到非空活跃页，若其块号高于理论截断边界，则将其纳入 Victim 待搬迁清单               |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
| Step 3: 定向一一映射与成本收益评估 (Target Mapping & Cost-Benefit Analysis)              |
|  - 确定目标截断边界 targetMaxBlock                                                      |
|  - 将尾部活跃页 (Victims) 由高到低与 URQ 库存中 < targetMaxBlock 的最低空页进行一一匹配   |
|  - 校验迁移成本比 (VictimCount / FreedGain <= costRatio)，满足时执行收缩                  |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
| Step 4: 在线定向搬迁与 URQ 槽位原位清理 (Targeted Migration & In-place Slot Removal)      |
|  - UBTreeMigrateOnePage 按照预分配的目标空块 targetFreeBlk 进行物理迁移与拓扑修复        |
|  - 记录原子 5-Buffer WAL 日志 (XLOG_UBTREE2_SHRINK_MOVE_LEAF)                            |
|  - 临界区外直接调用 RemoveOneItemFromPage 将消耗的 URQ 插槽剔除，避免重复读取              |
+-----------------------------------------------------------------------------------------+
                                             |
                                             v
+-----------------------------------------------------------------------------------------+
| Step 5: 微秒级锁升级物理截断 (Microsecond Lock Escalation & Relation Truncate)          |
|  - 获取瞬时 AccessExclusiveLock                                                          |
|  - 调用 RelationTruncate(rel, targetMaxBlock) 物理截断文件                              |
|  - 立即释放 AccessExclusiveLock，完成高空间回收率在线收缩                                  |
+-----------------------------------------------------------------------------------------+
```

---

## 3. 关键数据结构与函数实现

### 3.1 URQ 清单数据结构 (`UBTreeURQInventory`)
```c
typedef struct UBTreeFreeBlockEntry {
    BlockNumber blkno;
    BlockNumber queueBlk;
    OffsetNumber offset;
    bool isFreedFork;
} UBTreeFreeBlockEntry;

typedef struct UBTreeURQInventory {
    UBTreeFreeBlockEntry *entries;
    int count;
    int capacity;
} UBTreeURQInventory;
```

### 3.2 URQ 收集与排序 (`UBTreeCollectURQFreeBlocks`)
- 依次读取 `RECYCLE_FREED_FORK` 与 `RECYCLE_EMPTY_FORK` 的物理页面；
- 校验页面是否有效，检查记录元组对应事务是否全局已提交（`TransactionIdPrecedes(entryXid, RecentGlobalDataXmin)`）；
- 将满足可见性的候选空闲块记录至动态数组，使用 `qsort` 按照 `blkno` 升序排列，并进行块号去重。

### 3.3 半死页主动解链 (`UBTreeUnlinkHalfDeadPage`)
在 `UBTreeShrinkCheckInternal` 尾部逆向扫描阶段：
```c
if (P_ISHALFDEAD(opaque)) {
    /* 主动解链该半死页面，将其转为完全可截断的空页面 */
    bool rightsib_empty = false;
    UBTreeUnlinkHalfDeadPage(rel, buf, &rightsib_empty, NULL);
    /* 成功解链后该块被视为完全空闲块，继续向前扫描 */
    freeTailBlocks++;
    continue;
}
```

### 3.4 原位 URQ 槽位清理与定向分配
在 `UBTreeMigrateOnePage` 中直接使用预选定的 `targetFreeBlk` 初始化新页面并搬迁数据。在事务提交且离开临界区后，根据记录的 `targetQueueBlk` 与 `targetOffset`，对 URQ 页面申请写锁并调用 `RemoveOneItemFromPage` 物理移除已使用的槽位，彻底消除重试盲区。

---

## 4. 验证与性能实测收益

在集成 URQ 驱动紧凑度算法后，对 4 大典型场景进行了全量基准压测：

### 4.1 核心测试指标对比

| 测试场景 | 数据模式 | 收缩前物理大小 | 优化前收缩后 | **优化后收缩后 (URQ驱动)** | 空间回收率 | 执行耗时 | 提速 (vs VACUUM FULL) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **场景 1** | 100K 行，删 80% | 3096 kB (387 块) | 640 kB | **640 kB** (80 块) | **79.3%** | **7.75 ms** | **24.6x** |
| **场景 2** | 500K 行，删 90% | 15 MB (1932 块) | 14 MB (失败) | **3288 kB** (411 块) | **78.7%** | **22.91 ms** | **8.5x** |
| **场景 3** | 200K 行，散列删 50% | 6200 kB (775 块) | 6200 kB | **6200 kB** (775 块) | 0% (安全跳过) | **4.08 ms** | **74.0x** |
| **场景 4** | 1M 行，删 95% | 30 MB (3863 块) | 30 MB (失败) | **3288 kB** (411 块) | **89.4%** | **54.37 ms** | **5.2x** |

### 4.2 结论
1. **空间回收率逼近全量重建**：在 90% 和 95% 极端删除场景下，空间回收率达到 **78.7%** 和 **89.4%**，彻底解决了过去空间无法回收的问题；
2. **毫秒级执行时延**：即使对于 100 万行的大索引，在线物理收缩全流程仅耗时 **54.37 ms**，相比 `VACUUM FULL` 的 280.88 ms 提速 5.2 倍；
3. **零业务中断与零临时空间**：全过程支持业务并发读写，仅物理截断瞬间微秒级升级锁，且不需要像 VACUUM FULL 或 REINDEX 那样占用额外的临时磁盘空间。
