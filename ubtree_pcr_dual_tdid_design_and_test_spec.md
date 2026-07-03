# UBTree PCR 双 TD ID 架构改造与性能测试方案

本文档提供了将 openGauss UStore 的 UBTree PCR 页面格式从传统的“单 TD ID”重构为“双 TD ID”的详细实现方案，以及与之配套的性能对比测试方案。

---

## 第一部分：双 TD ID 实现方案

### 1. 核心设计思想
双 TD ID 设计通过在 32-bit 的行指针（`UBTreeItemIdData`）中**同时且独立保留**插入事务（`xmin_td_id`）与删除事务（`xmax_td_id`）对页面事务目录（TD Slots）的引用，实现以下设计目标：
- **消除写放大与覆盖冲突**：删除元组时，不再覆盖插入事务的 TD ID，直接原地写入 `xmax_td_id`，保证页面自包含。
- **$O(1)$ 可见性判定**：读事务在判定已被删除或 TD 槽已被复用的元组的可见性时，可以通过双 TD ID 直接在页面内做快速通道判定，或者直接定位到当前元组关联的最新那一条 Undo 记录，避免遍历整个 Block 的 Undo 链。
- **零额外页面空间开销**：行指针大小仍保持为 32-bit。

---

### 2. 详细数据结构设计

#### 2.1 行指针结构修改
修改 `ubtreepcr.h` 中的 `UBTreeItemIdData` 如下：

```diff
-typedef struct UBTreeItemIdData {
-    unsigned lp_off : 15,         /* offset to tuple */
-        lp_flags : 2,             /* state of line pointer */
-        lp_td_id : 8,             /* unique reference to TD slot */
-        lp_td_invalid : 1,        /* whether TD slot is reused */
-        lp_deleted : 1,           /* whether tuple is deleted */
-        lp_xmin_frozen : 1,       /* whether xmin is frozen */
-        lp_aligned : 4;           /* alignment padding */
-} UBTreeItemIdData;
+typedef struct UBTreeItemIdData {
+    unsigned lp_off : 15,          /* 元组在页面中的偏移量 (0 ~ 32767) */
+             lp_flags : 2,         /* 行指针状态: LP_UNUSED, LP_NORMAL, LP_REDIRECT, LP_DEAD */
+             lp_xmin_td_id : 7,    /* 插入事务的 TD 槽 ID (0 ~ 127) */
+             lp_xmax_td_id : 7,    /* 删除事务的 TD 槽 ID (0 ~ 127) */
+             lp_unused : 1;        /* 预留/对齐 */
+} UBTreeItemIdData;
```

#### 2.2 辅助操作宏定义调整
更新 `ubtreepcr.h` 中的辅助宏，消除对已废弃字段（`lp_td_invalid`、`lp_deleted`、`lp_xmin_frozen`）的依赖：

```cpp
#define UBTreePCRGetXminTDSlot(iid)      (((UBTreeItemId)(iid))->lp_xmin_td_id)
#define UBTreePCRSetXminTDSlot(iid, slot) (((UBTreeItemId)(iid))->lp_xmin_td_id = (slot))

#define UBTreePCRGetXmaxTDSlot(iid)      (((UBTreeItemId)(iid))->lp_xmax_td_id)
#define UBTreePCRSetXmaxTDSlot(iid, slot) (((UBTreeItemId)(iid))->lp_xmax_td_id = (slot))

/* lp_xmax_td_id 大于 0，说明该元组存在删除事务引用，即已被逻辑删除 */
#define IsUBTreePCRItemDeleted(iid)     (UBTreePCRGetXmaxTDSlot(iid) > 0)

/* 废弃原有的单 TD 操纵宏 */
// #define UBTreePCRSetIndexTupleTDInvalid(iid) ...
// #define IsUBTreePCRTDReused(iid) ...
// #define UBTreePCRSetIndexTupleDeleted(iid) ...
```

#### 2.3 Undo 记录格式更新
在 `UBTreeUndoInfoData` 结构体中，保存更丰富的上下文信息，以便在 TD 被复用时直接 $O(1)$ 取出历史 XID，无须遍历 Undo 链：

```cpp
typedef struct UBTreeUndoInfoData {
    uint32 old_itemid;         /* 修改前的 32-bit 行指针镜像 */
    TransactionId old_xmin_xactid;  /* 发生此修改时，旧 lp_xmin_td_id 所指向的事务号 */
    TransactionId old_xmax_xactid;  /* 发生此修改时，旧 lp_xmax_td_id 所指向的事务号 (可选，若无则为 Frozen) */
} UBTreeUndoInfoData;
```

---

### 3. 核心执行路径改造

#### 3.1 读可见性判定 与 事务信息获取 (`IndexTupleSatisfiesMvcc` / `GetItupTransInfo` / `UBTreePCRCheckKeys`)
在 `ubtpcrsearch.cpp` 中重构 MVCC 读可见性校验及元组事务信息获取逻辑：

1. **可见性判定 (`IndexTupleSatisfiesMvcc`)**：
   - 获取 `xmin_tdid` 和 `xmax_tdid`，若均未冻结且怀疑被复用，读事务**仅需读取当前元组对应的最新 1 条 Undo 记录**。
   - 从该 Undo 记录的 Payload 中反序列化出 `old_itemid` 镜像以及 `old_xmin_xactid`/`old_xmax_xactid`。
   - 使用 these 历史数据作为判定的基础，直接得知确切的 `xmin` 和 `xmax`。
   - 对于未复用的 TD 槽（常态）：直接在内存中读取 TD 槽的事务状态，无需产生任何 Undo I/O。

2. **获取元组事务号 (`GetItupTransInfo`)**：
   - 提取行指针上的 `xmin_tdid` 和 `xmax_tdid`，若已被复用，则顺着 `UBTreePCRGetLastTD(iid)` 对应的 Undo 链回溯：
     - 若最后一次修改为插入 (`UNDO_UBT_INSERT`)，则直接得到 `xmin = urec->Xid()`，`xmax = InvalidTransactionId`。
     - 若最后一次修改为删除 (`UNDO_UBT_DELETE`)，则得到 `xmax = urec->Xid()`，`xmin = undoinfo->old_xmin_xactid`。
     - 若 Undo 记录已被清理回收，则默认设为 `FrozenTransactionId`。

3. **正常扫描下的删除可见性 (`UBTreePCRCheckKeys`)**：
   - 当检测到 `IsUBTreePCRItemDeleted(iid)` 成立时，若 `xmax_tdid` 对应的 TD 槽正在运行，我们通过获取最新的一条 Undo 记录（仅需 Fetch 一条）来确定该槽是否已被其他元组复用。若已复用，说明原删除事务必然已提交且被回收，该元组对当前扫描不可见；否则代表删除仍在进行中，元组继续保持可见。

---

#### 3.2 插入与覆写操作 (`UBTreePCRDoInsert` / `UBTreePCRPageAddTuple` / `UBTreePCRDupInsertOnPage` / `UBTree3XlogInsert`)
在 `ubtpcrinsert.cpp` 和 `ubtxlog.cpp` 中修改：
- **普通插入 (`UBTreePCRDoInsert` / `UBTreePCRPageAddTuple`)**：
  - 申请活跃插入 TD 槽 $TD_{ins}$。
  - 向页面添加元组行指针时，初始化设置：
    ```cpp
    UBTreePCRSetXminTDSlot(iid, tdSlot);
    UBTreePCRSetXmaxTDSlot(iid, 0); // 初始无删除事务
    ```
- **原位覆写插入 (`UBTreePCRDupInsertOnPage` / `UBTree3XlogInsert`)**：
  - 当因为重复值或空间回收需要在一个已有的（逻辑删除或死元组）行指针上原位覆盖插入时，直接设置 `xmin_td_id` 并清理 `xmax` 删除标记：
    ```cpp
    UBTreePCRSetXminTDSlot(iid, tdSlot);
    UBTreePCRSetXmaxTDSlot(iid, 0);
    ```

---

#### 3.3 删除操作 (`UBTreePCRDoDelete`)
在 `ubtpcrinsert.cpp` 的 `PreparePCRDelete` / `UBTreePCRDeleteOnPage` 中修改：
- 申请活跃删除 TD 槽 $TD_{del}$。
- 原地修改行指针：
  ```cpp
  UBTreePCRSetXmaxTDSlot(iid, tdSlot); // 仅设置 xmax_td_id，xmin_td_id 原样保留
  ```
- **生成 Delete Undo 记录**：
  - 必须在 `UBTreeUndoInfoData` 中封装修改前的 4 字节 `itemid`。
  - 获取当前的 `lp_xmin_td_id` 所指向的事务号存入 `old_xmin_xactid`。
  - 将 `old_xmax_xactid` 设为 `FrozenTransactionId`（因为删除前没有 xmax）。

---

#### 3.4 事务回滚 (`ExecuteRollback`)
在 `ubtpcrrollback.cpp` 中重构：
- **插入回滚 (Insert Abort)**：
  - 将行指针状态 `lp_flags` 修改为 `LP_DEAD` 即可。
- **删除回滚 (Delete Abort)**：
  - 传统的单 TD 设计中，需要通过 `prev_td_id` 拼装行指针。
  - 在双 TD 设计中，**直接从 Undo Payload 中提取 `old_itemid`**，通过 4 字节的覆写操作，直接将行指针物理还原为删除前的状态。`lp_xmax_td_id` 自动恢复为旧值（通常为 0），`lp_xmin_td_id` 维持原样。

---

#### 3.5 垃圾回收 (`Page Prune`)
在 `ubtpcrrecycle.cpp` 的 `UBTreePCRPagePrune` 中重构：
- 遍历页面的行指针，若行指针中的 `lp_xmin_td_id` 指向已冻结的 TD 槽：
  ```cpp
  UBTreePCRSetXminTDSlot(iid, 0); // 设为 Frozen
  ```
- 若行指针中的 `lp_xmax_td_id` 指向已冻结且提交的删除事务的 TD 槽：
  ```cpp
  UBTreePCRSetXmaxTDSlot(iid, 0);
  iid->lp_flags = LP_DEAD; // 彻底标记为死元组，可在接下来的 RepairFragmentation 中被物理清理
  ```
- 若删除事务回滚：
  ```cpp
  UBTreePCRSetXmaxTDSlot(iid, 0); // 清除删除标记，保留 lp_flags 为 LP_NORMAL
  ```

---

#### 3.6 索引构建与排序 (`UBTreePCRSortAddTuple`)
在 `ubtpcrsort.cpp` 的 `UBTreePCRSortAddTuple` 中重构：
- 当在排序构建叶子页面时，将添加的新元组初始化为已提交（冻结）且未删除状态：
  ```cpp
  UBTreePCRSetXminTDSlot(iid, UBTreeFrozenTDSlotId);
  UBTreePCRSetXmaxTDSlot(iid, 0);
  ```

---

#### 3.7 辅助调试工具 (`parse_ubtree_pcr_index_item`)
在 `contrib/pagehack/pagehack.cpp` 中重构：
- 适配 `pagehack` 页面解析输出工具，在打印 PCR 索引元组时，提取并同时展示其 `xmin` 和 `xmax` 的 TD 槽引用：
  ```cpp
  uint8 xmin_slot = UBTreePCRGetXminTDSlot(iid);
  uint8 xmax_slot = UBTreePCRGetXmaxTDSlot(iid);
  // 输出 "xmin_td_id:%d xmax_td_id:%d" 替代原有的 "td_id:%d"
  ```

---

## 第二部分：性能对比测试方案

由于双 TD ID 的主要优势在于**消除高并发下已删除/已修改元组读判定时对 Undo 链的遍历开销**。我们的测试方案设计必须包含：**基础基准测试** 和 **针对 Undo 链回溯的专项压力测试**。

### 1. 测试环境配置
- **硬件**：
  - CPU: 至少 32 核 (如 Intel Xeon 或鲲鹏 920)。
  - 内存: 128GB。
  - 存储: 物理 NVMe SSD。
- **软件**：
  - 操作系统: openEuler / CentOS Linux。
  - openGauss 数据库：编译两个版本：
    - **Control 组**：原生 openGauss UStore（单 TD ID 方案）。
    - **Experimental 组**：改造后的 openGauss UStore（双 TD ID 方案）。
- **关键数据库参数**：
  ```ini
  # postgresql.conf 核心配置
  shared_buffers = 32GB
  enable_ustore = on
  undo_space_limit_size = 16GB
  max_connections = 200
  ```

---

### 2. 专项测试：Undo 链长度敏感度测试（核心差异验证）
该测试旨在通过人工拉长 Undo 链，对比两种设计在可见性判定上的性能瓶颈。

#### 2.1 敏感度测试脚本设计
编写一个测试脚本 `sensitivity_test.py`，其执行步骤如下：

1. **初始化数据**：
   - 创建一张测试表，在 `id` 字段上建立 UStore UBTree 索引。
   - 插入 $M$ 条初始数据。
2. **构建长 Undo 链（拉长 $N$）**：
   - 启动一个只读事务 $T_{read\_long}$，并 execute 一个简单的查询保持活跃。该事务的快照将作为“历史最老快照”锁定全局回收水位线（`globalRecycleXid`），使得后续写操作产生的 Undo 记录无法被清理。
   - 启动并发写线程，对这 $M$ 条数据执行高频的 **Delete + Insert (即 Update)**。
   - 由于 $T_{read\_long}$ 锁定了水位线，这些修改会在页面上大量申请 TD 槽。随着并发写事务不断提交和复用 TD 槽，会在该索引 block 上累积一条很长的 Undo 链。
3. **只读扫描测试**：
   - 启动另一个新的只读事务 $T_{benchmark}$，使用 Index Scan 遍历测试表。
   - 记录 $T_{benchmark}$ 完成扫描所消耗的总时间、产生的磁盘随机读 IOPS、以及系统 CPU 使用率。
4. **变动变量 $N$**：
   - 改变并发写的循环次数，使页面对应的 Undo 链长度分别为 $N = 10, 50, 100, 500, 1000$。
   - 分别在 Control 组（单 TD）和 Experimental 组（双 TD）上运行上述步骤。

#### 2.2 监控指标
- **Index Scan 延迟 (Latency)**：扫描 $M$ 条元组的端到端耗时。
- **CPU 耗时占比**：分析 `UBTreeItupEquals` 物理元组比对函数在 CPU 性能剖析工具（如 `perf`）中的占比。
- **随机读 IOPS**：由于 Undo 链回溯需要 Fetch 历史 Undo 页面，监控测试期间 Undo 缓冲池/磁盘的读 IOPS。

#### 2.3 预期结果图示分析
- **单 TD ID 组**：由于每次可见性判定均需顺着 Undo 链往回不断遍历比对，Index Scan 耗时与 $N$ 呈**线性增长**；`UBTreeItupEquals` 会成为 CPU 瓶颈；出现大量 Undo Page 读 I/O。
- **双 TD ID 组**：由于行指针上同时存在 xmin 和 xmax 引用，且复用时能 $O(1)$ 通过最新的一条 Undo 取出 XID，Index Scan 耗时**几乎不随 $N$ 的增长而变化**，保持在平稳 of 极低水平；`UBTreeItupEquals` 耗时占比接近 0。

---

### 3. 通用基准压测 (pgbench & sysbench)
验证在大规模并发混合负载下，双 TD 方案是否能提升系统的整体吞吐量并维持稳定性。

#### 3.1 pgbench 压测场景
使用 pgbench 运行内置的 `TPC-B` 混合读写场景：
1. 初始化 pgbench 数据库（规模因子 `scale = 500`）。
2. 执行不同并发连接下的压测：
   ```bash
   # 测试 32, 64, 128, 256 线程并发，持续 10 分钟
   pgbench -c 64 -j 8 -T 600 -N -r -p 5432 -U openGauss dbname
   ```
3. 对比两组的 TPS (每秒事务数) 和平均响应延迟。

#### 3.2 sysbench 压测场景
针对高频的主键/唯一键冲突读写进行测试：
1. **sysbench oltp_read_write**：读写混合压力，测试整体事务处理性能。
2. **sysbench oltp_update_index**：纯索引更新压力。在此场景下，索引元组会频繁发生“逻辑删除 + 插入”，能极大地暴露出旧方案中因 `lp_td_id` 被覆盖导致的 Undo 回溯延迟。
   ```bash
   sysbench --db-driver=pgsql --pgsql-host=127.0.0.1 --pgsql-port=5432 \
            --pgsql-user=openGauss --pgsql-db=testdb --tables=10 --table-size=1000000 \
            --threads=64 --time=600 oltp_update_index run
   ```

---

### 4. 测试报告内容要求
性能测试完成后，需输出包含以下内容的对比报告：
1. **吞吐量对比图**：横轴为并发线程数（16~256），纵轴为 TPS。
2. **延迟对比图**：横轴为并发线程数，纵轴为 Avg/95th/99th 响应时间。
3. **Undo 链敏感度曲线**：横轴为 Undo 链长度（10~1000），纵轴为单个查询耗时（ms）。
4. **性能热点 (Perf Top) 分析**：说明在 Control 组中占比例最高的内核函数（如 `UBTreeItupEquals`、`FetchUndoRecord`），以及 Experimental 组中该函数的消减比例。
