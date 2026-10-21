/* PROJECT 2 — BRONZE GLOBAL CLOSEOUT (READ-ONLY); SSMS SQL SERVER */
USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;
PRINT '01 | ALL 14 BRONZE TARGET TABLES: SOURCE-BASED INITIAL COUNTS';
WITH expected AS (
 SELECT * FROM (VALUES
    (N'POSTGRES_OLTP', N'bronze.oltp_orders',CONVERT(bigint,200000)),
    (N'POSTGRES_OLTP', N'bronze.oltp_order_items',CONVERT(bigint,500000)),
    (N'POSTGRES_OLTP', N'bronze.oltp_customers',CONVERT(bigint,50000)),
    (N'POSTGRES_OLTP', N'bronze.oltp_products',CONVERT(bigint,3000)),
    (N'POSTGRES_OLTP', N'bronze.oltp_payments',CONVERT(bigint,215000)),
    (N'MYSQL_CRM', N'bronze.crm_customers',CONVERT(bigint,50000)),
    (N'MYSQL_CRM', N'bronze.crm_loyalty_accounts',CONVERT(bigint,35000)),
    (N'MYSQL_CRM', N'bronze.crm_loyalty_transactions',CONVERT(bigint,175000)),
    (N'MYSQL_CRM', N'bronze.crm_campaigns',CONVERT(bigint,120)),
    (N'MYSQL_CRM', N'bronze.crm_campaign_memberships',CONVERT(bigint,360000)),
    (N'MYSQL_CRM', N'bronze.crm_support_tickets',CONVERT(bigint,45000)),
    (N'PARTNER_SHIPPING_CSV',N'bronze.partner_shipments',CONVERT(bigint,120000)),
    (N'MOCK_RETURNS_API',N'bronze.returns_raw',CONVERT(bigint,22093)),
    (N'APPLICATION_EVENTS',N'bronze.app_events_raw',CONVERT(bigint,1630000))
 ) v(source_system,target_table,expected_rows)
)
SELECT * INTO #expected_targets FROM expected;

CREATE TABLE #target_actual (
  target_table nvarchar(200) NOT NULL PRIMARY KEY,
  actual_rows bigint NULL,
  notes nvarchar(100) NOT NULL
);
DECLARE @target nvarchar(200), @stmt nvarchar(max), @schema sysname, @table sysname;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT target_table FROM #expected_targets;
OPEN c;
FETCH NEXT FROM c INTO @target;
WHILE @@FETCH_STATUS=0
BEGIN
  SET @schema=PARSENAME(@target,2);
  SET @table=PARSENAME(@target,1);
  IF OBJECT_ID(QUOTENAME(@schema)+N'.'+QUOTENAME(@table),N'U') IS NULL
    INSERT INTO #target_actual(target_table,actual_rows,notes) VALUES(@target,NULL,N'MISSING TABLE');
  ELSE
  BEGIN
    SET @stmt=N'INSERT INTO #target_actual(target_table,actual_rows,notes) '
       + N'SELECT @name, COUNT_BIG(*), N''OK'' FROM '+QUOTENAME(@schema)+N'.'+QUOTENAME(@table);
    EXEC sp_executesql @stmt,N'@name nvarchar(200)',@name=@target;
  END;
  FETCH NEXT FROM c INTO @target;
END;
CLOSE c;
DEALLOCATE c;

SELECT e.source_system,e.target_table,e.expected_rows,a.actual_rows,
       CASE WHEN a.actual_rows=e.expected_rows THEN N'PASS' ELSE N'FAIL' END AS row_count_check,
       a.notes
FROM #expected_targets e JOIN #target_actual a ON a.target_table=e.target_table
ORDER BY e.source_system,e.target_table;

PRINT '02 | SOURCE GROUP TOTALS';
SELECT e.source_system,SUM(e.expected_rows) AS expected_rows,SUM(a.actual_rows) AS actual_rows,
       CASE WHEN COUNT(a.actual_rows)=COUNT_BIG(*) AND SUM(e.expected_rows)=SUM(a.actual_rows)
            THEN 'PASS' ELSE 'FAIL' END AS source_group_count_check
FROM #expected_targets e JOIN #target_actual a ON a.target_table=e.target_table
GROUP BY e.source_system
ORDER BY e.source_system;

PRINT '03 | ALL SOURCES GRAND TOTAL; EXPECT 3,405,213';
SELECT SUM(e.expected_rows) AS manifest_and_source_expected,
       SUM(a.actual_rows) AS warehouse_actual,
       CASE WHEN COUNT(a.actual_rows)=COUNT_BIG(*) AND SUM(e.expected_rows)=SUM(a.actual_rows)
         THEN 'PASS' ELSE 'FAIL' END AS grand_total_check
FROM #expected_targets e JOIN #target_actual a ON a.target_table=e.target_table;

PRINT '04 | LATEST AUDIT PER TARGET';
WITH latest AS (
  SELECT l.*, ROW_NUMBER() OVER (PARTITION BY target_object ORDER BY run_id DESC) AS rn
  FROM control.etl_run_log l
)
SELECT e.source_system,e.target_table,l.run_id,l.pipeline_name,l.status,
       l.rows_processed,l.start_time,l.end_time,l.execution_id,l.error_message,
       CASE WHEN l.status=N'SUCCESS' AND l.rows_processed=e.expected_rows
            THEN 'PASS' ELSE 'REVIEW' END AS audit_check
FROM #expected_targets e LEFT JOIN latest l ON l.target_object=e.target_table AND l.rn=1
ORDER BY e.source_system,e.target_table;

PRINT '05 | HISTORICAL UNFINISHED RUNS: REVIEW ONLY, DO NOT MODIFY AUTOMATICALLY';
SELECT run_id,pipeline_name,target_object,start_time,status,execution_id
FROM control.etl_run_log
WHERE status=N'RUNNING' AND end_time IS NULL
ORDER BY start_time;

DROP TABLE #expected_targets;
DROP TABLE #target_actual;
GO
