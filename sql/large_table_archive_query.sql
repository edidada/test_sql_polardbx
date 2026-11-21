-- =====================================================================
-- PolarDB-X 大表归档查询演示（vivo TokuDB 归档库迁移场景）
-- 痛点: TokuDB 归档库只解决"存得下", 跨年归档查询慢且难维护
-- 方案: PolarDB-X 按时间 RANGE 分区, 归档查询靠分区裁剪只扫目标分区
-- 对应 cases/大表归档查询.md；在 GitHub Actions 的 PolarDB-X 容器中执行
-- =====================================================================

DROP DATABASE IF EXISTS archive_query_demo;
CREATE DATABASE archive_query_demo MODE = 'auto';
USE archive_query_demo;

-- 归档事实表: 按 arch_month(YYYYMM) 做 RANGE 分区, 历史数据按月归档
-- 拆分键 arch_month 必须包含在主键中, 保证分布式全局唯一
CREATE TABLE orders_archive (
  id BIGINT,
  user_id BIGINT NOT NULL,
  store_id INT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  arch_month INT NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (id, arch_month)
) PARTITION BY RANGE(arch_month) (
  PARTITION p2023 VALUES LESS THAN (202401),
  PARTITION p2024 VALUES LESS THAN (202501),
  PARTITION p2025 VALUES LESS THAN (202601),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- 模拟跨 2023~2026 的归档数据, 202601 落入 pmax
INSERT INTO orders_archive VALUES
 (1,  1, 101, 25.50, 202301, '2023-01-05 10:00:00'),
 (2,  2, 101, 18.00, 202306, '2023-06-05 11:00:00'),
 (3,  3, 102,  9.90, 202312, '2023-12-06 09:30:00'),
 (4,  4, 102, 33.00, 202401, '2024-01-06 12:00:00'),
 (5,  8, 103, 12.00, 202407, '2024-07-07 15:00:00'),
 (6,  9, 103, 45.60, 202412, '2024-12-07 16:00:00'),
 (7, 10, 104,  7.80, 202503, '2025-03-08 08:00:00'),
 (8, 16, 104, 88.00, 202511, '2025-11-08 18:00:00'),
 (9, 17, 105, 66.00, 202601, '2026-01-09 10:00:00');

SELECT '① 归档表分区定义' AS demo;
SHOW CREATE TABLE orders_archive;

SELECT '② 单月归档查询: 分区裁剪只扫 p2024' AS demo;
EXPLAIN SELECT id, user_id, amount, created_at
FROM orders_archive WHERE arch_month = 202401;
SELECT id, user_id, amount, created_at
FROM orders_archive WHERE arch_month = 202401;

SELECT '③ 跨年归档区间查询: 只扫 2023/2024 分区' AS demo;
EXPLAIN SELECT COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_archive WHERE arch_month BETWEEN 202301 AND 202412;
SELECT COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_archive WHERE arch_month BETWEEN 202301 AND 202412;

SELECT '④ 按归档月份聚合统计' AS demo;
SELECT arch_month, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_archive GROUP BY arch_month ORDER BY arch_month;

SELECT '⑤ 归档数据总量(全分区)' AS demo;
SELECT COUNT(*) AS total_rows, SUM(amount) AS total_amount FROM orders_archive;
