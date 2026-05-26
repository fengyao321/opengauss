-- 前置条件1：安装gv_graph插件
DROP EXTENSION IF EXISTS gv_index CASCADE;
CREATE EXTENSION gv_index;
-- 前置条件2：设置enable_indexscan_optimization为on
SET enable_indexscan_optimization = on;

-- 1. 验证访问方法
SELECT amname FROM pg_am WHERE amname = 'gv_graph';

-- 2. 创建表和索引（观察回显：ambuild被调用）
DROP TABLE IF EXISTS test_graph;
CREATE TABLE test_graph (id int, repr vector(128)) WITH (storage_type=ustore);
\copy test_graph from '/your/path/to/sift1b_1w.csv';

CREATE INDEX test_graph_index ON test_graph USING gv_graph (repr vector_l2_ops) WITH (graph_degree=48, quantization_type=lvq, subgraph_count=2, num_parallels=32);

-- 3. 搜索数据（观察回显：amgettuple被调用）
set gv_graph_nprobes=256;

SELECT /* +indexscan(test_graph test_graph_index) */ FROM test_graph ORDER BY "repr" <-> (SELECT repr FROM test_graph WHERE id=0) LIMIT 10;

-- 4. 插入数据（观察回显：aminsert被调用）


-- 5. 删除数据（观察回显：amdelete被调用）


-- 6. vacuum数据（观察回显：amvacuum被调用）