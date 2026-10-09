# openGauss Ustore 桥接索引 (Bridge Index) 阶段一落地执行计划

> **目标**：在 openGauss `bridgeindex` 分支上落地阶段一（MVP：Hash & GiST 桥接支持），跑通端到端读写与事务闭环。  
> **基线环境**：已就绪，编译器 `GCC 10.3.0`，单机集群运行在 `data/single_node`。

---

## 一、 执行任务与批次划分 (Task Breakdown)

整个实施过程划分为 **5 个执行阶段（Task 1 ~ Task 5）**，每阶段保持高内聚并具备可验证性：

```
+---------------------------------------------------------------------------------+
| Task 1: 基础设施与发号定义                                                         |
| - 创建 src/include/access/bridge.h                                              |
| - 定义 BridgeSeqNo 编解码与 RelationIsBridgedIndex 宏判定                        |
+---------------------------------------------------------------------------------+
                                       |
                                       v
+---------------------------------------------------------------------------------+
| Task 2: 桥接核心逻辑实现 (bridge_index.cpp)                                       |
| - 编写 src/gausskernel/storage/access/index/bridge_index.cpp                    |
| - 实现 BridgeGetOrCreateRelation (伴随 Bridge UBtree 管理)                        |
| - 实现 BridgeInsertEntry / BridgeDeleteEntry / BridgeLookupAndVerifyVisibility  |
+---------------------------------------------------------------------------------+
                                       |
                                       v
+---------------------------------------------------------------------------------+
| Task 3: DDL 约束放宽与执行流挂载                                                   |
| - 修改 indexcmds.cpp 放行 ustore 创建 hash / gist 索引                           |
| - 修改 parse_utilcmd.cpp 放宽语法语义校验                                         |
| - 修改 index.cpp 在建索引时触发伴随 Bridge UBtree 初始化                          |
+---------------------------------------------------------------------------------+
                                       |
                                       v
+---------------------------------------------------------------------------------+
| Task 4: DML 写入与读扫描两阶段寻址改造                                             |
| - 修改 execUtils.cpp (ExecInsertIndexTuples / ExecUHeapDeleteIndexTuplesGuts)   |
| - 扩展 relscan.h 中的 IndexScanDescData                                         |
| - 修改 indexam.cpp (index_beginscan / IndexGetnextSlot) 实现两阶段寻址            |
+---------------------------------------------------------------------------------+
                                       |
                                       v
+---------------------------------------------------------------------------------+
| Task 5: 增量编译、部署与端到端功能自验                                            |
| - 编译相关源码目标，链接 gaussdb 并安装                                           |
| - 重启 single_node 数据库服务                                                    |
| - 跑通 Hash / GiST 索引的 DDL、DML、IndexScan 查询、事务回滚验证用例               |
+---------------------------------------------------------------------------------+
```

---

## 二、 关键实现细节与源码清单

### Task 1: 基础接口定义 (`src/include/access/bridge.h`)
- **文件位置**：`src/include/access/bridge.h`
- **主要内容**：
  - `BridgeSeqNo`（`uint64` 48 位有效序列号）；
  - `BridgeSeqToItemPointer` / `ItemPointerToBridgeSeq` 宏函数；
  - `RelationIsBridgedIndex(Relation rel)`：
    - `RelationIsUstoreFormat(heapRel)` 且 `(am == HASH_AM_OID || am == GIST_AM_OID)`；
  - 核心接口声明（增、删、查、验可见性）。

### Task 2: 桥接核心逻辑 (`src/gausskernel/storage/access/index/bridge_index.cpp`)
- **文件位置**：`src/gausskernel/storage/access/index/bridge_index.cpp`
- **主要内容**：
  - **伴随 Bridge UBtree 管理**：
    - 命名规则：`pg_bridge_<heap_reloid>`；
    - 单列 `int8` 索引，其物理叶子节点的 `itup->t_tid` 直接存储真实的堆表 `physical_ctid`；
  - **`BridgeInsertEntry`**：
    - 构造 `IndexTuple`，Key 为 `bridge_seq`，`t_tid` 填入真实 `physical_ctid`；
    - 调用原生 `UBTreeDoInsert` 写入，天然生成 Undo 与 PCR TD 信息；
  - **`BridgeDeleteEntry`**：
    - 根据 `bridge_seq` 调用 `UBTreeDelete`，在叶子节点标记 `xmax` 并生成 Undo；
  - **`BridgeLookupAndVerifyVisibility`**：
    - 根据 `bridge_seq` 构造 `BTScanInsert`；
    - 调用 `UBTreeSearch` 定位叶子页与偏移；
    - 执行快照可见性检查（`UBTreeVisibilityCheckWrap`）；
    - 若可见，从 `itup->t_tid` 取出真实的 `physical_ctid` 并返回 `true`。

### Task 3: DDL 限制解除与创建挂载
1. **`src/gausskernel/optimizer/commands/indexcmds.cpp`**：
   - 寻找 `rel->rd_tam_ops == TableAmUstore` 区域；
   - 放宽 `strcmp(stmt->accessMethod, "hash") == 0` 与 `strcmp(stmt->accessMethod, "gist") == 0`，允许进入后续建索引流程。
2. **`src/common/backend/parser/parse_utilcmd.cpp`**：
   - 确保 `transformIndexStmt()` 不会将 `hash/gist` 强行覆盖或拦截报错。
3. **`src/common/backend/catalog/index.cpp`**：
   - 在 `index_create()` 中，若目标索引是 Bridged 索引，调用 `BridgeGetOrCreateRelation()` 确保伴随 Bridge UBtree 准备就绪。

### Task 4: DML 写管道与执行器读扫描两阶段拦截
1. **`src/gausskernel/runtime/executor/execUtils.cpp`**：
   - **`ExecInsertIndexTuples`**：
     - 若为 Bridged 索引，先为本行申请 `bridge_seq`；
     - 写入 Bridge UBtree：`(bridge_seq -> physical_ctid)`；
     - 组装 `bridge_tid = BridgeSeqToItemPointer(bridge_seq)`，传给目标索引的 `index_insert()`；
   - **`ExecUHeapDeleteIndexTuplesGuts`**：
     - 对于 Bridged 索引，不调用外部索引的 `index_delete()`，转而调用 `BridgeDeleteEntry()` 将对应的 `bridge_seq` 在 Bridge UBtree 标记失效。
2. **`src/include/access/relscan.h`**：
   - 在 `IndexScanDescData` 中补充 `bool xs_is_bridge_scan;` 和 `Relation xs_bridge_rel;`。
3. **`src/gausskernel/storage/access/index/indexam.cpp`**：
   - `index_beginscan()`：判断若为 Bridged 索引，开启 `xs_is_bridge_scan = true` 并打开伴随 Bridge UBtree；
   - `index_endscan()`：安全关闭 `xs_bridge_rel`；
   - `IndexGetnextSlot()`：
     - 获得外部索引返回的 `bridge_tid`；
     - 拦截调用 `BridgeLookupAndVerifyVisibility()`；
     - 若不可见则循环取下一个 TID；
     - 若可见，置换 `scan->xs_ctup.t_self = physical_tid`，调用原生 `IndexFetchUHeap()`。

### Task 5: 增量构建与端到端验证
1. **增量编译**：
   ```bash
   export PATH=/home/fengyao/binarylibs/buildtools/gcc10.3/gcc/bin:$PATH
   export LD_LIBRARY_PATH=/usr/lib64:/home/fengyao/binarylibs/buildtools/gcc10.3/gcc/lib64:/home/fengyao/binarylibs/buildtools/gcc10.3/isl/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/mpc/lib/:/home/fengyao/binarylibs/buildtools/gcc10.3/mpfr/lib/:/home/fengyao/binarylibs/buildtools/gcc10.3/gmp/lib/:$LD_LIBRARY_PATH
   export DEBUG_TYPE=debug
   export PERL5LIB=/home/fengyao/openGauss-server/src/common/backend/utils/mb/Unicode:$PERL5LIB
   make -C tmp_build/src/gausskernel/storage/access/index -j8
   make -C tmp_build/src/gausskernel/optimizer -j8
   make -C tmp_build/src/common/backend -j8
   make -C tmp_build/src/gausskernel/runtime/executor -j8
   cd tmp_build/src/gausskernel && /usr/bin/cmake -E cmake_link_script CMakeFiles/gaussdb.dir/link.txt
   cp -f tmp_build/src/gausskernel/gaussdb mppdb_temp_install/bin/gaussdb
   ```
2. **测试用例集**：
   - `CREATE TABLE (storage_type=ustore)` -> `CREATE INDEX USING hash / gist`
   - 点查、范围扫描、更新、删除验证
   - `ROLLBACK` 事务一致性验证

---

## 三、 执行步骤推进计划

我们将按照上述 Task 1 到 Task 5 顺序依次实施并验证。实施过程中随时同步每个修改文件的具体内容与编译测试结果。
