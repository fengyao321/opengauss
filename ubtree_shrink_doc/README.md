# openGauss UBTree 在线物理收缩（Shrink）技术资产与文档全景导航

> **模块归属**: openGauss 内核 UStore 存储引擎 · UBTree 索引在线物理收缩模块  
> **核心源码**:
> - 核心实现：[`src/gausskernel/storage/access/ubtree/ubtshrink.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/ubtree/ubtshrink.cpp)
> - 日志重做：[`src/gausskernel/storage/access/ubtree/ubtxlog.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/ubtree/ubtxlog.cpp)
> - 头文件定义：[`src/include/access/ubtree.h`](file:///home/fengyao/openGauss-server/src/include/access/ubtree.h)
> - 日志描述符：[`src/gausskernel/storage/access/rmgrdesc/nbtdesc.cpp`](file:///home/fengyao/openGauss-server/src/gausskernel/storage/access/rmgrdesc/nbtdesc.cpp)

---

## 目录导航
- [一、 整体目录结构树](#一-整体目录结构树)
- [二、 文档全景分类与索引矩阵](#二-文档全景分类与索引矩阵)
  - [1. 核心架构与专项技术设计 (`ubtree_shrink_design/`)](#1-核心架构与专项技术设计-ubtree_shrink_design)
  - [2. 社区评审、Code Review 与架构重构 (`reviews/`)](#2-社区评审code-review-与架构重构-reviews)
  - [3. 发明专利提案与技术交底规划](#3-发明专利提案与技术交底规划)
  - [4. 性能评测与压测分析报告 (`perf/reports/`)](#4-性能评测与压测分析报告-perfreports)
  - [5. 基准测试套件与自动化脚本 (`perf/scripts/`)](#5-基准测试套件与自动化脚本-perfscripts)
  - [6. 原始测试数据与执行日志 (`perf/logs/`)](#6-原始测试数据与执行日志-perflogs)
- [三、 推荐阅读与研读路径](#三-推荐阅读与研读路径)
- [四、 压测与验证复现指引](#四-压测与验证复现指引)

---

## 一、 整体目录结构树

```text
ubtree_shrink_doc/
├── README.md                                    # 【索引中枢】目录导航、技术矩阵与研读路径
├── ubtree_shrink_patent_proposals.md            # 【知识产权】6 项核心发明专利挖掘与交底书布局规划
│
├── reviews/                                     # 【社区审查与架构重构】
│   ├── ubtree_shrink_postgres_hackers_review.md # PostgreSQL Hackers 评审专家首轮意见集 (5 大关键缺陷)
│   ├── ubtree_shrink_postgres_hackers_round2_review.md # PostgreSQL Hackers 二轮评审意见 (条件接收与边缘加固)
│   ├── ubtree_shrink_postgres_hackers_fix.md    # 针对 Hackers 意见的架构级重构修复实施细节
│   ├── ubtree_shrink_concurrency_formal_proof.md # ★ 并发控制协议形式化数学证明 (4 大定理与无锁死证明)
│   └── ubtree_shrink_full_code_review.md        # 内核源码逐行审查报告 (锁/内存/边界校验)
│
├── ubtree_shrink_design/                        # 【核心设计】架构规格书与专项攻坚设计
│   ├── ubtree_shrink_latest_architecture_design.md # ★ 最新完整版架构设计说明书 (v3.2)
│   ├── ubtree_shrink_internal_page_migration_design.md # 非叶子内部节点 (Level >= 1) 搬迁专项设计
│   ├── ubtree_shrink_urq_compaction_design.md   # URQ 回收队列紧凑度分析与重度膨胀定向迁移设计
│   ├── ubtree_shrink_targeted_migration_design.md # 活跃块与空闲块一对一定向映射设计
│   ├── ubtree_shrink_implementation_summary.md  # 关键实现与阶段性代码落地总结
│   └── ubtree_shrink_design_report.md           # 早期总体设计报告与技术选型权衡
│
└── perf/                                        # 【评测体系】基准压测、验证脚本与原始数据
    ├── reports/                                 # 评测与稳定性分析报告
    │   ├── perf_benchmark_report_v3.md          # ★ 最新综合基准报告 (7 大场景，提速 3~55 倍)
    │   ├── longrun_stability_report.md          # ★ 180s 高并发混合负载长周期稳定性报告 (0死锁/0Panic)
    │   ├── tpcc_shrink_comparison_report.md     # 30 分钟 TPC-C A/B 对照测试 (业务零损耗验证)
    │   ├── adaptive_shrink_15min_report.md      # 自适应阈值长周期压测报告 (防颠簸熔断验证)
    │   ├── ubtree_shrink_time_space_comparison_report.md # 物理空间缩减与执行耗时双维量化报告
    │   ├── tpcc_longrun_shrink_comparison_report.md
    │   ├── ubtree_shrink_comparison_report.md
    │   ├── smoke_test_report.md
    │   ├── scenario5_page_relocation_bug_analysis.md # 散列中间空洞迁移 Bug 诊断与解决
    │   ├── perf_v2_report.md
    │   ├── perf_v1.md
    │   ├── ubtree_shrink_performance_report.md
    │   └── ubtree_shrink_adaptive_threshold_benchmark_design.md
    │
    ├── scripts/                                 # 基准测试与自动化运行脚本
    │   ├── perf.sql                             # 7 大典型场景基准测试完整 SQL 脚本
    │   ├── test_ubtree_shrink_longrun.py        # 金融流水账本混合负载长时间稳定性压测套件
    │   ├── run_perf_test.py                     # 自动化基准压测运行驱动器
    │   ├── run_tpcc_shrink_comparison.py        # TPC-C A/B 对比测试自动化脚本
    │   ├── run_tpcc_with_shrink.py              # TPC-C 在线收缩压测脚本
    │   └── run_15min_benchmark.sh               # 15 分钟自适应基准 Shell 自动化运行器
    │
    └── logs/                                    # 原始执行日志与数据
        ├── perf_results_latest.out              # 最新 7 大场景全量成功执行日志
        ├── perf_results_full.out
        ├── perf_results_internal_migration.out
        ├── perf_results_phase1_2.out
        ├── perf_results_phase3.out
        ├── tpcc_comparison.log
        ├── tpcc_longrun_comparison.log
        └── adaptive_shrink_15min.log
```

*(注：`perf/` 根目录下保留了指向 `reports/`、`scripts/` 与 `logs/` 的兼容软链接，确保既有外部脚本调用路径完全无损。)*

---

## 二、 文档全景分类与索引矩阵

### 1. 核心架构与专项技术设计 (`ubtree_shrink_design/`)
本模块包含 UBTree 在线物理收缩特性的核心架构说明书、各阶段专项攻坚设计方案及落地总结。

| 文件名称 | 文档版本 | 定位与核心内容摘要 |
| :--- | :--- | :--- |
| [**`ubtree_shrink_latest_architecture_design.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_latest_architecture_design.md) | **v3.2 (Latest)** | **【必读】最新完整版架构设计说明书**。涵盖全流程流水线、两阶段解耦迁移协议、非叶子节点自底向上搬迁、边界悬空指针闭合、Pin-Count 安全屏障与主备 WAL 对称清理。 |
| [**`ubtree_shrink_design_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_design_report.md) | v1.0 | 早期总体设计报告与技术选型权衡。 |
| [**`ubtree_shrink_implementation_summary.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_implementation_summary.md) | v2.0 | 关键功能落地与阶段性代码实现总结。 |
| [**`ubtree_shrink_urq_compaction_design.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_urq_compaction_design.md) | 专项设计 | **URQ 回收队列紧凑度分析专项**。解决重度膨胀场景（如 500K 删 90%、1M 删 95%）下低位线性扫描失效与 URQ 高位页分配死循环问题。 |
| [**`ubtree_shrink_internal_page_migration_design.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_internal_page_migration_design.md) | 专项设计 | **非叶子内部节点（Internal Page，Level $\ge 1$）搬迁专项**。破解高位内部节点阻断文件截断痛点，详细推导父节点寻址、根节点保护与自底向上分层协议。 |
| [**`ubtree_shrink_targeted_migration_design.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_targeted_migration_design.md) | 专项设计 | 尾部活跃块与低位空闲块定向映射及成本收益决策机制。 |

---

### 2. 社区评审、Code Review 与架构重构 (`reviews/`)
本模块记录了遵循 PostgreSQL Hackers 高标准进行严格代码审查（Code Review）及架构级缺陷重构的完整历程。

| 文件名称 | 涉及模块 | 定位与核心内容摘要 |
| :--- | :--- | :--- |
| [**`ubtree_shrink_postgres_hackers_review.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_postgres_hackers_review.md) | 外部评审 (R1) | **PostgreSQL Hackers 首轮评审意见集**。尖锐指出了早期设计的 5 大核心缺陷：页面锁逆序死锁 (P0)、缺乏 Pin-count 保护致读越界 Panic (P0)、URQ 缺 WAL 致备机升主物理空洞 (P0)、5 块巨型 WAL 与整页镜像导致并行回放停顿 (P1)、污染 Session 全局变量 (P1)。 |
| [**`ubtree_shrink_postgres_hackers_round2_review.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_postgres_hackers_round2_review.md) | 外部评审 (R2) | **PostgreSQL Hackers 二轮评审意见**。评价状态转为 *Conditionally Acceptable*，高度肯定了两阶段解耦、URQ WAL 重做、Pin 屏障与局部变量隔离，针对边界悬空指针挂死、GUC 超时等边缘案例提出加固要求。 |
| [**`ubtree_shrink_postgres_hackers_fix.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_postgres_hackers_fix.md) | 架构修复 | **针对 Hackers 评审意见的重构修复实施方案**。详细记录了两阶段解耦、Pin-Count 屏障检测、`XLOG_UBTREE2_URQ_PURGE`、增量差量日志解耦与局部参数传参的修复细节。 |
| [**`ubtree_shrink_concurrency_formal_proof.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_concurrency_formal_proof.md) | 理论形式化证明 | **【形式化数学证明】** 包含四大定理严格推导：1. 无死锁（偏序归纳法证明）；2. 扫描完备性（正反向扫描零元组丢失证明）；3. 防 EOF 越界读双屏障安全证明；4. 崩溃恢复与主备元数据幂等性证明。 |
| [**`ubtree_shrink_full_code_review.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_full_code_review.md) | 源码审计 | **内核源码全量审计报告**。逐行审查加锁顺序、边界条件、内存泄漏、WAL 回放安全性与事务边界。 |

---

### 3. 发明专利提案与技术交底规划
将收缩特性的创新成果提炼为企业核心知识产权资产。

| 文件名称 | 提案数量 | 定位与核心内容摘要 |
| :--- | :--- | :--- |
| [**`ubtree_shrink_patent_proposals.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_patent_proposals.md) | **6 项发明专利** | **【技术资产】专利挖掘与技术交底书布局规划**。<br>包含：<br>1. *两阶段解耦 B-Link 树在线页搬迁协议* (核心协议 P0)<br>2. *多版本 B-Link 树内部节点分层搬迁方法* (拓扑突破 P0)<br>3. *物理截断边界悬空指针闭合方法* (防 Panic 安全 P1)<br>4. *引用计数屏障与微秒级锁升级截断方法* (并发控制 P1)<br>5. *主备复制索引回收队列水位同步与日志方法* (高可用 P1)<br>6. *边际效益衰减与轻量探查自适应收缩调度* (智能运维 P2) |

---

### 4. 性能评测与压测分析报告 (`perf/reports/`)
本模块汇集了不同阶段、不同维度的基准测试报告，覆盖时间提速比、物理压缩率、长周期高并发稳定性与 TPC-C 吞吐。

| 文件名称 | 评测场景 | 定位与核心内容摘要 |
| :--- | :--- | :--- |
| [**`perf_benchmark_report_v3.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/perf_benchmark_report_v3.md) | 7 大场景基准 | **【最新综合基准报告】** 对比 VACUUM FULL 与 REINDEX，收缩提速 3~55 倍，物理空间缩减 75%~89%。 |
| [**`longrun_stability_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/longrun_stability_report.md) | 生产级长周期高压 | **长时间混合负载稳定性报告**。180 秒持续压测（158 万写入、147 万删除、3.3 万查询、39 次在线收缩），达成 **0 死锁、0 崩溃、0 读穿 EOF，索引数据 100% 绝对一致**。 |
| [**`tpcc_shrink_comparison_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/tpcc_shrink_comparison_report.md) | TPC-C A/B 对比 | 30 分钟 TPC-C 测试，高频收缩组（2,168.5 tpmC）相比无收缩组（1,981.8 tpmC）**性能零损耗**，472 次收缩 0 故障。 |
| [**`tpcc_longrun_shrink_comparison_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/tpcc_longrun_shrink_comparison_report.md) | TPC-C 深度长周期 | TPC-C 场景下追加写负载特征及收缩调度优化分析。 |
| [**`adaptive_shrink_15min_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/adaptive_shrink_15min_report.md) | 滑动窗口业务 | 15 分钟自适应阈值触发长周期对比报告，验证防颠簸熔断器有效性。 |
| [**`ubtree_shrink_time_space_comparison_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/ubtree_shrink_time_space_comparison_report.md) | 时空量化 | 空间削减率与耗时加速比综合量化分析。 |
| [**`ubtree_shrink_comparison_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/ubtree_shrink_comparison_report.md) | 阶段对比 | 早期对比评测报告。 |
| [**`smoke_test_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/smoke_test_report.md) | 冒烟测试 | 基础功能与系统调用可用性快速核验。 |
| [**`scenario5_page_relocation_bug_analysis.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/scenario5_page_relocation_bug_analysis.md) | Bug 诊断 | 场景 5 散列中间空洞迁移时越界读 Bug 根因剖析与解决。 |
| [**`perf_v2_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/perf_v2_report.md) / [**`perf_v1.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/perf_v1.md) | 历史版本 | 早期评测基准历史归档。 |
| [**`ubtree_shrink_adaptive_threshold_benchmark_design.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/ubtree_shrink_adaptive_threshold_benchmark_design.md) | 方案设计 | 自适应阈值触发机制压测方案设计说明书。 |
| [**`ubtree_shrink_performance_report.md`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/ubtree_shrink_performance_report.md) | 性能总结 | 阶段性性能综合评估总结。 |

---

### 5. 基准测试套件与自动化脚本 (`perf/scripts/`)
本模块包含可直接在本地或测试集群执行的端到端测试与压测脚本。

| 文件名称 | 语言/类型 | 用途与执行方式说明 |
| :--- | :--- | :--- |
| [**`perf.sql`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/perf.sql) | SQL 脚本 | **7 大典型业务场景基准评测脚本**。覆盖单调递增主键、重度膨胀、散列死元、极端膨胀、中间空洞、FIFO 滑动窗口及高并发混合负载。 |
| [**`test_ubtree_shrink_longrun.py`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/test_ubtree_shrink_longrun.py) | Python 3 | **生产级高并发长时间混合负载稳定性验证套件**。模拟金融流水账本，并发执行 Ingest、Mutate、Query、Purger 与 Shrink。 |
| [**`run_perf_test.py`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/run_perf_test.py) | Python 3 | 7 大基准场景自动化执行与报告提取驱动。 |
| [**`run_tpcc_shrink_comparison.py`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/run_tpcc_shrink_comparison.py) | Python 3 | TPC-C A/B 对比测试执行与自动报告生成脚本。 |
| [**`run_tpcc_with_shrink.py`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/run_tpcc_with_shrink.py) | Python 3 | 周期性伴随收缩的 TPC-C 压测驱动器。 |
| [**`run_15min_benchmark.sh`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/run_15min_benchmark.sh) | Bash 脚本 | 15 分钟自适应长周期评测一键运行脚本。 |

---

### 6. 原始测试数据与执行日志 (`perf/logs/`)
本模块归档了各项测试真实运行所产出的原始控制台日志与输出流。

| 文件名称 | 格式/性质 | 内容简述 |
| :--- | :--- | :--- |
| [**`perf_results_latest.out`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/perf_results_latest.out) | SQL 执行日志 | 7 大基准测试场景全量最新成功执行日志。 |
| [**`perf_results_full.out`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/perf_results_full.out) | SQL 执行日志 | 早期全量执行日志（记录了修复前 read beyond EOF 的历史追踪）。 |
| [**`perf_results_internal_migration.out`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/perf_results_internal_migration.out) | SQL 执行日志 | 非叶子内部节点搬迁专项验证日志。 |
| [**`perf_results_phase1_2.out`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/perf_results_phase1_2.out) / [**`perf_results_phase3.out`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/perf_results_phase3.out) | SQL 执行日志 | Phase 1/2 离线收缩与 Phase 3 在线定向迁移验证日志。 |
| [**`tpcc_comparison.log`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/tpcc_comparison.log) / [**`tpcc_longrun_comparison.log`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/tpcc_longrun_comparison.log) | 性能测试日志 | TPC-C 对照测试完整过程日志。 |
| [**`adaptive_shrink_15min.log`**](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/logs/adaptive_shrink_15min.log) | 监控日志 | 15 分钟自适应阈值长周期运行日志。 |

---

## 三、 推荐阅读与研读路径

```
                      【技术全貌了解】
                             │
                             ▼
             ubtree_shrink_latest_architecture_design.md
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
 【内核实现与重构】    【性能表现与基准】    【知识产权申报】
        │                    │                    │
        ├─ reviews/hackers_review.md  ├─ reports/perf_v3.md   └─ patent_proposals.md
        ├─ reviews/hackers_fix.md     ├─ reports/longrun.md
        └─ reviews/code_review.md     └─ reports/tpcc.md
```

1. **架构师 / 评审专家**：
   - 首先阅读 [`ubtree_shrink_latest_architecture_design.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_latest_architecture_design.md) 获取全生命周期技术蓝图；
   - 随后参阅 [`ubtree_shrink_postgres_hackers_review.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_postgres_hackers_review.md) 与 [`ubtree_shrink_postgres_hackers_fix.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/reviews/ubtree_shrink_postgres_hackers_fix.md)，了解关键死锁与并发边界的重构推导；
   - 深入专项技术：[`ubtree_shrink_internal_page_migration_design.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_internal_page_migration_design.md) 与 [`ubtree_shrink_urq_compaction_design.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_design/ubtree_shrink_urq_compaction_design.md)。
2. **测试与性能调优工程师**：
   - 阅读最新综合性能报告 [`perf_benchmark_report_v3.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/perf_benchmark_report_v3.md)；
   - 阅读高并发长周期稳定性报告 [`longrun_stability_report.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/longrun_stability_report.md) 与 TPC-C 报告 [`tpcc_shrink_comparison_report.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/perf/reports/tpcc_shrink_comparison_report.md)。
3. **专利工程师 / 知识产权负责人**：
   - 重点阅读 [`ubtree_shrink_patent_proposals.md`](file:///home/fengyao/openGauss-server/ubtree_shrink_doc/ubtree_shrink_patent_proposals.md)，获取 6 项发明专利的完整权利要求书构想与对比现有技术的有益效果。

---

## 四、 压测与验证复现指引

### 1. 7 大场景全量基准测试
```bash
# 启动 gsql 执行全量场景并输出
gsql -d postgres -p 5432 -f /home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/perf.sql > perf_results.out
```

### 2. 长时间混合高压稳定性验证
```bash
# 运行 180 秒（或自定义时长）高并发综合稳定性压测
python3 /home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/test_ubtree_shrink_longrun.py \
  --duration 180 \
  --workers 4 \
  --output-report ubtree_shrink_doc/perf/reports/longrun_stability_report.md
```

### 3. TPC-C A/B 对照测试
```bash
# 执行伴随收缩的 TPC-C 压测
python3 /home/fengyao/openGauss-server/ubtree_shrink_doc/perf/scripts/run_tpcc_shrink_comparison.py \
  --duration 1800 \
  --shrink-interval 15
```
