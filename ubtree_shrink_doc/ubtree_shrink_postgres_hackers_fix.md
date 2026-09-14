# UBTree 在线物理收缩 (Online Shrink) 架构重构与 Hackers 意见修复报告

## 摘要

针对 PostgreSQL Hackers 对 UBTree 在线物理收缩与定向迁移补丁提出的 5 大架构缺陷（加锁协议死锁、截断越界 Panic、备机 URQ 状态丢失、巨型 WAL 镜像放大、全局变量污染），本项目对 UBTree 在线收缩引擎进行了全面的系统级重构。

本次重构严格遵从 Lehman-Yao 并发 B-Tree 协议，将迁移流程解耦为两阶段独立写事务，引入 Buffer Pool Pin 引用计数探查屏障，补齐备机 URQ 截断清理 WAL，并消除了所有全局状态污染。

---

## 核心架构重构与修复对比

| 缺陷序号 | Hacker 核心评审意见 | 原实现缺陷分析 | 重构后的解决方案 | 涉及代码模块 |
| :--- | :--- | :--- | :--- | :--- |
| **缺陷 1** | **并发加锁协议缺陷与 AB-BA 死锁** | 1. 跨层级加锁：同时持有父节点与叶子节点排他锁，破坏自底向上/横向加锁约束；<br>2. 反向查找：通过 victim 页查找并锁定左兄弟，违背 B-tree 自左向右加锁协议，与正常分裂并发必然死锁。 | **两阶段解耦加锁协议 (Two-Phase Decoupled Protocol)**：<br>• **阶段 1（叶子层横向迁移）**：严格按 `left -> victim -> right -> new` 自左向右顺序加锁，不持有任何父节点锁。将 victim 标记为 `BTP_DELETED` 并设置 `victim->btpo_next = newBlk` 转发指针，记录精简叶子 WAL 后立即释放所有叶子锁；<br>• **阶段 2（父节点 Downlink 修正）**：自底向上重新查找父页面，并发下严格调用 `_bt_moveright` 顺向追赶分裂，只持单块排他锁，修正 Downlink 并写入独立 WAL。彻底消除跨层同时持锁与死锁条件。 | `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` |
| **缺陷 2** | **Truncate 截断导致读写越界 Panic** | 物理截断文件前未校验是否有其他后端进程正 Pin 住待截断的数据块，截断后 backend 刷脏或读取触发 `read/write beyond EOF` PANIC。 | **Buffer Pool Pin-Count 检查屏障**：<br>新增 `UBTreeCheckBuffersPinned`，在在线与离线 Truncate 物理截断前，主动遍历待截断范围对应的 Buffer Header。一旦检测到任意页面 `refcount > 0`（被 Pin 住），立即安全退避、放弃本轮截断并留待下一轮重试。配合 `DropRelationBuffers` 确保缓存与磁盘强一致。 | `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` |
| **缺陷 3** | **备机回放逻辑不完整（URQ 截断状态丢失）** | 主机截断后清理了本地 URQ（回收队列），但未向 WAL 写入 URQ 清理记录，备机重放后 URQ 依然残留已截断的高位块号，导致后续再次使用触发损坏。 | **补齐 `XLOG_UBTREE2_URQ_PURGE` WAL**：<br>新增 `XLOG_UBTREE2_URQ_PURGE (0x60)` WAL 记录。主机物理截断前将截断水位线块号写入 WAL；备机重放时通过 `UBTree2XlogURQPurge` 构造伪 Relcache，对称清理备机 URQ 中高于该水位线的所有悬空页，保证主备 URQ 强一致。 | `src/include/access/ubtree.h`<br>`src/gausskernel/storage/access/ubtree/ubtxlog.cpp`<br>`src/gausskernel/storage/access/rmgrdesc/nbtdesc.cpp` |
| **缺陷 4** | **巨型 WAL 记录与全页写放大** | 迁移单页一次性锁定 5 块并写入一条巨型复合 WAL，且使用 `REGBUF_FORCE_IMAGE` 强制写 Full Page Image，导致 WAL 极大膨胀且增加重放崩溃风险。 | **拆分两阶段细粒度 WAL，去除强制全页镜像**：<br>1. 拆为 `XLOG_UBTREE2_SHRINK_MOVE_LEAF`（仅包含叶子节点修改，移除了跨层父块）和 `XLOG_UBTREE2_SHRINK_UPDATE_PARENT (0x70)`；<br>2. 移除全部 `REGBUF_FORCE_IMAGE`，完全遵循标准增量重做规范，大幅减少 WAL 膨胀。 | `src/include/access/ubtree.h`<br>`src/gausskernel/storage/access/ubtree/ubtxlog.cpp` |
| **缺陷 5** | **篡改全局变量破坏事务可见性** | 函数中直接向 `u_sess->utils_cxt.RecentGlobalDataXmin` 赋值，篡改了全局活跃事务可见性下界，导致并发长事务或快照查询结果错误。 | **消除全局污染，安全局部传参**：<br>移除所有对 `RecentGlobalDataXmin` 的篡改代码，计算出的安全水位线改用局部变量 `safeRecycleXmin` 安全传递至回收和清理子例程。 | `src/gausskernel/storage/access/ubtree/ubtshrink.cpp` |

---

## 详细加锁与并发迁移协议设计

```
========================================================================================
[阶段 1: 叶子层重定向 (严格自左向右加锁，不持有父锁)]
  1.1 探查 victimBuf->btpo_prev 得到候选 leftBlk，立即释放 victimBuf 读锁。
  1.2 条件锁定 leftBuf (BT_WRITE)。若并发发生了分裂，按 btpo_next 顺向右移 (Step-Right)。
  1.3 条件锁定 victimBuf (BT_WRITE)，校验状态及左指针 opaque->btpo_prev == leftBlk。
  1.4 条件锁定 rightBuf (BT_WRITE)，校验右指针 opaque->btpo_prev == victimBlk。
  1.5 锁定空闲页面 newBuf (BT_WRITE)。
  1.6 START_CRIT_SECTION:
      - 拷贝 victimPage 内容至 newPage；
      - leftPage->btpo_next = newBlk; rightPage->btpo_prev = newBlk;
      - victimPage->btpo_flags |= BTP_DELETED; victimPage->btpo_next = newBlk (转发指针);
      - 写入 XLOG_UBTREE2_SHRINK_MOVE_LEAF (仅包含 left, victim, right, new 四块，标准差量日志);
  1.7 释放 leftBuf, victimBuf, rightBuf, newBuf 的所有锁。
  
  * 并发安全性证明：并发只读事务若通过父节点旧 Downlink 访问到 victimBlk，读到 BTP_DELETED，
    依据 Lehman-Yao 协议自动根据其 btpo_next 跳往 newBlk 继续扫描，数据零丢失，过程零死锁。
========================================================================================
[阶段 2: 父节点 Downlink 修正 (自底向上独立写事务)]
  2.1 构造以 newBlk 的 High Key 为目标的搜索键。
  2.2 调用 UBTreeSearch 自顶向下定位父节点，获取 parentBuf 的 BT_WRITE 锁。
  2.3 若父节点在阶段 1 期间发生分裂，通过 _bt_moveright 向右定位包含 victimBlk 的正确父页。
  2.4 START_CRIT_SECTION:
      - 将父页中指向 victimBlk 的 Downlink 修改为 newBlk；
      - 写入 XLOG_UBTREE2_SHRINK_UPDATE_PARENT (仅涉及 parentBuf 单块);
  2.5 释放 parentBuf 锁。
========================================================================================
```

---

## 变更文件清单

1. **`src/include/access/ubtree.h`**
   - 定义 WAL 操作码：`XLOG_UBTREE2_URQ_PURGE` (`0x60`)、`XLOG_UBTREE2_SHRINK_UPDATE_PARENT` (`0x70`)。
   - 定义 WAL 结构体：`xl_ubtree2_shrink_update_parent` 与 `xl_ubtree2_urq_purge`。
   - 精简 `xl_ubtree2_shrink_move_leaf`（去除了跨层 `parentBlk` 与 `parentOffset`）。
   - 导出 `UBTreePurgeRecycleQueueAboveWatermark` 与安全传参声明。

2. **`src/gausskernel/storage/access/rmgrdesc/nbtdesc.cpp`**
   - 更新 `ubtree2_desc` 对 `XLOG_UBTREE2_SHRINK_MOVE_LEAF` 的解析。
   - 补齐 `XLOG_UBTREE2_SHRINK_UPDATE_PARENT` 与 `XLOG_UBTREE2_URQ_PURGE` 的格式化描述及 `ubtree2_type_name`。

3. **`src/gausskernel/storage/access/ubtree/ubtxlog.cpp`**
   - `UBTree2XlogShrinkMoveLeaf`：适配 4 块叶子重定向重放。
   - 新增 `UBTree2XlogShrinkUpdateParent`：单块父节点 Downlink 修正重放。
   - 新增 `UBTree2XlogURQPurge`：构造 Fake Relcache 对称清理备机 URQ。
   - 在 `UBTree2Redo` 注册新增 WAL 的重放分支。

4. **`src/gausskernel/storage/access/ubtree/ubtshrink.cpp`**
   - 新增 `UBTreeCheckBuffersPinned`：扫描目标区间 Buffer 的 `refcount`，有 Pin 即安全退避。
   - 补齐 `UBTreeOnlineTruncate` 与离线截断路径中的 `XLOG_UBTREE2_URQ_PURGE` 写入。
   - 全面重写 `UBTreeMigrateOnePage` 为两阶段解耦协议。
   - 移除所有对 `RecentGlobalDataXmin` 的写操作，改为 `safeRecycleXmin` 局部传参。
   - 增加边际效益衰减（收益率 < 20%）自适应早退熔断。

---

## 编译验证

重构后的所有源文件通过 GCC 10.3 独立目标增量编译：
- `ubtshrink.cpp.o`：编译通过（0 Warning, 0 Error）
- `ubtxlog.cpp.o`：编译通过（0 Warning, 0 Error）
- `nbtdesc.cpp.o`：编译通过（0 Warning, 0 Error）
