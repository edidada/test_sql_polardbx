-- =====================================================================
-- PolarDB-X 部门树递归查询演示（含广播表与拆分表两种建表方式）
-- 对应 cases/部门树查询.md；在 GitHub Actions 的 PolarDB-X 容器中执行
-- =====================================================================

DROP DATABASE IF EXISTS dept_demo;
CREATE DATABASE dept_demo MODE = 'auto';
USE dept_demo;

-- ---------- 建表1: BROADCAST 广播表(树查询最优) ----------
CREATE TABLE departments (
  id INT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  parent_id INT NULL
) BROADCAST;

INSERT INTO departments (id, name, parent_id) VALUES
(1,  '集团公司',   NULL),
(2,  '技术部',     1),
(3,  '财务部',     1),
(4,  '人事部',     1),
(10, '后端开发组', 2),
(11, '前端开发组', 2),
(12, '测试组',     2),
(20, '会计组',     3),
(21, '出纳组',     3),
(100,'Java小组',   10),
(101,'Go小组',     10),
(102,'Vue小组',    11);

-- ---------- ① 向下查子树（带层级 + 路径） ----------
SELECT '① 技术部及所有下级(广播表+递归CTE)' AS demo;
WITH RECURSIVE dept_tree AS (
    SELECT id, name, parent_id, 1 AS level,
           CAST(name AS CHAR(200)) AS path
    FROM departments WHERE id = 2
    UNION ALL
    SELECT d.id, d.name, d.parent_id, dt.level + 1,
           CONCAT(dt.path, ' > ', d.name)
    FROM departments d INNER JOIN dept_tree dt ON d.parent_id = dt.id
)
SELECT id, parent_id, level, path FROM dept_tree ORDER BY path;

-- ---------- ② 自底向上追溯 ----------
SELECT '② Java小组向上追溯' AS demo;
WITH RECURSIVE up_chain AS (
    SELECT id, name, parent_id, 1 AS level FROM departments WHERE id = 100
    UNION ALL
    SELECT d.id, d.name, d.parent_id, u.level + 1
    FROM departments d INNER JOIN up_chain u ON d.id = u.parent_id
)
SELECT id, name, parent_id, level FROM up_chain;

-- ---------- ③ 各部门子孙节点数统计 ----------
SELECT '③ 各部门子孙节点数' AS demo;
WITH RECURSIVE sub AS (
    SELECT id, id AS root_id FROM departments
    UNION ALL
    SELECT d.id, s.root_id FROM departments d INNER JOIN sub s ON d.parent_id = s.id
)
SELECT root_id, COUNT(*) - 1 AS descendant_count
FROM sub GROUP BY root_id ORDER BY root_id;

-- ---------- ④ 建表2: HASH 拆分表, 验证拆分表上的递归查询 ----------
SELECT '④ 拆分表(HASH分区)上同样递归' AS demo;
CREATE TABLE departments_split (
  id INT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  parent_id INT NULL,
  KEY idx_parent_id (parent_id)
) PARTITION BY HASH(id) PARTITIONS 4;

INSERT INTO departments_split SELECT * FROM departments;

WITH RECURSIVE dept_tree AS (
    SELECT id, name, parent_id, 1 AS level FROM departments_split WHERE id = 2
    UNION ALL
    SELECT d.id, d.name, d.parent_id, dt.level + 1
    FROM departments_split d INNER JOIN dept_tree dt ON d.parent_id = dt.id
)
SELECT COUNT(*) AS split_table_nodes FROM dept_tree;

-- ---------- ⑤ 深度限制防死循环 ----------
SELECT '⑤ 深度限制' AS demo;
WITH RECURSIVE dept_tree AS (
    SELECT id, name, 1 AS level FROM departments WHERE id = 2
    UNION ALL
    SELECT d.id, d.name, dt.level + 1
    FROM departments d INNER JOIN dept_tree dt ON d.parent_id = dt.id
    WHERE dt.level < 2
)
SELECT * FROM dept_tree;
