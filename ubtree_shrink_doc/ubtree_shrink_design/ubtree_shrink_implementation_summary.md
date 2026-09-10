# UBTree 物理索引空间收缩（Index Shrink）实现方案总结

## 1. 背景与目标
在 openGauss 数据库中，UBTree（Ustore B-Tree）用于支持 Ustore 引擎的多版本并发控制。在大量的 INSERT、UPDATE 及 DELETE 操作后，索引树页面在完成清理或重组后，物理文件末尾容易留存连续的空闲页面（Dead/Empty Pages）。传统机制下，这些页面即使不再承载有效元组，索引物理文件尺寸（`pg_relation_size`）也不会自动缩小，造成物理磁盘空间膨胀。

本项目设计并实现了 **UBTree 物理索引空间收缩机制（UBTree Physical Index Shrink）**，支持在线（Online）与离线（Offline）两种物理空间回收模式，并提供了完备的系统级 SQL 运维接口与回归测试用例。

---

## 2. 总体架构与核心实现

### 2.1 模块构成
1. **收缩核心实现层**：`src/gausskernel/storage/access/ubtree/ubtshrink.cpp`
   - 实现逆向扫描检测（`UBTreeShrinkCheckInternal`）
   - 实现在线微秒级锁升级物理截断（`UBTreeOnlineTruncate`）
   - 实现回收队列残余项清理（`UBTreePurgeRecycleQueueAboveWatermark`）
   - 实现收缩总入口（`UBTreeShrink`）
2. **头文件与结构定义**：`src/include/access/ubtree.h`
   - 定义 `UBTreeShrinkStats` 统计信息结构
   - 导出 `gs_ubtree_shrink`、`gs_ubtree_shrink_check` 等函数声明
3. **系统函数目录与内建函数注册**：
   - `src/common/backend/catalog/builtin_funcs.ini`（注册 OID 9732、9733、9734）
   - `src/include/catalog/pg_proc.h`
4. **测试验证用例**：
   - `src/test/regress/sql/test_ubtree_shrink.sql`

---

### 2.2 核心流程与关键设计

#### (1) 逆向探测与安全截断边界（Safety Watermark Check）
- 从索引文件最后一个物理块（`totalBlocks - 1`）向前逆向扫描至根/元数据边界。
- 探测条件：若物理页满足 `P_ISDELETED(opaque) || PageIsEmpty(page) || PageIsNew(page)`，则认定为可回收死块/空块。
- 遇到首个活跃页面（Active Page）即停止扫描，计算得出安全收缩目标水位 `targetMaxBlock = totalBlocks - freedTailBlocks`。

#### (2) URQ（UBTree Recycle Queue）残余项清理
- 在物理截断磁盘文件之前，遍历清理 UBTree 页面回收队列（包括 `RECYCLE_FREED_FORK` 与 `RECYCLE_EMPTY_FORK`）。
- 移除所有块号 `>= targetMaxBlock` 的项，防止未来索引扩展复用到已被 OS 截断的非法块号。

#### (3) 在线非阻塞收缩与微秒级锁升级（Microsecond Lock Escalation）
- **常规阶段**：持有 `ShareUpdateExclusiveLock`，不阻塞并发 `SELECT`、`INSERT`、`DELETE`。
- **物理截断临界区**：
  - 使用带有短超时（默认 200ms）的 `ConditionalLockRelation(rel, AccessExclusiveLock)` 进行瞬时锁升级。
  - 获取排他锁后进行 **二次校验（Double Check）**，防止在锁获取间隙并发写入了高位块。
  - 获取 `ExtensionLock`，调用存储引擎 `RelationTruncate(rel, targetMaxBlock)` 物理裁剪底层磁盘文件。
  - 立即释放 `AccessExclusiveLock`，将对高并发业务的影响降至微秒级。

---

## 3. SQL 运维接口

| 接口名称 | 参数 | 返回值 | 说明 |
| :--- | :--- | :--- | :--- |
| `gs_ubtree_shrink_check(relname text)` | 索引名 | `text` | 探测评估索引收缩可行性，返回 `TotalBlocks`、`TargetMaxBlock`、`FreeTailBlocks` |
| `gs_ubtree_shrink(relname text, is_online bool DEFAULT true)` | 索引名, [是否在线] | `bool` | 执行物理截断收缩，支持在线与离线模式 |

---

## 4. 回归测试用例设计与物理尺寸验证

在 `src/test/regress/sql/test_ubtree_shrink.sql` 中实现了覆盖多种业务场景的端到端测试套件：

1. **基础功能与物理尺寸验证（TestCase 1）**：
   - 创建标准单列 UBTree 索引，插入 5000 行数据触发 BTree 节点分裂与物理文件扩展。
   - 记录 `init_size`，删除高位 4000 行并 `VACUUM` 后记录 `pre_shrink_size`。
   - 调用 `gs_ubtree_shrink(idx, true)` 执行在线物理收缩，验证 `(:post_shrink_size <= :pre_shrink_size)` 物理体积不膨胀/收缩。
   - 强制走索引扫描（`enable_seqscan = off`）验证元组检索与点查正确性。
   - 追加写入 1000 行新数据，验证索引在收缩后仍能正常分配新页与增长。
2. **复合列与唯一索引场景（TestCase 2）**：
   - 创建多列唯一索引（`c1 int, c2 text`），插入 4000 行宽字段数据。
   - 范围删除并收缩，断言物理体积收缩效果。
   - 收缩后校验唯一性约束（Unique Constraint）仍然保持有效，冲突插入被正确拦截报错。
3. **空表与边界用例（TestCase 3）**：
   - 针对 0 数据行的空表 UBTree 索引执行收缩探测与物理截断，验证不发生段错误或空指针异常。
   - 针对已处于紧凑状态的索引重复触发收缩，验证收缩幂等性。
4. **多模式支持验证（TestCase 4）**：
   - 验证单参数默认模式（`gs_ubtree_shrink(rel)`，默认在线）。
   - 验证双参数显式离线模式（`gs_ubtree_shrink(rel, false)`）与显式在线模式（`true`）。
5. **异常分支与非法调用防护（TestCase 5）**：
   - **不存在的对象**：传入不存在的索引名，校验优雅报错 `relation "..." does not exist`。
   - **非 UBTree 索引防护**：对传统 Heap 表的标准 BTree 索引调用收缩，校验类型检查拦截 `"... is not a UBTree index"`。

