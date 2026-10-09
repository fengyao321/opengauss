# openGauss Ustore 桥接索引 (Bridge Index) 阶段一实施计划

> **文档标识**：`BRIDGE-INDEX-PHASE1-SPEC`  
> **制定日期**：2026-10-09  
> **目标分支**：`bridgeindex`  
> **基线代码**：openGauss 7.0.0-RC2  
> **前置参考**：[`bridgeindex/README.md`](file:///home/fengyao/openGauss-server/bridgeindex/README.md)

---

## 1. 阶段一目标与范围界定 (Objectives & Scope)

### 1.1 核心目标
构建 Ustore 桥接索引子系统的**最小可行产品（MVP, Minimum Viable Product）**，打通从 DDL 定义、DML 写入、Undo 事务回滚到执行器检索（IndexScan）的全流程闭环。在 openGauss 7.0.0-RC2 代码基上，实现 Ustore 对**首批标量/点查型非 B-Tree 索引（以 Hash 索引与 GiST 标量/几何索引为突破口）**的原生支持。

### 1.2 阶段一范围定义

| 功能模块 | 阶段一纳入范围 (In Scope) | 阶段一暂不包含 (Deferred to Phase 2/3) |
| :--- | :--- | :--- |
| **支持的索引 AM** | **Hash** (等值点查)、**GiST** (空间几何/范围检索) | GIN (倒排压缩树)、SP-GiST、BRIN、pgvector (HNSW) |
| **查询扫描模式** | **IndexScan** (普通单行与范围流式扫描) | BitmapIndexScan / BitmapHeapScan (位图批量置换) |
| **DML 支持** | `INSERT`、`DELETE`、`UPDATE` (原地与跨页更新) | 并发批量 COPY 吞吐极速模式 |
| **事务支持** | `COMMIT`、`ROLLBACK` (基于 Ustore Undo 自动回退) | 跨数据库分布式强一致二阶段提交 (2PC) 深度调优 |
| **空间回收** | 事务内 Retail Delete，支持 `REINDEX` | 外部索引与 Bridge UBtree 的异步 VACUUM 级联回调 |

### 1.3 准出与验收标准 (Exit Criteria)
1. 可以在 Ustore 表上成功创建 Hash 及 GiST 索引：
   ```sql
   CREATE TABLE test_ubridge (id int, val text, loc point) WITH (storage_type=ustore);
   CREATE INDEX idx_hash ON test_ubridge USING hash(val);
   CREATE INDEX idx_gist ON test_ubridge USING gist(loc);
   ```
2. 基础 DML（插入、原地更新、跨页搬迁更新、删除）能够正确维护索引与桥接映射。
3. 执行 `SELECT ... WHERE val = 'abc'`走 `IndexScan`，结果正确，能够过滤不可见版本。
4. 执行 `ROLLBACK` 后，被撤销的数据在后续索引查询中完全不可见，无悬挂指针与脏读。
5. 槽位被后续 Insert 复用（Slot Reuse）时，旧索引项绝不发生幽灵命中（Zero Phantom Hits）。
6. 系统发生异常 Crash 重启后，`bridge_ctid` 发号器不回拨，数据恢复正常。

---

## 2. 核心数据结构与契约定义 (Data Structures & Contracts)

### 2.1 合成虚拟指针 (`bridge_ctid`) 与转换规范

外部标准索引的物理接口强制要求传入 6 字节的 `ItemPointerData`。阶段一将 48 位单调自增整型编码映射至 `ItemPointerData`。

```c
/* src/include/access/bridge.h */

#ifndef BRIDGE_INDEX_H
#define BRIDGE_INDEX_H

#include "c.h"
#include "storage/item/itemptr.h"

/* 48位逻辑序列号 */
typedef uint64 BridgeSeqNo;

#define BRIDGE_INVALID_SEQ ((BridgeSeqNo)0)
#define BRIDGE_FIRST_SEQ   ((BridgeSeqNo)1)

/*
 * 将 48位单调序列号打包为 6字节 ItemPointerData
 * 高 32位存入 ip_blkid，低 16位存入 ip_posid (偏移量从 1 开始)
 */
static inline ItemPointerData BridgeSeqToItemPointer(BridgeSeqNo seq)
{
    ItemPointerData itemptr;
    BlockNumber blkno = (BlockNumber)(seq >> 16);
    OffsetNumber offno = (OffsetNumber)((seq & 0xFFFF) + 1);
    ItemPointerSet(&itemptr, blkno, offno);
    return itemptr;
}

/* 从 ItemPointerData 解包出 48位单调序列号 */
static inline BridgeSeqNo ItemPointerToBridgeSeq(const ItemPointer itemptr)
{
    BlockNumber blkno = ItemPointerGetBlockNumber(itemptr);
    OffsetNumber offno = ItemPointerGetOffsetNumber(itemptr);
    return (((BridgeSeqNo)blkno) << 16) | (BridgeSeqNo)(offno - 1);
}

#endif /* BRIDGE_INDEX_H */
```

---

### 2.2 伴随 Bridge UBtree 数据模型：轻量级单列映射

由于 openGauss 的 `IndexTupleData` 内部结构为：
```
+-----------------------------------+
| ItemPointerData t_tid   (6 Bytes) |  <--- 在传统索引中存储物理元组 TID
+-----------------------------------+
| unsigned short  t_info  (2 Bytes) |
+-----------------------------------+
| Key Data (bridge_ctid, 8 Bytes)   |  <--- 索引列数据
+-----------------------------------+
```

#### 设计突破：
在内部伴随索引 **Bridge UBTree** 中：
- **索引键（Key）**：`bridge_ctid`（8 字节整型）。
- **指针体（`t_tid`）**：**直接复用 `itup->t_tid` 存放 UHeap 的真实 `physical_ctid`**！
- **收益**：
  1. **零冗余空间**：无需定义额外的 Payload 复合结构，元组体极其紧凑；
  2. **完全复用 UBTree 原生能力**：直接使用原生 [`ubtinsert`](file:///home/fengyao/openGauss-server/src/include/access/ubtree.h#L38) 插入 `(bridge_seq, physical_ctid)`，直接使用原生 [`UBTreeDelete`](file:///home/fengyao/openGauss-server/src/include/access/ubtree.h#L51) 打标失效；
  3. **事务天然隔离**：UBTree 的 `xmin`/`xmax` 与 PCR TD 机制天然保护了 `(bridge_seq -> physical_ctid)` 映射的快照可见性。

---

### 2.3 `bridge_ctid` 发号器与崩溃恢复状态机

为避免每次生成 `bridge_ctid` 都产生 WAL 写入，采用**内存原子步长预申请机制**：

```
+-------------------------------------------------------------------------+
|                       BridgeCtidGenerator 状态机                        |
+-------------------------------------------------------------------------+
  内存当前值: g_curr_seq (Atomic uint64)
  已持久化高水位: g_persisted_hwm
  预分配步长: STEP = 10000

  [运行时生成]:
    seq = pg_atomic_fetch_add_u64(&g_curr_seq, 1);
    if (seq >= g_persisted_hwm) {
        获取发号器排他锁;
        g_persisted_hwm += STEP;
        写一条轻量 WAL_BRIDGE_ADVANCE_HWM 日志;
        释放排他锁;
    }

  [崩溃恢复 Crash Recovery]:
    重放 Redo 日志，读取最新的 WAL_BRIDGE_ADVANCE_HWM -> target_hwm;
    启动完成时: g_curr_seq = target_hwm + STEP;
    (确保新分配的 seq 绝不回拨，哪怕崩溃前部分预分配值未使用也无妨)
```

---

## 3. 源码级改造清单与详细模块设计 (Implementation Specs)

```
openGauss-server/
├── src/common/backend/parser/parse_utilcmd.cpp    [DDL 限制放宽]
├── src/common/backend/catalog/index.cpp           [伴随 Bridge UBtree 生命周期]
├── src/gausskernel/storage/access/bridge/         [新建: Bridge 核心子系统]
│   ├── CMakeLists.txt
│   ├── bridge_generator.cpp                       [发号器与高水位持久化]
│   ├── bridge_generator.h
│   ├── bridge_lookup.cpp                          [两阶段可见性检索]
│   ├── bridge_lookup.h
│   └── bridgexlog.cpp                             [WAL 记录与 Redo 回放]
├── src/include/access/relscan.h                   [IndexScanDescData 扩展]
├── src/gausskernel/storage/access/index/indexam.cpp [读拦截与执行两阶段寻址]
└── src/gausskernel/runtime/executor/execUtils.cpp [写路径 DML 拦截分发]
```

---

### 3.1 DDL 解析与元数据管理 (Catalog & DDL)

#### 1. [`src/common/backend/parser/parse_utilcmd.cpp`](file:///home/fengyao/openGauss-server/src/common/backend/parser/parse_utilcmd.cpp)
- **修改点**：在 `transformIndexStmt()` 函数中放宽对 Ustore 索引类型的限制：
  ```cpp
  /* parse_utilcmd.cpp:4420 */
  if (!isColStore) {
      if (!RelationIsUstoreFormat(rel)) {
          stmt->accessMethod = DEFAULT_INDEX_TYPE; /* btree */
      } else {
          /* 如果未显式指定 USING，默认使用 ubtree */
          if (stmt->accessMethod == NULL) {
              stmt->accessMethod = DEFAULT_USTORE_INDEX_TYPE;
          }
      }
  }
  ```
- **放宽校验**：在行存索引类型校验逻辑中，允许当 `RelationIsUstoreFormat(rel)` 为真时指定 `DEFAULT_HASH_INDEX_TYPE` 与 `DEFAULT_GIST_INDEX_TYPE`。

#### 2. [`src/common/backend/catalog/index.cpp`](file:///home/fengyao/openGauss-server/src/common/backend/catalog/index.cpp)
- **实现伴随索引管理器**：`GetOrCreateBridgeRelation(Relation heapRel)`：
  ```cpp
  Relation GetOrCreateBridgeRelation(Relation heapRel)
  {
      Oid bridgeRelOid = GetBridgeRelationOid(RelationGetRelid(heapRel));
      if (OidIsValid(bridgeRelOid)) {
          return index_open(bridgeRelOid, RowExclusiveLock);
      }
      /* 首次创建该表上的桥接索引，隐式构建伴随 Bridge UBtree */
      return CreateBridgeUBTree(heapRel);
  }
  ```
- **`CreateBridgeUBTree` 规格**：
  - 索引名称：`pg_bridge_<table_relfilenode>`
  - 目标关系：`heapRel`
  - 访问方法：`UBTREE_AM_OID` (4439)
  - 列定义：单列 `int8`（存放 `bridge_seq`）
  - 依赖关系：在 `pg_depend` 中注册 `CLASS_DEPENDENCY`，依赖主表；当主表 Drop 时自动清理。

---

### 3.2 DML 写入管道改造 (Insert / Update / Delete)

修改入口：[`src/gausskernel/runtime/executor/execUtils.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/runtime/executor/execUtils.cpp)

#### 1. `INSERT` 拦截与双写
在 [`ExecInsertIndexTuples()`](file:///home/fengyao/openGauss-server/src/gausskernel/runtime/executor/execUtils.cpp#L1603) 遍历 `relationDescs` 时增加桥接分支：

```cpp
if (RelationIsUstoreFormat(heapRelation)) {
    if (RelationIsBridgedIndex(actualindex)) {
        /* 1. 为本次写入分配单调递增的 bridge_seq */
        BridgeSeqNo seq = BridgeGetNextSeq(RelationGetRelid(heapRelation));
        ItemPointerData bridge_tid = BridgeSeqToItemPointer(seq);

        /* 2. 插入内部 Bridge UBTree: key=seq, t_tid=真实 physical_ctid */
        Relation bridgeRel = ExecGetBridgeRelation(estate, heapRelation);
        Datum bridgeKey = Int64GetDatum(seq);
        bool isNull = false;
        UBTreeDoInsert(bridgeRel, &bridgeKey, &isNull, tupleid /* physical_ctid */, false);

        /* 3. 调用外部索引 (Hash/GiST) 的 aminsert，将 bridge_tid 伪装为堆 TID 传入 */
        index_insert(actualindex, values, isnull, &bridge_tid, actualheap, 
                     indexInfo->ii_Unique ? UNIQUE_CHECK_YES : UNIQUE_CHECK_NO);
        continue;
    }
}
```

#### 2. `DELETE` 拦截与单行打标
在 [`ExecUHeapDeleteIndexTuplesGuts()`](file:///home/fengyao/openGauss-server/src/gausskernel/runtime/executor/execUtils.cpp#L1705) 中：
- 识别到索引为 Bridged 索引时，**不调用目标索引的 `index_delete()`**（因为 Hash/GiST 缺乏该接口）；
- 改为在 `Bridge UBTree` 中执行失效：
  ```cpp
  if (RelationIsBridgedIndex(actualindex)) {
      /* 根据物理 CTID 在 Bridge UBtree 中检索出匹配的 bridge_seq */
      BridgeSeqNo seq = BridgeLookupSeqByPhysicalTid(bridgeRel, tupleid);
      if (seq != BRIDGE_INVALID_SEQ) {
          Datum bridgeKey = Int64GetDatum(seq);
          bool isNull = false;
          /* 调用 UBTree 原生删除接口，在索引页标记 xmax 并记录 Undo */
          UBTreeDelete(bridgeRel, &bridgeKey, &isNull, tupleid, isRollbackIndex);
      }
      continue;
  }
  ```

#### 3. `UPDATE` 处理分支
- **未修改索引列**：`modifiedIdxAttrs` 判定无重叠，直接跳过外部索引与 Bridge UBtree，**零开销**；
- **修改了索引列**：
  - 触发上述 `DELETE` 逻辑将旧 `bridge_seq` 在 Bridge UBtree 标记失效；
  - 触发上述 `INSERT` 逻辑生成全新 `new_bridge_seq` 并写入外部索引。
- **跨页搬迁（非原地更新，但索引列未改）**：
  - 仅更新 Bridge UBtree 节点上的 `t_tid = new_physical_ctid`，外部索引保持完全不动！

---

### 3.3 读路径拦截与执行两阶段寻址 (Scan Engine)

#### 1. 数据结构扩充
在 [`src/include/access/relscan.h`](file:///home/fengyao/openGauss-server/src/include/access/relscan.h#L182) 中的 `xs_heapfetch` 后、`xs_ctbuf_hdr` 前插入桥接字段：

```cpp
    /* Bridge index scan support */
    bool xs_is_bridge_scan;       /* 是否为桥接扫描 */
    Relation xs_bridge_rel;       /* 伴随的 Bridge UBTree 句柄 */
```

#### 2. 扫描初始化：[`src/gausskernel/storage/access/index/indexam.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/index/indexam.cpp#L296)
在 `index_beginscan()` 中：
```cpp
if (RelationIsUstoreFormat(heap_relation) && RelationIsBridgedIndex(index_relation)) {
    scan->xs_is_bridge_scan = true;
    scan->xs_bridge_rel = index_open(GetBridgeRelationOid(RelationGetRelid(heap_relation)), AccessShareLock);
} else {
    scan->xs_is_bridge_scan = false;
    scan->xs_bridge_rel = NULL;
}
```
在 `index_endscan()` 中释放 `xs_bridge_rel`。

#### 3. 执行流拦截：[`IndexGetnextSlot()`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/index/indexam.cpp#L958)

```cpp
bool IndexGetnextSlot(IndexScanDesc scan, ScanDirection direction, TupleTableSlot *slot, bool* has_cur_xact_write)
{
    ItemPointer tid;
    for (;;) {
        tid = index_getnext_tid(scan, direction);
        if (tid == NULL)
            break;

        ItemPointerData physical_tid;
        if (scan->xs_is_bridge_scan) {
            /* 桥接模式：tid 实际上是 bridge_ctid */
            BridgeSeqNo seq = ItemPointerToBridgeSeq(tid);
            
            /* 在 Bridge UBTree 中按照当前快照检索并验证可见性 */
            bool visible = BridgeLookupAndVerifyVisibility(scan->xs_bridge_rel, seq, 
                                                           scan->xs_snapshot, &physical_tid);
            if (!visible) {
                /* 该版本已被并发事务删除或未提交，直接跳向下一个 TID */
                continue;
            }
            /* 替换为真实的堆物理 TID */
            scan->xs_ctup.t_self = physical_tid;
        }

        /* 原生堆取与 Undo 链多版本重构 */
        if (IndexFetchUHeap(scan, slot, has_cur_xact_write)) {
            return true;
        }
    }
    return false;
}
```

---

## 4. 详细开发任务分解与排期 (WBS & Timeline)

阶段一开发周期预计为 **6 周**，分为 4 个迭代 Sprint：

```
Sprint 1 (第 1-2 周): 基础设施与发号器子系统
  ├── [Task 1.1] 建立 src/gausskernel/storage/access/bridge/ 目录与构建系统
  ├── [Task 1.2] 实现 bridge.h 与 BridgeSeq 编解码函数
  ├── [Task 1.3] 实现 BridgeCtidGenerator 内存原子步长发号器
  └── [Task 1.4] 定义并实现 WAL_BRIDGE_ADVANCE_HWM 日志与 Redo 恢复函数

Sprint 2 (第 3 周): DDL 与元数据管理
  ├── [Task 2.1] 修改 parse_utilcmd.cpp 放宽 Ustore 表索引类型检查 (Hash/GiST)
  ├── [Task 2.2] 实现 CreateBridgeUBTree() 与 GetOrCreateBridgeRelation()
  └── [Task 2.3] 登记 pg_depend 依赖关系，跑通 Table/Index Drop 级联清理

Sprint 3 (第 4-5 周): DML 写路径与读扫描闭环
  ├── [Task 3.1] execUtils.cpp 改造 ExecInsertIndexTuples 跑通桥接插入
  ├── [Task 3.2] 实现 BridgeLookupSeqByPhysicalTid 与 ExecUHeapDeleteIndexTuplesGuts 失效
  ├── [Task 3.3] relscan.h 扩充 IndexScanDescData 桥接字段
  ├── [Task 3.4] indexam.cpp 改造 index_beginscan 与 IndexGetnextSlot 两阶段寻址
  └── [Task 3.5] 实现 BridgeLookupAndVerifyVisibility() 快照可见性过滤

Sprint 4 (第 6 周): 集成测试、事务回滚验证与回归加固
  ├── [Task 4.1] 编写包含 Hash/GiST 的专有回归测试用例 (regress test)
  ├── [Task 4.2] 验证事务 Abort/Rollback 一致性与槽位复用防串门
  ├── [Task 4.3] 构造 Crash 注入测试验证发号器高水位
  └── [Task 4.4] 输出阶段一代码审查与测试自验报告
```

---

## 5. 测试与验收方案 (Testing & Verification Strategy)

### 5.1 核心功能测试用例设计

#### 用例 1：Hash 索引等值点查与多快照可见性
```sql
-- 测试表与索引建立
CREATE TABLE t_bridge_hash (id int, val text) WITH (storage_type=ustore);
CREATE INDEX idx_bh_val ON t_bridge_hash USING hash(val);

-- 插入基础数据
INSERT INTO t_bridge_hash VALUES (1, 'apple'), (2, 'banana'), (3, 'cherry');

-- 会话 A: 开启事务修改
BEGIN;
UPDATE t_bridge_hash SET val = 'orange' WHERE id = 1;

-- 会话 B: 并发查询验证快照隔离
-- 应当通过 Hash 索引走 IndexScan 查到旧值 'apple' (依赖 Undo 重建)
EXPLAIN (COSTS OFF) SELECT * FROM t_bridge_hash WHERE val = 'apple';
SELECT * FROM t_bridge_hash WHERE val = 'apple'; -- 返回 (1, 'apple')
SELECT * FROM t_bridge_hash WHERE val = 'orange'; -- 返回 0 行

-- 会话 A 提交
COMMIT;
-- 会话 B 再次查询验证新快照
SELECT * FROM t_bridge_hash WHERE val = 'orange'; -- 返回 (1, 'orange')
SELECT * FROM t_bridge_hash WHERE val = 'apple';  -- 返回 0 行
```

#### 用例 2：GiST 空间几何索引与范围查询
```sql
CREATE TABLE t_bridge_gist (id int, loc point) WITH (storage_type=ustore);
CREATE INDEX idx_bg_loc ON t_bridge_gist USING gist(loc);

INSERT INTO t_bridge_gist VALUES 
  (1, point(10, 10)), 
  (2, point(20, 20)), 
  (3, point(100, 100));

-- 验证 GiST IndexScan 几何包含检索
EXPLAIN (COSTS OFF) SELECT * FROM t_bridge_gist WHERE loc <@ box(point(0,0), point(50,50));
SELECT id FROM t_bridge_gist WHERE loc <@ box(point(0,0), point(50,50)); -- 返回 1, 2
```

#### 用例 3：槽位复用防幽灵匹配（Anti-Phantom Row Test）
```sql
-- 构造单页面频繁删除插入场景
DELETE FROM t_bridge_hash WHERE id = 2; -- (2, 'banana') 删除
VACUUM (FREEZE) t_bridge_hash;          -- 触发 knl_pruneuheap 擦除槽位

-- 插入一条全新不相干记录，强制复用原有空槽
INSERT INTO t_bridge_hash VALUES (4, 'durian');

-- 检索旧键值 'banana'，外部 Hash 索引虽残留旧 bridge_ctid，但 Bridge UBTree 判定不可见
SELECT * FROM t_bridge_hash WHERE val = 'banana'; -- 必须返回 0 行，绝不能误返回 (4, 'durian')
```

#### 用例 4：事务回滚闭环（Rollback Test）
```sql
BEGIN;
INSERT INTO t_bridge_hash VALUES (5, 'elderberry');
SELECT * FROM t_bridge_hash WHERE val = 'elderberry'; -- 命中 1 行
ROLLBACK;

-- 回滚后立即查
SELECT * FROM t_bridge_hash WHERE val = 'elderberry'; -- 必须返回 0 行
```

---

### 5.2 故障注入与高可用测试
1. **Crash-Safe 序列号测试**：
   - 编写高频并发插入脚本持续插入数据；
   - 在高压写入期间向进程发送 `kill -9` 模拟崩溃；
   - 重启数据库，检查 WAL Redo 恢复过程；
   - 恢复后继续插入数据，验证新生成的 `bridge_ctid` 大于所有历史项，无唯一冲突报错。

---

## 6. 风险识别与应对预案 (Risks & Mitigations)

| 潜在风险 | 风险评级 | 产生根因 | 应对与缓解预案 |
| :--- | :---: | :--- | :--- |
| **加锁死锁风险 (Deadlock)** | **中** | 主表、外部索引、Bridge UBtree 三者加锁顺序若不一致可能引发死锁 | **严格制定统一加锁顺序**：`UHeap (表锁/行锁) -> Bridge UBtree -> 外部索引 AM`，读写操作一律依此序申请。 |
| **两次查找延迟开销** | **低至中** | 相比直接物理 TID，多了遍历 Bridge UBtree 的开销 | 阶段一主要针对点查，Bridge UBTree 高度通常仅 2~3 层且全在 Buffer Cache 中。阶段二将引入 Scan-Level Cache 进一步消除 70% 寻址。 |
| **Relation 句柄内存泄漏** | **低** | 扫描中途报错导致 `xs_bridge_rel` 未被正常关闭 | 在 `index_endscan()` 与事务异常退出挂钩的清理函数（`AtEOXact_RelationCache`）中强化防护性清理。 |

---

## 7. 阶段一产出交付物清单
1. **代码提交集**：实现 `src/gausskernel/storage/access/bridge/` 及相关模块的补丁 PR。
2. **测试脚本集**：`src/test/regress/sql/ustore_bridge_hash.sql` 及 `ustore_bridge_gist.sql`。
3. **自验总结报告**：功能测试 100% 通过证明，以及与原生 Astore Hash/GiST 的功能对齐清单。
