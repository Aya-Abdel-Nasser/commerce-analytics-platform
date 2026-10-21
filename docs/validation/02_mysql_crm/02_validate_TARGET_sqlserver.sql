-- PROJECT 2 | SQL Server Warehouse | MySQL CRM TARGET VALIDATION
-- Run in SSMS or Azure Data Studio against commerce_warehouse_dev.
-- Read-only for bronze + control tables. Temporary #column_profile is session-scoped.
-- Each expected count is from the initial load baseline (not an ongoing CDC target).
-- IMPORTANT: Do not run another INSERT load just to test counts.

USE commerce_warehouse_dev;
GO

-- 01 | Warehouse Bronze row counts vs source initial-load baseline
WITH row_counts AS (
    SELECT N'crm_customers' AS table_name, CONVERT(bigint,50000) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_customers UNION ALL
    SELECT N'crm_loyalty_accounts' AS table_name, CONVERT(bigint,35000) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_loyalty_accounts UNION ALL
    SELECT N'crm_loyalty_transactions' AS table_name, CONVERT(bigint,175000) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_loyalty_transactions UNION ALL
    SELECT N'crm_campaigns' AS table_name, CONVERT(bigint,120) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_campaigns UNION ALL
    SELECT N'crm_campaign_memberships' AS table_name, CONVERT(bigint,360000) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_campaign_memberships UNION ALL
    SELECT N'crm_support_tickets' AS table_name, CONVERT(bigint,45000) AS expected_rows, COUNT_BIG(*) AS actual_rows FROM bronze.crm_support_tickets
)
SELECT table_name, expected_rows, actual_rows,
       actual_rows - expected_rows AS difference,
       CASE WHEN actual_rows = expected_rows THEN 'PASS' ELSE 'REVIEW' END AS count_check
FROM row_counts
UNION ALL
SELECT N'ALL_TABLES', SUM(expected_rows), SUM(actual_rows),
       SUM(actual_rows - expected_rows),
       CASE WHEN SUM(actual_rows - expected_rows) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM row_counts;

-- 02 | Target schema metadata (mapping data types may legitimately change)
SELECT t.name AS table_name, c.column_id AS ordinal_position,
       c.name AS column_name, ty.name AS sql_server_data_type,
       c.is_nullable, c.max_length, c.precision, c.scale
FROM sys.schemas s
JOIN sys.tables t ON t.schema_id = s.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE s.name = N'bronze' AND t.name IN (N'crm_customers', N'crm_loyalty_accounts', N'crm_loyalty_transactions', N'crm_campaigns', N'crm_campaign_memberships', N'crm_support_tickets')
ORDER BY t.name, c.column_id;

-- 03 | Target constraints (Bronze may intentionally have no PK/FK constraints)
SELECT t.name AS table_name, kc.name AS constraint_name,
       kc.type_desc AS constraint_type, c.name AS key_column,
       ic.key_ordinal
FROM sys.key_constraints kc
JOIN sys.tables t ON t.object_id = kc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = t.object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = ic.column_id
WHERE s.name = N'bronze' AND t.name IN (N'crm_customers', N'crm_loyalty_accounts', N'crm_loyalty_transactions', N'crm_campaigns', N'crm_campaign_memberships', N'crm_support_tickets')
ORDER BY t.name, kc.name, ic.key_ordinal;

-- 04 | Column-level NULL profile. Pair table+column+null_count with SOURCE report.
IF OBJECT_ID('tempdb..#column_profile') IS NOT NULL DROP TABLE #column_profile;
CREATE TABLE #column_profile (
    table_name sysname, column_name sysname,
    row_count bigint, null_count bigint
);
DECLARE @table sysname, @column sysname, @sql nvarchar(max);
DECLARE profile_cur CURSOR LOCAL FAST_FORWARD FOR
  SELECT t.name, c.name
  FROM sys.schemas s
  JOIN sys.tables t ON t.schema_id = s.schema_id
  JOIN sys.columns c ON c.object_id = t.object_id
  WHERE s.name = N'bronze' AND t.name IN (N'crm_customers', N'crm_loyalty_accounts', N'crm_loyalty_transactions', N'crm_campaigns', N'crm_campaign_memberships', N'crm_support_tickets')
  ORDER BY t.name, c.column_id;
OPEN profile_cur;
FETCH NEXT FROM profile_cur INTO @table, @column;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'INSERT INTO #column_profile (table_name,column_name,row_count,null_count) '
      + N'SELECT @t, @c, COUNT_BIG(*), COALESCE(SUM(CONVERT(bigint, CASE WHEN '
      + QUOTENAME(@column) + N' IS NULL THEN 1 ELSE 0 END)),0) '
      + N'FROM bronze.' + QUOTENAME(@table) + N';';
    EXEC sys.sp_executesql @sql,
         N'@t sysname, @c sysname', @t = @table, @c = @column;
    FETCH NEXT FROM profile_cur INTO @table, @column;
END
CLOSE profile_cur;
DEALLOCATE profile_cur;
SELECT table_name, column_name, row_count, null_count
FROM #column_profile ORDER BY table_name, column_name;

-- 05 | Audit reconciliation: review matching pipeline runs.
-- Review only: RUNNING/FAILED can be historical and should not be deleted.
SELECT run_id, execution_id, pipeline_name, source_system, source_object,
       target_object, start_time, end_time, status, rows_processed, error_message
FROM control.etl_run_log
WHERE pipeline_name LIKE N'mt_bronze_mysql_crm_%'
ORDER BY run_id DESC;

-- Interpretation:
-- PASS count & matching NULL profile: baseline structure/volume checks passed.
-- Still NOT a proof of full row-by-row equality across database engines.
-- For full data equality, compare source/target PKs and all mapped values using
-- a deterministic cross-system comparison job, after inspecting actual key names.
