# UBTree 物理收缩场景 5（FIFO 跨页搬迁与尾部截断）缺陷分析与修复报告

> **模块**: `src/gausskernel/storage/access/ubtree/ubtshrink.cpp`  
> **发现场景**: 压测脚本 `perf.sql` - 场景 5 (FIFO 200K 头部淘汰 80% 与跨页搬迁)  
> **故障现象**: `ERROR: could not read block 695 in file "base/...": read only 0 of 8192 bytes`  
> **修复状态**: ✅ 已修复并通过全量回归验证

---

## 一、 问题背景与复现路径

在执行带有跨页数据搬迁与物理截断的 FIFO 队列测试场景（场景 5）时：
1. 初始表插入 200,000 行记录，`idx_perf_shrink_id` 索引规模扩张至 **775 块**（Block 0 ~ 774，树高 3 层，Root 位于 Block 410，Internal 位于 Block 409 及 Block 695 等）。
2. 执行 `DELETE WHERE id <= 160000;` 删除最老的前 80% 数据。
3. 经两阶段 `VACUUM` 触发空页剪枝进入 UBTree 回收队列（URQ）。
4. 调用 `gs_ubtree_shrink('idx_perf_shrink_id', false)` 触发页搬迁逻辑，将高位存活页搬迁至低位空闲槽位，并将索引物理截断至 `targetMaxBlock = 411`（物理文件仅剩 Block 0 ~ 410）。
5. 紧随其后的任何索引遍历操作（如 `SELECT count(*)`, `ORDER BY id DESC LIMIT 50`, 点查）均报出致命越界读错误：
   ```text
   ERROR: could not read block 695 in file "base/15396/149644": read only 0 of 8192 bytes
   ```

---

## 二、 缺陷根本原因分析（Root Causes）

通过对 openGauss UBTree 物理存储布局的十六进制二进制分析、Page Header / Opaque 字段逆向及 Lehman-Yao 并发树指针追踪，定位到 4 重级联缺陷：

### 1. 截断边界检查被人为硬编码“32 页”限制
* **位置**: `UBTreeCloseBoundarySiblingsBeforeTruncate`
* **原因**: 原逻辑仅检查 `[targetMaxBlock, Min(currentTotal, targetMaxBlock + 32))` 区间。当截断跨度较大时（从 411 到 775，跨度 364 块），位于 443 以后的块（如 Block 695）完全被跳过。保留区内部页 Block 409 的右兄弟指针 `btpo_next = 695` 未被闭合为 `P_NONE`，后续扫描沿链表右移直接越界读取物理已截断块。

### 2. 元信息页 `btm_fastroot` 悬垂指针未处理
* **位置**: `BTREE_METAPAGE`
* **原因**: openGauss UBTree 在元页（Block 0）中缓存了 `btm_fastroot` 以加速树下降。在索引分裂过程中，`btm_fastroot` 被分配到高位物理块（Block 695）。物理截断至 411 后，元页的 `btm_fastroot` 仍指向已被 truncate 的 695 块，后续索引扫描在入口处即尝试读取 Block 695 导致崩溃。

### 3. 非叶子内部页（Internal Pages）被错误纳入迁移与截断范围
* **位置**: `UBTreeShrinkCheckInternal` 与 `UBTreeMigratePages`
* **原因**: 扫描候选搬迁受害页时未校验 `P_ISLEAF(opaque)`。在 B-Tree 动态扩展中，非叶子内部节点也会分配在高位块（如 Block 695 为 Level 1 内部节点）。现有搬迁逻辑记录的是 `XLOG_UBTREE2_SHRINK_MOVE_LEAF` 并只下探叶子层，无法安全迁移内部节点。强行截断内部节点破坏了整棵树的拓扑路由结构。

### 4. 父节点 Downlink 未更新时仍静默标记成功
* **位置**: `UBTreeMigrateOnePage`
* **原因**: 若因并发或键匹配未能定位父节点更正 Downlink，函数未进行有效防御性回滚，导致上层仍保留旧块物理引用。

---

## 三、 代码修复方案

在 [`src/gausskernel/storage/access/ubtree/ubtshrink.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/ubtree/ubtshrink.cpp) 中实施了系统性修复：

1. **边界闭合检查全覆盖**:
   * 将扫描区间扩展为 `[targetMaxBlock, currentTotal)` 全范围检查，彻底切断所有由保留区跨向截断区的 `btpo_next` 兄弟指针。
2. **元页 Fastroot 安全防护与本地缓存失效**:
   * 在文件物理截断前检查 `BTMetaPageData`。若 `btm_fastroot >= targetMaxBlock`，自动回退为真实树根：
     ```c
     metad->btm_fastroot = metad->btm_root;
     metad->btm_fastlevel = metad->btm_level;
     ```
   * 记录 WAL 并主动失效当前后端本地缓存（`rel->rd_amcache` 与 `rel->rd_rootcache`）。
3. **保护非叶子节点与根节点**:
   * `UBTreeShrinkCheckInternal` 与 `UBTreeMigratePages` 严格校验 `P_ISLEAF(opaque)`，内部节点及根节点不作为迁移受害页；
   * 物理截断点 `targetMaxBlock` 严格限制必须大于根节点及所有高位存活内部节点。
4. **Downlink 修复强断言**:
   * `UBTreeMigrateOnePage` 严格跟踪 `parentUpdated` 状态，未成功更新父节点 Downlink 时强制返回 `false`。

---

## 四、 验证结果

重新编译 `gaussdb` 并重启后，在包含 20 万数据头部淘汰与两阶段 VACUUM 的复现环境中进行了全方位验证：

| 验证项 | 验证 SQL | 结果 | 状态 |
| :--- | :--- | :--- | :--- |
| **数据完整性** | `SELECT count(*) FROM test_diag;` | **40,000 行完整存活** | ✅ PASS |
| **反向索引扫描** | `ORDER BY id DESC LIMIT 50;` | **0.314 ms** 毫秒级返回 | ✅ PASS |
| **正向范围扫描** | `ORDER BY id ASC LIMIT 5;` | 160001 ~ 160005 连续正常 | ✅ PASS |
| **点查与区间聚合**| `WHERE id = 180000; BETWEEN 160001 AND 170000;` | 结果准确，0 越界读取 | ✅ PASS |
| **物理截断安全** | `SELECT gs_ubtree_shrink(...)` | **0 越界 Panic，0 Block Read Error** | ✅ PASS |
