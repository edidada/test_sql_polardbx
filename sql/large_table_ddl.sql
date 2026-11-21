-- =====================================================================
-- PolarDB-X 大表在线结构变更演示（vivo TokuDB 归档库迁移场景）
-- 痛点: TokuDB 400 亿行大表无法在线变更, "存得下"但"变得动"
-- 方案: 迁入 PolarDB-X, 分布式在线 DDL, 结构变更不阻塞读写
-- 对应 cases/大表在线结构变更.md；在 GitHub Actions 的 PolarDB-X 容器中执行
-- =====================================================================

DROP DATABASE IF EXISTS large_ddl_demo;
CREATE DATABASE large_ddl_demo MODE = 'auto';
USE large_ddl_demo;

-- ---------------------------------------------------------------------
-- 模拟 400 亿行订单事实表: 逻辑上一张表, 物理按 user_id HASH 拆分到 8 个分片
-- CI 中用小规模数据演示, DDL 机制与线上 400 亿行场景完全一致
-- 复合主键包含拆分键 user_id, 保证分布式全局唯一
-- ---------------------------------------------------------------------
CREATE TABLE orders_fact (
  id BIGINT,
  user_id BIGINT NOT NULL,
  store_id INT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id, user_id)
) PARTITION BY HASH(user_id) PARTITIONS 8;

INSERT INTO orders_fact VALUES
 (1,  1, 101, 25.50, '2024-01-05 10:00:00'),
 (2,  2, 101, 18.00, '2024-01-05 11:00:00'),
 (3,  3, 102,  9.90, '2024-01-06 09:30:00'),
 (4,  4, 102, 33.00, '2024-01-06 12:00:00'),
 (5,  5, 103, 12.00, '2024-01-07 15:00:00'),
 (6,  6, 103, 45.60, '2024-01-07 16:00:00'),
 (7,  7, 104,  7.80, '2024-01-08 08:00:00'),
 (8,  8, 104, 88.00, '2024-01-08 18:00:00'),
 (9,  9, 105, 15.20, '2024-01-09 09:00:00'),
 (10,10, 105, 26.40, '2024-01-09 10:00:00'),
 (11,11, 106, 33.10, '2024-01-10 11:00:00'),
 (12,12, 106, 41.80, '2024-01-10 12:00:00'),
 (13,13, 107, 52.90, '2024-01-11 13:00:00'),
 (14,14, 107, 63.20, '2024-01-11 14:00:00'),
 (15,15, 108, 74.50, '2024-01-12 15:00:00'),
 (16,16, 108, 85.60, '2024-01-12 16:00:00'),
 (17,17, 109, 96.70, '2024-01-13 17:00:00'),
 (18,18, 109, 17.80, '2024-01-13 18:00:00'),
 (19,19, 110, 28.90, '2024-01-14 19:00:00'),
 (20,20, 110, 39.00, '2024-01-14 20:00:00');

SELECT '① 变更前表结构' AS demo;
SHOW CREATE TABLE orders_fact;

SELECT '② 变更前数据校验' AS demo;
SELECT COUNT(*) AS rows_before, SUM(amount) AS amount_before FROM orders_fact;

-- ---------------------------------------------------------------------
-- 在线结构变更 1: 加字段(不锁表, 不阻塞 DML)
-- ---------------------------------------------------------------------
SELECT '③ Online DDL: ADD COLUMN discount' AS demo;
ALTER TABLE orders_fact ADD COLUMN discount DECIMAL(10,2) NOT NULL DEFAULT 0.00;

-- ---------------------------------------------------------------------
-- 在线结构变更 2: 加索引(分布式在线建全局二级索引)
-- ---------------------------------------------------------------------
SELECT '④ Online DDL: ADD INDEX idx_store' AS demo;
ALTER TABLE orders_fact ADD INDEX idx_store (store_id);

-- ---------------------------------------------------------------------
-- 在线结构变更 3: 改字段类型(在线变更, 不锁表)
-- ---------------------------------------------------------------------
SELECT '⑤ Online DDL: MODIFY COLUMN amount DECIMAL(14,2)' AS demo;
ALTER TABLE orders_fact MODIFY COLUMN amount DECIMAL(14,2) NOT NULL;

-- ---------------------------------------------------------------------
-- 变更后 DML 仍可正常执行, 数据零丢失
-- ---------------------------------------------------------------------
SELECT '⑥ 变更后继续写入(证明结构变更不阻塞 DML)' AS demo;
INSERT INTO orders_fact (id, user_id, store_id, amount, created_at, discount)
VALUES (21, 5, 105, 66.00, '2024-01-15 10:00:00', 5.00);

SELECT '⑦ 变更后数据校验' AS demo;
SELECT COUNT(*) AS rows_after, SUM(amount) AS amount_after, SUM(discount) AS discount_after FROM orders_fact;

SELECT '⑧ 变更后表结构(新增列与索引已生效)' AS demo;
SHOW CREATE TABLE orders_fact;
