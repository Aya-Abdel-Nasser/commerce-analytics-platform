-- PROJECT 2 | MySQL CRM | SOURCE VALIDATION
-- Run in MySQL Workbench (commerce_crm_dev), NOT SQL Server.
-- Purpose: initial-load counts, metadata, PK/FK integrity and per-column NULL counts.
-- Read-only for business tables. Dynamic SQL uses PREPARE and session variables only.

USE commerce_crm_dev;
SET SESSION group_concat_max_len = 1000000;

-- 01 | Counts vs known initial-load baseline
WITH row_counts AS (
  SELECT 'crm_customers' AS table_name, 50000 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_customers` UNION ALL
  SELECT 'crm_loyalty_accounts' AS table_name, 35000 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_loyalty_accounts` UNION ALL
  SELECT 'crm_loyalty_transactions' AS table_name, 175000 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_loyalty_transactions` UNION ALL
  SELECT 'crm_campaigns' AS table_name, 120 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_campaigns` UNION ALL
  SELECT 'crm_campaign_memberships' AS table_name, 360000 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_campaign_memberships` UNION ALL
  SELECT 'crm_support_tickets' AS table_name, 45000 AS expected_rows, COUNT(*) AS actual_rows FROM commerce_crm_dev.`crm_support_tickets`
)
SELECT table_name, expected_rows, actual_rows,
       actual_rows - expected_rows AS difference,
       IF(actual_rows = expected_rows, 'PASS', 'REVIEW') AS count_check
FROM row_counts
UNION ALL
SELECT 'ALL_TABLES', SUM(expected_rows), SUM(actual_rows),
       SUM(actual_rows - expected_rows),
       IF(SUM(actual_rows - expected_rows) = 0, 'PASS', 'REVIEW')
FROM row_counts;

-- 02 | Source column metadata
SELECT table_name, ordinal_position, column_name, data_type, is_nullable,
       character_maximum_length, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'commerce_crm_dev' AND table_name IN ('crm_customers', 'crm_loyalty_accounts', 'crm_loyalty_transactions', 'crm_campaigns', 'crm_campaign_memberships', 'crm_support_tickets')
ORDER BY table_name, ordinal_position;

-- 03 | Source primary keys and foreign keys (includes composite keys)
SELECT table_name, constraint_name, column_name, ordinal_position,
       referenced_table_schema, referenced_table_name, referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = 'commerce_crm_dev' AND table_name IN ('crm_customers', 'crm_loyalty_accounts', 'crm_loyalty_transactions', 'crm_campaigns', 'crm_campaign_memberships', 'crm_support_tickets')
  AND (constraint_name = 'PRIMARY' OR referenced_table_name IS NOT NULL)
ORDER BY table_name, constraint_name, ordinal_position;

-- 04 | Dynamic primary-key null/duplicate checks
-- Missing tables in this result have no discoverable PRIMARY KEY; review section 03.
SELECT GROUP_CONCAT(
    CONCAT(
      'SELECT ', QUOTE(pk.table_name), ' AS table_name, ',
      QUOTE(pk.key_columns), ' AS pk_columns, ',
      '(SELECT COUNT(*) FROM `commerce_crm_dev`.`', REPLACE(pk.table_name,'`','``'),
      '` WHERE ', pk.null_condition, ') AS null_key_rows, ',
      '(SELECT COUNT(*) FROM (SELECT 1 FROM `commerce_crm_dev`.`',
      REPLACE(pk.table_name,'`','``'), '` GROUP BY ', pk.key_columns,
      ' HAVING COUNT(*) > 1) AS d) AS duplicate_key_groups'
    ) ORDER BY pk.table_name SEPARATOR ' UNION ALL '
) INTO @crm_pk_sql
FROM (
  SELECT k.table_name,
         GROUP_CONCAT(CONCAT('`', REPLACE(k.column_name,'`','``'), '`')
                      ORDER BY k.ordinal_position SEPARATOR ', ') AS key_columns,
         GROUP_CONCAT(CONCAT('`', REPLACE(k.column_name,'`','``'), '` IS NULL')
                      ORDER BY k.ordinal_position SEPARATOR ' OR ') AS null_condition
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage k
    ON k.constraint_schema = tc.constraint_schema
   AND k.constraint_name = tc.constraint_name
   AND k.table_schema = tc.table_schema AND k.table_name = tc.table_name
  WHERE tc.table_schema = 'commerce_crm_dev'
    AND tc.constraint_type = 'PRIMARY KEY' AND k.table_name IN ('crm_customers', 'crm_loyalty_accounts', 'crm_loyalty_transactions', 'crm_campaigns', 'crm_campaign_memberships', 'crm_support_tickets')
  GROUP BY k.table_name
) AS pk;
SET @crm_pk_sql = COALESCE(@crm_pk_sql,
  'SELECT ''NO_SOURCE_PRIMARY_KEYS_FOUND'' AS table_name, NULL AS pk_columns, NULL AS null_key_rows, NULL AS duplicate_key_groups');
PREPARE crm_pk_stmt FROM @crm_pk_sql;
EXECUTE crm_pk_stmt;
DEALLOCATE PREPARE crm_pk_stmt;

-- 05 | Dynamic column-level NULL profile; compare to warehouse profile.
-- This reads each source column and may take time on the larger tables.
SELECT GROUP_CONCAT(
  CONCAT('SELECT ', QUOTE(c.table_name), ' AS table_name, ',
         QUOTE(c.column_name), ' AS column_name, ',
         'COUNT(*) AS row_count, ',
         'SUM(CASE WHEN `', REPLACE(c.column_name,'`','``'),
         '` IS NULL THEN 1 ELSE 0 END) AS null_count ',
         'FROM `commerce_crm_dev`.`', REPLACE(c.table_name,'`','``'), '`')
  ORDER BY c.table_name, c.ordinal_position SEPARATOR ' UNION ALL '
) INTO @crm_profile_sql
FROM information_schema.columns AS c
WHERE c.table_schema = 'commerce_crm_dev' AND c.table_name IN ('crm_customers', 'crm_loyalty_accounts', 'crm_loyalty_transactions', 'crm_campaigns', 'crm_campaign_memberships', 'crm_support_tickets');
SET @crm_profile_sql = COALESCE(@crm_profile_sql,
  'SELECT ''NO_TABLES_FOUND'' AS table_name, NULL AS column_name, NULL AS row_count, NULL AS null_count');
PREPARE crm_profile_stmt FROM @crm_profile_sql;
EXECUTE crm_profile_stmt;
DEALLOCATE PREPARE crm_profile_stmt;
