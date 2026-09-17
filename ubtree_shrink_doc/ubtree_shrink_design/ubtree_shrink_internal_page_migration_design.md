# UBTree 在线物理收缩：非叶子内部节点搬迁设计方案
## （UBTree Shrink: Deterministic Internal Page Migration Design）

> **设计模块**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp`  
> **文档版本**: v1.0 (Architecture Review & Redesign)  
> **适用场景**: 高并发大表、FIFO 队列表、分区滚动清理、时间序列归档等长期运行场景中高位非叶子节点阻塞文件物理截断的痛点解决。

---

## 一、 背景与现实痛点（Motivation & Problem Statement）

### 1.1 现实业务场景中的“高位非叶子节点阻塞”
在 openGauss / PostgreSQL 的 Lehman-Yao B-Link 树索引中，索引物理文件的扩张和页分配遵循追加式动态申请逻辑：
1. **业务膨胀期**：表经历高并发大规模写入，B-Tree 发生大量页分裂（Split），导致文件物理规模大幅扩大（例如扩展至 100,000 个物理页，Block 0 ~ 99,999）。在此过程中，树高度增加或中间层分裂，**必然会有部分非叶子内部节点（Internal Page，Level $\ge 1$）被分配在高物理块号区域（如 Block 95,000）**。
2. **数据淘汰与清理期**：随后的业务周期中，历史数据被清理（如 FIFO 队列表按时间滑动删除老数据、大批量 DELETE），大量叶子页变为死页并被两阶段 VACUUM 回收进空闲回收队列（URQ）。
3. **物理截断困境（Shrink Bottleneck）**：
   - 物理截断（`ftruncate`）是从文件物理尾部向头部单向推进的。
   - 现有的 `gs_ubtree_shrink` 仅支持叶子节点（Leaf Page, Level 0）搬迁，对非叶子节点采取“硬拦截保护”；
   - **即便尾部 99% 的叶子节点已经全部被清空或搬迁至低位，只要有一个 Level 1 内部节点残留在 Block 95,000，物理截断线（`targetMaxBlock`）就必须被强行阻挡在 95,001 之后**！
   - **结果**：原本可以收缩数十 GB 的物理空间，由于一个或几个非叶子节点的存在，导致**实际物理截断空间为 0 字节**，严重制约了 `gs_ubtree_shrink` 的生产实用价值。

---

## 二、 前序方案 Review 与盲区深度剖析（Review of Prior Traps）

在前期的初步构想中，直觉认为“内部节点与叶子节点类似，直接提取 Key、调用 `UBTreeSearch` 搜索父节点并搬迁即可”。但经过深入分析 openGauss 存储引擎内核实现，发现存在 **4 大致命陷阱**：

### 陷阱 1：父节点寻址的“Key 构造假设”完全破产
* **上版设想**：从 `victimPage` 提取 High Key 或 Offset 2 Tuple 作为搜索 Key，调用 `UBTreeSearch` 定位父节点。
* **致命现实**：
  1. **最右页无 High Key**：如果被搬迁的内部节点是同层最右节点（`P_RIGHTMOST`），它根本没有 `P_HIKEY`（概念上为 $+\infty$）。
  2. **Offset 2 是负无穷占位**：在 Lehman-Yao 内部节点中，Offset 2 的首个数据项是一个无具体 Key 值的 Downlink（代表 $-\infty$）。对它调用 `UBTreeMakeScanKey` 会构造出非法 Key，导致搜索失真或内存异常。
  3. **`UBTreeSearch` 语义不匹配**：`ubtsearch.cpp` 中的 `UBTreeSearch` 硬编码了 `if (P_ISLEAF(opaque)) break;`，它专为查找叶子节点设计，无法在指定的中间内部层（Level $L+1$）停止。

### 陷阱 2：根节点（Root）的“进程本地缓存（`rd_amcache`）”越界读风险
* **上版设想**：若高位块是 Root 节点，直接搬迁并在 Metapage 中修改 `btm_root`。
* **致命现实**：
  - openGauss 每个并发 Backend 会话在本地内存中缓存了 `rel->rd_amcache`（记录了 `btm_root` 和 `btm_fastroot` 的物理块号）。
  - 在线收缩（Online Shrink）不支持全库广播强刷所有并发后端的本地私有内存。
  - 一旦把 Root 节点搬走并立即 `ftruncate`，其它 Session 读取本地缓存的旧 Root 块号，会立即报出：
    `could not read block ... read only 0 of 8192 bytes` 并引发事务回滚。

### 陷阱 3：上下层级交叉乱序搬迁引发的拓扑断裂与死锁
* **上版设想**：从后往前扫，遇到存活页（Leaf 或 Internal）直接申请空槽搬迁。
* **致命现实**：
  - 若索引尾部同时存在 Level 0 叶子页和 Level 1 内部页，若先搬迁 Level 1 内部页，其在 Level 2 的 Downlink 尚未持久化，其下的子叶子页又在并发移动，会导致父子两级互相等待死锁，且破坏 Lehman-Yao 崩溃恢复（Redo）的前置条件。

### 陷阱 4：忽视了底层 WAL Redo 的固有通用性
* **源码事实**：查阅 `ubtxlog.cpp` 中 `UBTree2XlogShrinkMoveLeaf` 的实现：
  ```c
  /* 0. Restore new leaf page */
  char *datapos = XLogRecGetBlockData(record, 0, &datalen);
  if (datalen == BLCKSZ) {
      errno_t rc = memcpy_s(page, BLCKSZ, datapos, BLCKSZ);
      ...
  ```
  底层 Redo 本质上是**整块 8192 字节物理覆盖**，并维护左右邻居的 `btpo_next` / `btpo_prev` 指针。**底层 WAL 协议天然支持任意层级（Leaf 或 Internal）的物理页平移！** 真正缺失的是**上层控制流、父节点确定性寻址与分层执行协议**。

---

## 三、 重新设计的核心准则（Core Design Axioms）

基于上述 Review，确立以下 **4 条不可逾越的核心设计准则**：

```text
┌────────────────────────────────────────────────────────────────────────┐
│ 准则 1：Root 坚守底线原则 (Root Immutability)                           │
│        Root 节点永不物理搬迁，截断线永远满足 targetMaxBlock > rootBlk。  │
├────────────────────────────────────────────────────────────────────────┤
│ 准则 2：非根内部节点全量可搬 (Non-Root Internals Fully Migratable)       │
│        1 <= Level < RootLevel 的所有内部节点，全部纳入受害页管辖。     │
├────────────────────────────────────────────────────────────────────────┤
│ 准则 3：确定性链表匹配取代模糊 Key 搜索 (Deterministic Downlink Search) │
│        从 Level L+1 层最左页遍历匹配 Downlink == victimBlk，100% 准确。│
├────────────────────────────────────────────────────────────────────────┤
│ 准则 4：严格自底向上推进 (Strict Bottom-Up Level-by-Level)             │
│        先清空高位 Level 0，再搬迁 Level 1，最后递推至最高内部层。       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 四、 详细架构设计与执行协议（Architecture & Protocol）

### 4.1 拓扑演化架构图

```text
【初始状态：高位残留 Internal Page 695 阻塞截断】
Level 2 (Parent):   [ Block 10 ] ──downlink──> (指向 Block 695)
                         │
Level 1 (Internal): [ Block 695 (高位) ] ──downlink──> [ Leaf 770 (高位) ]
----------------------------------------------------------------------
【第一步：清空 Level 0 (叶子层先行沉降)】
Level 0:            [ Leaf 770 ] ──搬迁至──> [ Free Slot 20 (低位) ]
                    (Level 1 Block 695 中的 Downlink 更新为 20)
----------------------------------------------------------------------
【第二步：搬迁 Level 1 内部节点】
Level 1:            [ Block 695 ] ──搬迁至──> [ Free Slot 21 (低位) ]
                    1. 复制 8KB 数据至 Block 21 (保持 btpo.level = 1)
                    2. 原 Block 695 标记 BTP_DELETED, btpo_next = 21 (Lehman-Yao 转发通道)
                    3. 在 Level 2 确定性扫描，将指向 695 的 Downlink 修正为 21
----------------------------------------------------------------------
【第三步：安全物理截断】
截断安全线:          targetMaxBlock 划定在 Block 22！
物理截断:            ftruncate 砍掉 Block 22 ~ 774，完美回收空间！
```

---

### 4.2 五阶段执行协议（Five-Phase Execution Protocol）

#### 阶段 1：边界扫描与受害节点分层普查（Classification Sweep）
- 从物理文件尾部向前扫描（`currentBlk = totalBlocks - 1`）：
  - 若为 `Level 0` 且存活：记录入 `LeafVictims`；
  - 若为 `1 <= Level < RootLevel` 且存活：记录入 `InternalVictims[level]`；
  - 若遇到 `P_ISROOT`：立即作为不可逾越的硬边界终止探测。
- 收集低位 URQ 回收队列可用空洞，校验容量平衡：
  $$\text{CapacityCheck}: \quad \text{AvailableSlotsBelowCutoff} \ge |\text{LeafVictims}| + \sum_{l=1}^{\text{RootLevel}-1} |\text{InternalVictims}[l]|$$

#### 阶段 2：严格自底向上流水线（Strict Bottom-Up Execution）
严禁交叉混合搬迁，必须按层级由低至高逐步推进：

##### Step 2.1：Level 0 叶子层全量搬迁
- 将所有处于截断线之上的活跃叶子节点搬迁至低位空洞；
- 按照既有成熟的 `UBTreeMigrateOnePage` 流程更新对应 Level 1 内部节点的 Downlink。
- **状态保证**：此步骤完成后，拟截断区域上方**不再有任何存活的叶子节点**，只剩孤立的内部节点。

##### Step 2.2：逐层清空高位 Level 1 ~ Level $N-1$ 内部节点
对于每一层内部节点 $L$（从 1 到 $\text{RootLevel}-1$）：
1. **同层三页原子替换（Horizontal Relink & Page Copy）**：
   - 顺序获取三把同层写锁：`leftBuf(BT_WRITE)` -> `victimBuf(BT_WRITE)` -> `rightBuf(BT_WRITE)`；
   - 将 `victimPage` 完整 8KB 物理二进制拷贝到 `newBuf`，**保持 `newOpaque->btpo.level = L` 不变**；
   - 更新同层邻居指针：`left->btpo_next = newBlk`，`right->btpo_prev = newBlk`；
   - 建立 Lehman-Yao 并发转发链路：
     ```c
     victimOpaque->btpo_flags |= BTP_DELETED;
     victimOpaque->btpo_next = newBlk;
     ```
   - 刷脏并记录 WAL（复用 `XLOG_UBTREE2_SHRINK_MOVE_LEAF`）；
   - **立即释放 Level $L$ 的所有同层写锁**。
2. **上层确定性 Downlink 修复（Deterministic Parent Downlink Update）**：
   - **确定性遍历算法**：
     - 从 Level $L+1$ 层的最左节点出发（通过 `UBTreeGetEndPoint(rel, L + 1, false)` 获取）；
     - 顺着 `btpo_next` 链表向右遍历每个父节点页面；
     - 遍历页内每个 Tuple，比对 `UBTreeTupleGetDownLink(itup) == victimBlk`；
     - 一旦匹配，获取该父页写锁，将其 Downlink 修改为 `newBlk`：
       ```c
       UBTreeTupleSetDownLink(parentItup, newBlk);
       MarkBufferDirty(parentBuf);
       ```
     - 写入 `XLOG_UBTREE2_SHRINK_UPDATE_PARENT` WAL 记录；
     - 释放父页写锁并退出。
   - **子节点零影响**：内部节点搬迁过程中，其下属的所有子节点（Level $L-1$）**无需任何物理修改或加锁**。

#### 阶段 3：元页 Fastroot 降级防御（Fastroot Defense）
- 在所有节点沉降完成后，检查元页：
  ```c
  if (metad->btm_fastroot >= targetMaxBlock) {
      metad->btm_fastroot = metad->btm_root;
      metad->btm_fastlevel = metad->btm_level;
      MarkBufferDirty(metabuf);
  }
  ```
- 本地失效 `rel->rd_amcache = NULL`。

#### 阶段 4：边界指针闭合（Boundary Sibling Closure）
- 调用 `UBTreeCloseBoundarySiblingsBeforeTruncate(rel, targetMaxBlock)`，对所有跨越截断线的 `btpo_next` 置为 `P_NONE`，杜绝任何并发扫描越界探查已截断块。

#### 阶段 5：轻量升级锁与物理截断（Safe File Truncation）
- 在微秒级 `AccessExclusiveLock` 保护下，执行 `UBTreeCheckBuffersPinned` 确保保留区以上无并发 Pin，调用 `RelationTruncate(rel, targetMaxBlock)` 物理释放磁盘空间。

---

## 五、 并发正确性与 Lehman-Yao 一致性证明

| 并发场景 | 潜在风险 | 方案防御机制 | 结果 |
| :--- | :--- | :--- | :--- |
| **并发读正在访问旧内部节点** | 查询拿到 `victimBlk`，正在准备读取 | 旧块保留并标记 `BTP_DELETED`，`btpo_next = newBlk`。并发读沿 `btpo_next` 跳转至新块，继续路由。 | **无任何 Tuple 丢失** |
| **并发查询跨截断边界** | 读操作试图探查已被物理删除的块 | 物理截断前执行全量闭合，跨界指针全被置为 `P_NONE`；且截断在 `AccessExclusiveLock` 下执行。 | **零越界读 Panic** |
| **父节点发生并发分裂** | 遍历父层寻找 Downlink 时父页 Split | 遍历算法沿父层 `btpo_next` 右移（`_bt_moveright`），保证 100% 能找到下移的 Downlink。 | **确定性命中父项** |
| **进程本地 Root 缓存** | 外部 Session 持有旧 `rd_amcache` | Root 节点作为硬底线坚决不搬迁，`btm_root` 块号永久固定有效。 | **零会话崩溃** |

---

## 六、 伪代码实现蓝图（Code Blueprint）

### 6.1 确定性父节点 Downlink 查找
```c
static bool UBTreeFixInternalParentDownlink(Relation rel, BlockNumber victimBlk, BlockNumber newBlk, uint16 victimLevel)
{
    uint16 parentLevel = victimLevel + 1;
    Buffer pbuf = UBTreeGetEndPoint(rel, parentLevel, false);
    if (!BufferIsValid(pbuf)) {
        return false;
    }

    bool updated = false;
    while (BufferIsValid(pbuf)) {
        LockBuffer(pbuf, BT_WRITE);
        Page page = BufferGetPage(pbuf);
        UBTPageOpaqueInternal opaque = (UBTPageOpaqueInternal)PageGetSpecialPointer(page);
        OffsetNumber maxoff = PageGetMaxOffsetNumber(page);

        for (OffsetNumber off = P_FIRSTDATAKEY(opaque); off <= maxoff; off = OffsetNumberNext(off)) {
            ItemId item = PageGetItemId(page, off);
            IndexTuple itup = (IndexTuple)PageGetItem(page, item);
            if (UBTreeTupleGetDownLink(itup) == victimBlk) {
                START_CRIT_SECTION();
                UBTreeTupleSetDownLink(itup, newBlk);
                MarkBufferDirty(pbuf);
                if (RelationNeedsWAL(rel)) {
                    xl_ubtree2_shrink_update_parent pxlrec;
                    pxlrec.parentBlk = BufferGetBlockNumber(pbuf);
                    pxlrec.parentOff = off;
                    pxlrec.oldChildBlk = victimBlk;
                    pxlrec.newChildBlk = newBlk;

                    XLogBeginInsert();
                    XLogRegisterData((char *)&pxlrec, SizeOfUBTree2ShrinkUpdateParent);
                    XLogRegisterBuffer(0, pbuf, REGBUF_STANDARD);
                    XLogRecPtr recptr = XLogInsert(RM_UBTREE2_ID, XLOG_UBTREE2_SHRINK_UPDATE_PARENT);
                    PageSetLSN(page, recptr);
                }
                END_CRIT_SECTION();
                updated = true;
                break;
            }
        }

        BlockNumber nextBlk = opaque->btpo_next;
        _bt_relbuf(rel, pbuf);

        if (updated || nextBlk == P_NONE) {
            break;
        }
        pbuf = ReadBuffer(rel, nextBlk);
    }
    return updated;
}
```

---

## 七、 改造前后预期效益对比

| 评价维度 | 现有实现（保护非叶子节点） | 重新设计方案（分层确定性内节点搬迁） |
| :--- | :--- | :--- |
| **场景 5 (FIFO 队列淘汰)** | 被 Block 695 拦截，**回收率 0%** | **Block 695 沉降至低位，回收率 > 95%** |
| **场景 2 (尾部大量删除)** | 尾部残留内节点导致截断受阻 | **彻底打通截断路径，空间零浪费** |
| **父节点定位可靠性** | 易崩溃（Key 构造失败/最右页无 High Key） | **100% 确定性链表匹配，永不失真** |
| **并发稳定性** | 易因 Root 缓存悬垂导致 Session Crash | **Root 坚守硬底线，零 Cache 击穿** |
| **代码与 WAL 复用度** | 需重写 WAL 协议 | **完全复用现有全页覆盖 WAL，侵入极小** |
