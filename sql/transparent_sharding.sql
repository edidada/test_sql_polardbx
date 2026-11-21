-- =====================================================================
-- PolarDB-X 透明分布式 vs 应用层分库分表 演示（好想来零食量贩场景）
-- 迁移前: 自建分库分表, 分片规则写死在业务代码 -> 运维/扩容困难
-- 迁移后: PolarDB-X 分片规则收敛到 DDL, 业务代码零耦合, 在线扩容
-- 对应 cases/透明分布式与分库分表迁移.md；在 GitHub Actions 的 PolarDB-X 容器中执行
-- =====================================================================

DROP DATABASE IF EXISTS haoxianglai_demo;
CREATE DATABASE haoxianglai_demo MODE = 'auto';
USE haoxianglai_demo;

-- =====================================================================
-- 第一部分: 【迁移前】应用层分库分表 —— 分片逻辑写在业务代码里
-- =====================================================================
SELECT '=== 迁移前: 应用层分库分表(分片规则写死在业务代码) ===' AS demo;

-- 业务代码里的分片规则: shard = user_id % 4，据此手写 4 张物理表
CREATE TABLE orders_app_shard_0 (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, store_id INT, amount DECIMAL(10,2), created_at DATETIME);
CREATE TABLE orders_app_shard_1 (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, store_id INT, amount DECIMAL(10,2), created_at DATETIME);
CREATE TABLE orders_app_shard_2 (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, store_id INT, amount DECIMAL(10,2), created_at DATETIME);
CREATE TABLE orders_app_shard_3 (id BIGINT PRIMARY KEY, user_id BIGINT NOT NULL, store_id INT, amount DECIMAL(10,2), created_at DATETIME);

-- 写入: 业务代码必须先算 user_id % 4, 再分别 INSERT 到对应物理表
INSERT INTO orders_app_shard_0 VALUES (1004, 4, 101, 25.50, NOW());
INSERT INTO orders_app_shard_1 VALUES (1001, 1, 101, 18.00, NOW());
INSERT INTO orders_app_shard_2 VALUES (1002, 2, 102,  9.90, NOW());
INSERT INTO orders_app_shard_3 VALUES (1003, 3, 102, 33.00, NOW());
INSERT INTO orders_app_shard_0 VALUES (1008, 8, 103, 12.00, NOW());

-- 痛点1: 单分片点查, 业务代码要先算分片号再拼表名
SELECT '① 点查: 代码先算 user_id%4=0 才知道要查 shard_0' AS demo;
SELECT * FROM orders_app_shard_0 WHERE user_id = 4;

-- 痛点2: 全局统计, 代码必须 UNION ALL 所有分片后再聚合
SELECT '② 全局统计: 代码 UNION ALL 全部 4 张分片表再 SUM' AS demo;
SELECT COUNT(*) AS total_orders, SUM(amount) AS total_amount FROM (
  SELECT amount FROM orders_app_shard_0
  UNION ALL SELECT amount FROM orders_app_shard_1
  UNION ALL SELECT amount FROM orders_app_shard_2
  UNION ALL SELECT amount FROM orders_app_shard_3
) t;

-- 痛点3: 扩容 %4 -> %8 需新建分片、历史数据重分布、分片规则与代码一起改并发版
SELECT '③ 扩容: %4 -> %8 需建新表+数据迁移+改代码, 强耦合' AS demo;


-- =====================================================================
-- 第二部分: 【迁移后】PolarDB-X 透明分布式 —— 分片规则收敛到 DDL
-- =====================================================================
SELECT '=== 迁移后: PolarDB-X 透明分布式(业务代码零耦合) ===' AS demo;

-- 一张逻辑表即可, 分片规则写在 DDL 的 PARTITION BY 里; 业务代码不再感知分片
-- 主键需包含拆分键以保证全局唯一, 故使用复合主键 (id, user_id)
CREATE TABLE orders (
  id BIGINT,
  user_id BIGINT NOT NULL,
  store_id INT,
  amount DECIMAL(10,2),
  created_at DATETIME,
  PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 4;

-- 写入: 业务代码只写逻辑表 orders, 由内核自动路由到对应分片
INSERT INTO orders VALUES
 (1004, 4, 101, 25.50, NOW()),
 (1001, 1, 101, 18.00, NOW()),
 (1002, 2, 102,  9.90, NOW()),
 (1003, 3, 102, 33.00, NOW()),
 (1008, 8, 103, 12.00, NOW());

-- 收益1: 点查无需算分片、无需拼表名, 透明路由
SELECT '④ 点查: 直接查逻辑表, 内核按 user_id 透明路由' AS demo;
SELECT * FROM orders WHERE user_id = 4;

-- 收益2: 全局统计一条 SQL 透明聚合, 不再手写 UNION ALL
SELECT '⑤ 全局统计: 一条 SQL 透明聚合所有分片' AS demo;
SELECT COUNT(*) AS total_orders, SUM(amount) AS total_amount FROM orders;

-- 收益3: EXPLAIN 可见路由被下推到存储节点(DN), 业务无感
SELECT '⑥ 透明路由执行计划(EXPLAIN)' AS demo;
EXPLAIN SELECT * FROM orders WHERE user_id = 4;

-- 收益4: 在线扩容 —— 仅改分区数, 业务代码零改动, 数据自动重分布
SELECT '⑦ 在线扩容: 4 -> 8 分区, 业务代码不变' AS demo;
ALTER TABLE orders PARTITION BY HASH(user_id) PARTITIONS 8;

SELECT '⑧ 扩容后数据不丢, 业务 SQL 完全不用改' AS demo;
SELECT COUNT(*) AS total_orders_after_scale, SUM(amount) AS total_amount_after_scale FROM orders;

-- 收益5: 维度表用广播表(BROADCAST), 跨分片 JOIN 透明下推
SELECT '⑨ 跨分片 JOIN 广播维度表: 透明下推到各分片本地执行' AS demo;
CREATE TABLE dim_store (store_id INT PRIMARY KEY, store_name VARCHAR(50)) BROADCAST;
INSERT INTO dim_store VALUES (101, '杭州旗舰店'), (102, '上海南京路店'), (103, '成都春熙路店');
SELECT o.id, o.user_id, s.store_name, o.amount
FROM orders o JOIN dim_store s ON o.store_id = s.store_id
ORDER BY o.id;
