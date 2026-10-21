/*
  Commerce Analytics Platform - Control Log Diagnostic (READ ONLY)
  Scope: review control.etl_run_log and historical run_id 8 / 9.
  No INSERT, UPDATE, DELETE, DDL, or ETL replay is executed.
  Run in SQL Server Management Studio against the current LOCAL warehouse.
  Save all result sets + Informatica Monitor run history for correlation.
  Last reviewed: 2026-10-16
*/
USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;

IF OBJECT_ID(N'control.etl_run_log', N'U') IS NULL
    THROW 51001, 'Missing control.etl_run_log: verify database, schema and table before diagnosing.', 1;

PRINT '01 | AUDIT STRUCTURE -- fields/types available for stored-procedure inspection';
SELECT c.column_id, c.name AS column_name, t.name AS data_type,
       c.max_length, c.is_nullable, c.is_identity
FROM sys.columns AS c
JOIN sys.types AS t ON c.user_type_id=t.user_type_id
WHERE c.object_id=OBJECT_ID(N'control.etl_run_log',N'U')
ORDER BY c.column_id;

PRINT '02 | RUN 8 AND RUN 9 -- reported as historical RUNNING attempts';
SELECT run_id, execution_id, pipeline_name, source_system, source_object,
       target_object, start_time, end_time, status, rows_processed,
       error_message
FROM control.etl_run_log
WHERE run_id IN (8,9)
ORDER BY run_id;

PRINT '03 | ALL CURRENT RUNNING RECORDS -- distinguish recent runs from stale history in Monitor';
SELECT run_id, execution_id, pipeline_name, source_system, source_object,
       target_object, start_time, end_time, status, rows_processed,
       error_message
FROM control.etl_run_log
WHERE UPPER(LTRIM(RTRIM(CONVERT(nvarchar(40),status)))) = N'RUNNING'
ORDER BY start_time, run_id;

PRINT '04 | AUDIT STATE INVARIANTS -- anomalies only (inspect, do not auto-fix)';
WITH normalized AS (
    SELECT run_id, execution_id, pipeline_name, target_object,
           start_time, end_time, status, rows_processed, error_message,
           UPPER(LTRIM(RTRIM(CONVERT(nvarchar(40), status)))) AS normalized_status
    FROM control.etl_run_log
), exceptions AS (
    SELECT *,
      CASE
        WHEN end_time < start_time THEN N'END_BEFORE_START'
        WHEN normalized_status=N'SUCCESS' AND end_time IS NULL THEN N'SUCCESS_WITHOUT_END_TIME'
        WHEN normalized_status=N'SUCCESS' AND rows_processed IS NULL THEN N'SUCCESS_WITHOUT_ROWS_PROCESSED'
        WHEN normalized_status=N'RUNNING' AND end_time IS NOT NULL THEN N'RUNNING_WITH_END_TIME'
        WHEN normalized_status IN (N'FAILED',N'ERROR',N'CANCELLED',N'CANCELED')
             AND end_time IS NULL THEN N'FINISHED_OR_FAILED_WITHOUT_END_TIME'
        ELSE NULL END AS anomaly
    FROM normalized
)
SELECT run_id, execution_id, pipeline_name, target_object, status,
       rows_processed, start_time, end_time, anomaly, error_message
FROM exceptions
WHERE anomaly IS NOT NULL
ORDER BY run_id;

PRINT '05 | RECENT HISTORY -- compare run_id and execution_id against Informatica Monitor';
SELECT TOP(100) run_id, execution_id, pipeline_name, source_system, source_object,
       target_object, start_time, end_time, status, rows_processed, error_message
FROM control.etl_run_log
ORDER BY run_id DESC;

PRINT '06 | STATUS DISTRIBUTION -- check expected number of attempts by target';
SELECT target_object, status, COUNT_BIG(*) AS run_count,
       MIN(run_id) AS first_run_id, MAX(run_id) AS latest_run_id
FROM control.etl_run_log
GROUP BY target_object, status
ORDER BY target_object, status;

PRINT '07 | LATEST RECORD PER TARGET -- review attempt versus latest successful run';
WITH numbered AS (
  SELECT run_id, execution_id, pipeline_name, target_object, status,
         start_time, end_time, rows_processed, error_message,
         ROW_NUMBER() OVER (PARTITION BY target_object ORDER BY run_id DESC) AS rn
  FROM control.etl_run_log
)
SELECT run_id, execution_id, pipeline_name, target_object, status,
       start_time, end_time, rows_processed, error_message
FROM numbered
WHERE rn=1
ORDER BY target_object;

PRINT '08 | ERRORS -- relevant failures even when final target count is correct';
SELECT TOP(100) run_id, execution_id, pipeline_name, target_object,
       start_time, end_time, status, rows_processed, error_message
FROM control.etl_run_log
WHERE error_message IS NOT NULL
   OR UPPER(LTRIM(RTRIM(CONVERT(nvarchar(40),status))))
      IN (N'FAILED',N'ERROR',N'CANCELLED',N'CANCELED')
ORDER BY run_id DESC;

PRINT 'END | Correlate with Informatica CDI/Taskflow monitor and control-log write logic.';
GO
