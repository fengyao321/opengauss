# openGauss Ustore 桥接索引 (Bridge Index) 阶段一测试用例设计规范

> **文档标识**：`BRIDGE-INDEX-PHASE1-TEST-SPEC`  
> **制定日期**：2026-10-09  
> **目标特性**：Ustore 桥接索引 (Bridge Index Phase 1: MVP for Hash & GiST)  
> **基线分支**：`bridgeindex` (openGauss 7.0.0-RC2)  
> **参考设计**：[`bridgeindex/phase1_implementation_plan.md`](file:///home/fengyao/openGauss-server/bridgeindex/phase1_implementation_plan.md)

---

## 1. 测试范围与准出基准 (Test Scope & Exit Criteria)

### 1.1 测试目标
验证基于伴生桥接索引（Bridge Index）机制下，Ustore 表使用 **Hash 索引** 和 **GiST 索引** 的全生命周期功能完整性，确保以下核心目标达成：
1. **DDL 闭环**：正确创建、删除带有 Hash/GiST 索引的 Ustore 表，自动生成伴生表与双向 UBTree 索引，主表 DROP 时级联清理。
2. **读写一致性**：DML（INSERT/UPDATE/DELETE）正确维护桥接映射；`IndexScan` 能够通过虚拟 TID 两阶段反查提取真实堆元组。
3. **MVCC 快照隔离**：并发读写时，能够通过快照可见性过滤不可见版本，并正确利用 Ustore Undo 链重构历史快照。
4. **事务回滚无残留**：`ROLLBACK` 之后，被撤销的写入在外部索引和伴生表中无残留或被完全过滤，绝不出现脏读或悬垂指针。
5. **槽位复用防幽灵命中（Zero Phantom Hits）**：物理槽位因删除被后续新元组复用后，查询旧键值绝不能误命中新元组。

---

## 2. 测试用例矩阵清单 (Test Matrix)

| 用例编号 | 测试模块 | 关键验证点 | 预期关键表现 |
| :--- | :--- | :--- | :--- |
| **TC-01** | DDL 语法与元数据 | Ustore 上创建 Hash 索引与伴生表自动生成 | 伴生表 `pg_bridge_<oid>` 及其双向 UBTree 索引就绪 |
| **TC-02** | DDL 语法与元数据 | Ustore 上创建 GiST 空间几何索引 | 支持 `point` 类型的 GiST 索引正常创建 |
| **TC-03** | DDL 约束拦截 | 非法索引类型在 Ustore 上的安全防御 | `USING btree` 提示引导至 `ubtree`，防止误用 |
| **TC-04** | DML & 检索 | Hash 索引等值点查与两阶段反查正确性 | `EXPLAIN` 显示 `Index Scan using idx_hash`，结果 100% 精确 |
| **TC-05** | DML & 检索 | GiST 空间几何范围检索与包含判定 | `loc <@ box(...)` 走 `Index Scan using idx_gist` 精确匹配 |
| **TC-06** | MVCC 多版本 | 原位更新（非索引列）与跨版本检索 | 原位修改数据后，走 Hash 索引检索返回最新值，TID 保持原位 |
| **TC-07** | MVCC 多版本 | 索引列值变更更新与旧键失效 | 旧值走索引返回 0 行，新值走索引准确定位 |
| **TC-08** | 事务回滚 | `INSERT` 事务回滚一致性 | 外部索引虽记录虚拟 TID，但快照判定不可见，结果为 0 行 |
| **TC-09** | 事务回滚 | `DELETE` / `UPDATE` 事务回滚一致性 | 回滚后原始数据完整恢复，索引扫描与全表扫描结果一致 |
| **TC-10** | 核心安全机制 | 物理槽位复用防幽灵行命中 (Anti-Phantom) | 物理槽位被新行复用后，查旧键值绝不命中新行 |
| **TC-11** | 异常与边界 | NULL 值处理与混合数据类型兼容性 | Hash/GiST 对 NULL 列的安全过滤 |
| **TC-12** | 级联清理 | 主表与索引 DROP 级联清理生命周期 | 伴生表及双向索引随主表 DROP 自动级联清理无垃圾残留 |

---

## 3. 详细测试用例与执行脚本 (Detailed Test Cases)

### 用例 TC-01：Ustore Hash 索引创建与伴生表元数据验证
- **设计目的**：验证 DDL 路径放开、`storage_type=ustore` 选项校验、伴生表及双向 UBTree 索引自动创建。
- **测试脚本**：
```sql
-- 1. 创建 Ustore 主表
DROP TABLE IF EXISTS t_bridge_ddl_test CASCADE;
CREATE TABLE t_bridge_ddl_test (
    id INT,
    user_name VARCHAR(64),
    score NUMERIC
) WITH (storage_type = ustore);

-- 2. 创建 Hash 索引
CREATE INDEX idx_b_hash ON t_bridge_ddl_test USING hash(user_name);

-- 3. 验证主表、伴生表及伴生索引元数据
SELECT c.relname, c.relkind, am.amname, c.reloptions
FROM pg_class c
LEFT JOIN pg_am am ON c.relam = am.oid
WHERE c.relname LIKE 'pg_bridge_' || (SELECT oid FROM pg_class WHERE relname = 't_bridge_ddl_test') || '%'
ORDER BY c.relname;
```
- **预期结果**：
  1. 索引 `idx_b_hash` 成功创建，无报错；
  2. 系统中自动生成 `pg_bridge_<oid>` 伴生表（`relkind='r'`，`storage_type=ustore`）；
  3. 自动生成两个 UBTree 索引：`pg_bridge_<oid>_seq_idx` 与 `pg_bridge_<oid>_tid_idx`（`amname='ubtree'`）。

---

### 用例 TC-02：Ustore GiST 空间几何索引创建
- **设计目的**：验证 GiST 索引在 Ustore 存储引擎上的 DDL 解析与伴生桥接链路初始化。
- **测试脚本**：
```sql
DROP TABLE IF EXISTS t_bridge_gist_test CASCADE;
CREATE TABLE t_bridge_gist_test (
    id INT,
    geo_point POINT,
    geo_box BOX
) WITH (storage_type = ustore);

-- 创建 GiST 空间索引
CREATE INDEX idx_b_gist ON t_bridge_gist_test USING gist(geo_point);

-- 验证索引状态
\d+ t_bridge_gist_test
```
- **预期结果**：
  1. `idx_b_gist` 成功创建；
  2. 执行 `\d+` 显示索引访问方法为 `gist`。

---

### 用例 TC-03：非法索引类型安全拦截校验
- **设计目的**：验证系统能够正确区分合法的桥接索引类型（Hash/GiST/UBTree）与非法的传统堆索引（如在 Ustore 上错误指定 `USING btree`）。
- **测试脚本**：
```sql
-- 尝试在 Ustore 表上创建未经桥接的传统 btree 索引
CREATE INDEX idx_fail_btree ON t_bridge_ddl_test USING btree(id);
```
- **预期结果**：
  - 触发错误拦截，报错信息应包含：`ERROR: btree index is not supported for ustore, please use ubtree instead`。

---

### 用例 TC-04：Hash 索引等值点查与两阶段反查正确性
- **设计目的**：验证多行写入、虚拟 TID 编码生成、伴生表映射写入，以及查询时通过 `IndexScan` 反查真实物理元组的正确性。
- **测试脚本**：
```sql
DROP TABLE IF EXISTS t_hash_scan CASCADE;
CREATE TABLE t_hash_scan (
    id INT,
    code TEXT,
    info VARCHAR(100)
) WITH (storage_type = ustore);

CREATE INDEX idx_hs_code ON t_hash_scan USING hash(code);

-- 插入测试数据
INSERT INTO t_hash_scan VALUES (1, 'ALPHA', 'first record');
INSERT INTO t_hash_scan VALUES (2, 'BETA',  'second record');
INSERT INTO t_hash_scan VALUES (3, 'GAMMA', 'third record');
INSERT INTO t_hash_scan VALUES (4, 'DELTA', 'fourth record');

-- 开启强制索引扫描
SET enable_seqscan = off;
SET enable_indexscan = on;

-- 验证执行计划走 Hash IndexScan
EXPLAIN (COSTS OFF) SELECT * FROM t_hash_scan WHERE code = 'BETA';

-- 验证执行结果
SELECT * FROM t_hash_scan WHERE code = 'BETA';
SELECT * FROM t_hash_scan WHERE code = 'DELTA';
SELECT * FROM t_hash_scan WHERE code = 'NON_EXISTENT';
```
- **预期结果**：
  1. `EXPLAIN` 显示 `Index Scan using idx_hs_code on t_hash_scan`；
  2. `code = 'BETA'` 精准返回 `(2, 'BETA', 'second record')`；
  3. `code = 'DELTA'` 精准返回 `(4, 'DELTA', 'fourth record')`；
  4. 未命中键值返回 0 行，无死循环或段错误。

---

### 用例 TC-05：GiST 空间几何范围包含检索
- **设计目的**：验证 GiST 空间多维检索条件走 Bridge 机制的准确性。
- **测试脚本**：
```sql
DROP TABLE IF EXISTS t_gist_scan CASCADE;
CREATE TABLE t_gist_scan (
    id INT,
    city VARCHAR(50),
    location POINT
) WITH (storage_type = ustore);

CREATE INDEX idx_gs_loc ON t_gist_scan USING gist(location);

INSERT INTO t_gist_scan VALUES (101, 'Beijing',  point(116.40, 39.90));
INSERT INTO t_gist_scan VALUES (102, 'Shanghai', point(121.47, 31.23));
INSERT INTO t_gist_scan VALUES (103, 'Chengdu',  point(104.06, 30.67));
INSERT INTO t_gist_scan VALUES (104, 'Tokyo',    point(139.69, 35.68));

SET enable_seqscan = off;
SET enable_indexscan = on;

-- 范围窗口检索（包含在经纬度范围盒内）
EXPLAIN (COSTS OFF) 
SELECT id, city FROM t_gist_scan 
WHERE location <@ box(point(100.0, 20.0), point(125.0, 45.0));

SELECT id, city FROM t_gist_scan 
WHERE location <@ box(point(100.0, 20.0), point(125.0, 45.0))
ORDER BY id;
```
- **预期结果**：
  1. 执行计划走 `Index Scan using idx_gs_loc on t_gist_scan`；
  2. 检索结果包含 Beijing、Shanghai、Chengdu（id 101, 102, 103），排除 Tokyo（104）。

---

### 用例 TC-06：原位更新 (In-Place Update) 索引扫描有效性
- **设计目的**：验证 Ustore 最具特色的原地更新场景（修改非索引列，物理 TID 保持不变）下，Bridge Index 是否能持续保持寻址有效。
- **测试脚本**：
```sql
-- 基于 TC-04 数据
UPDATE t_hash_scan SET info = 'beta updated in place' WHERE code = 'BETA';

-- 再次走 Hash 索引检索
SELECT * FROM t_hash_scan WHERE code = 'BETA';
```
- **预期结果**：
  - 走索引检索返回 `(2, 'BETA', 'beta updated in place')`，数据更新成功且通过原索引项直接命中。

---

### 用例 TC-07：索引列值更新与旧键失效
- **设计目的**：验证更新索引列时，旧 Bridge 映射失效并生成新 Bridge 映射的全生命周期处理。
- **测试脚本**：
```sql
-- 将 GAMMA 改为 OMEGA
UPDATE t_hash_scan SET code = 'OMEGA' WHERE id = 3;

-- 检索旧值
SELECT * FROM t_hash_scan WHERE code = 'GAMMA';

-- 检索新值
SELECT * FROM t_hash_scan WHERE code = 'OMEGA';
```
- **预期结果**：
  1. 查询 `code = 'GAMMA'` 返回 0 行（旧键已通过 Bridge 伴生表标记失效）；
  2. 查询 `code = 'OMEGA'` 正常命中 `(3, 'OMEGA', 'third record')`。

---

### 用例 TC-08：事务回滚 (ROLLBACK) 完整闭环
- **设计目的**：测试在事务内插入数据后 Abort/Rollback，外部索引虽可能残留虚拟 TID，但伴生表依赖 Undo 版本控制将其正确过滤，绝不发生脏读。
- **测试脚本**：
```sql
-- 开启显式事务并插入数据
BEGIN;
INSERT INTO t_hash_scan VALUES (999, 'PHANTOM', 'uncommitted test');
-- 事务内查询应当可见
SELECT * FROM t_hash_scan WHERE code = 'PHANTOM';
ROLLBACK;

-- 回滚后再次查询
SELECT * FROM t_hash_scan WHERE code = 'PHANTOM';
```
- **预期结果**：
  1. 事务内返回 1 行；
  2. `ROLLBACK` 后走索引查询返回 0 行，未产生任何悬垂指针或脏读错误。

---

### 用例 TC-09：删除 (DELETE) 事务与回滚验证
- **设计目的**：验证 DELETE 操作在 Bridge 表中的单行失效维护，以及对 DELETE 进行 ROLLBACK 后的数据恢复。
- **测试脚本**：
```sql
BEGIN;
DELETE FROM t_hash_scan WHERE code = 'ALPHA';
-- 事务内删除生效
SELECT * FROM t_hash_scan WHERE code = 'ALPHA';
ROLLBACK;

-- 回滚后应当完全恢复
SELECT * FROM t_hash_scan WHERE code = 'ALPHA';
```
- **预期结果**：
  1. 事务内查询返回 0 行；
  2. 回滚后查询正常返回 `(1, 'ALPHA', 'first record')`。

---

### 用例 TC-10：槽位复用防幽灵行命中 (Anti-Phantom Row on Slot Reuse)
- **设计目的**：**Bridge Index 的核心技术安全防线**。验证 Ustore 页面内清理元组并由全新元组复用物理槽位（Slot Reuse）时，外部 Hash 索引残留项绝不会将新元组误判为旧元组。
- **测试脚本**：
```sql
DROP TABLE IF EXISTS t_slot_reuse CASCADE;
CREATE TABLE t_slot_reuse (
    id INT,
    token TEXT,
    payload CHAR(100)
) WITH (storage_type = ustore);

CREATE INDEX idx_sr_token ON t_slot_reuse USING hash(token);

-- 插入记录并提交
INSERT INTO t_slot_reuse VALUES (1, 'KEY_AAA', 'payload_1');
COMMIT;

-- 删除记录并提交
DELETE FROM t_slot_reuse WHERE token = 'KEY_AAA';
COMMIT;

-- 触发 Ustore 页面空间回收整理 (Slot Pruning)
VACUUM t_slot_reuse;

-- 插入一条全新不相干记录，强制复用原有空槽
INSERT INTO t_slot_reuse VALUES (2, 'KEY_BBB', 'payload_2');
COMMIT;

-- 关键验证：通过旧键 'KEY_AAA' 检索
-- 外部 Hash 索引中如果残留有旧指向，Bridge 伴生表可见性检查必须拦截
SET enable_seqscan = off;
SET enable_indexscan = on;
SELECT * FROM t_slot_reuse WHERE token = 'KEY_AAA';

-- 正常检索新键 'KEY_BBB'
SELECT * FROM t_slot_reuse WHERE token = 'KEY_BBB';
```
- **预期结果**：
  1. 检索 `'KEY_AAA'` 必须严格返回 0 行（**绝对不允许误返回 `(2, 'KEY_BBB', 'payload_2')`**）；
  2. 检索 `'KEY_BBB'` 正常返回 1 行。

---

### 用例 TC-11：NULL 值与边界场景验证
- **设计目的**：验证包含 NULL 键值时的处理稳定性。
- **测试脚本**：
```sql
INSERT INTO t_hash_scan VALUES (5, NULL, 'null token test');

-- 检索 NULL
SELECT * FROM t_hash_scan WHERE code IS NULL;
```
- **预期结果**：
  - 正常处理 NULL 记录，无崩溃或段错误。

---

### 用例 TC-12：主表与伴生表级联清理 (Drop Cascade)
- **设计目的**：验证基于 `pg_depend` 内部依赖的级联回收机制，确保主表 Drop 时伴生表与伴生索引不产生系统目录孤立垃圾。
- **测试脚本**：
```sql
-- 获取当前主表 OID
SELECT oid FROM pg_class WHERE relname = 't_bridge_ddl_test' \gset

-- 删除主表
DROP TABLE t_bridge_ddl_test CASCADE;

-- 验证伴生表及其索引是否已自动彻底清除
SELECT count(*) FROM pg_class WHERE relname LIKE 'pg_bridge_' || :oid || '%';
```
- **预期结果**：
  - 查询结果计数为 0，伴生表及所属索引全部被干净级联删除。

---

## 4. 自动化测试套件产出与执行方法

在测试验证环节，本套件已转化为标准测试 SQL 脚本：
- 脚本位置：[`bridgeindex/test/phase1_bridge_index_test.sql`](file:///home/fengyao/openGauss-server/bridgeindex/test/phase1_bridge_index_test.sql)
- 运行命令（在数据库启动后通过 gsql 批量执行）：
  ```bash
  gsql -d postgres -p 5432 -r -f bridgeindex/test/phase1_bridge_index_test.sql
  ```
