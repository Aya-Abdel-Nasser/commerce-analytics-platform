/*
PROJECT 2 | SOURCE 5 | APPLICATION EVENTS | SQL SERVER TARGET VALIDATION
RUN IN SSMS AGAINST commerce_warehouse_dev. All queries are SELECT/read-only.
Large dataset: 1,630,000 rows; full checks may take minutes on SQL Express.
SOURCE manifest baseline: 9 JSONL files; 1,630,000 rows; 11,897 late events
(>=24 hours between event_time_utc and received_at_utc).
A successful Taskflow alone does not prove this validation passed.
*/
USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;

PRINT '01 | TARGET TABLE EXISTS';
SELECT N'bronze.app_events_raw' AS target_table,
       CASE WHEN OBJECT_ID(N'bronze.app_events_raw', N'U') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END AS object_exists;
IF OBJECT_ID(N'bronze.app_events_raw', N'U') IS NULL
    THROW 51801, 'Missing target bronze.app_events_raw', 1;

PRINT '02 | TARGET METADATA: EXPECT raw_json NVARCHAR(MAX) NOT NULL; OPTIONAL LINEAGE';
SELECT c.column_id, c.name AS column_name, ty.name AS data_type,
       c.max_length AS max_bytes, c.precision, c.scale, c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'bronze.app_events_raw', N'U')
ORDER BY c.column_id;

WITH expected AS (
    SELECT * FROM (VALUES
      (1, N'raw_json', N'nvarchar', CONVERT(smallint,-1), CONVERT(bit,0)),
      (2, N'source_file_name', N'nvarchar', CONVERT(smallint,520), CONVERT(bit,1)),
      (3, N'source_line_number', N'bigint', CONVERT(smallint,8), CONVERT(bit,1))
    ) v(column_id,column_name,data_type,max_bytes,is_nullable)
), actual AS (
    SELECT c.column_id, c.name AS column_name, ty.name AS data_type,
           c.max_length AS max_bytes,c.is_nullable
    FROM sys.columns c JOIN sys.types ty ON ty.user_type_id=c.user_type_id
    WHERE c.object_id=OBJECT_ID(N'bronze.app_events_raw',N'U')
)
SELECT COALESCE(e.column_id,a.column_id) AS column_position, e.column_name AS expected_column,
       a.column_name AS actual_column, e.data_type AS expected_type,
       a.data_type AS actual_type,e.max_bytes AS expected_max_bytes,
       a.max_bytes AS actual_max_bytes,e.is_nullable AS expected_nullable,
       a.is_nullable AS actual_nullable,
       CASE WHEN e.column_id IS NOT NULL AND a.column_id IS NOT NULL
         AND e.column_name=a.column_name AND e.data_type=a.data_type
         AND e.max_bytes=a.max_bytes AND e.is_nullable=a.is_nullable
         THEN 'PASS' ELSE 'FAIL' END AS column_contract
FROM expected e FULL OUTER JOIN actual a ON e.column_id=a.column_id
ORDER BY column_position;

PRINT '03 | SNAPSHOT ROW COUNT; EXPECT 1,630,000';
SELECT COUNT_BIG(*) AS actual_target_rows,
       CONVERT(bigint,1630000) AS expected_manifest_rows,
       CASE WHEN COUNT_BIG(*)=1630000 THEN 'PASS' ELSE 'FAIL' END AS row_count_check
FROM bronze.app_events_raw;

PRINT '04 | JSON VALIDITY, TRUNCATION AND RAW STORAGE';
SELECT COUNT_BIG(*) AS rows_seen,
       SUM(CASE WHEN raw_json IS NULL THEN 1 ELSE 0 END) AS null_raw_json,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(raw_json)),N'') IS NULL THEN 1 ELSE 0 END) AS blank_raw_json,
       SUM(CASE WHEN ISJSON(raw_json) <> 1 THEN 1 ELSE 0 END) AS invalid_json,
       MIN(LEN(raw_json)) AS min_raw_json_characters,
       MAX(LEN(raw_json)) AS max_raw_json_characters,
       SUM(CASE WHEN LEFT(LTRIM(raw_json),1) <> N'{' THEN 1 ELSE 0 END) AS not_object_looking_text
FROM bronze.app_events_raw;

-- JSON_VALUE returns NULL on malformed text in lax mode in some cases; stop
-- if invalid JSON to avoid misleading field summaries.
IF NOT EXISTS (SELECT 1 FROM bronze.app_events_raw)
    THROW 51802, 'Target is empty; cannot validate JSON fields.', 1;
IF EXISTS (SELECT 1 FROM bronze.app_events_raw WHERE ISJSON(raw_json) <> 1)
    THROW 51803, 'Invalid JSON detected in target; investigate before continuing.', 1;

PRINT '05 | REQUIRED ENVELOPE AND PAYLOAD FIELDS';
-- Some business payload fields (e.g. customer_code) can legitimately be JSON null.
SELECT COUNT_BIG(*) AS total_rows,
       SUM(CASE WHEN JSON_VALUE(raw_json,'$._source_system') IS NULL THEN 1 ELSE 0 END) AS missing_source_system,
       SUM(CASE WHEN JSON_VALUE(raw_json,'$._batch') <> N'initial'
                      OR JSON_VALUE(raw_json,'$._batch') IS NULL THEN 1 ELSE 0 END) AS wrong_or_missing_batch,
       SUM(CASE WHEN JSON_QUERY(raw_json,'$.payload') IS NULL THEN 1 ELSE 0 END) AS missing_payload_object,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json,'$.payload.event_id'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_event_id,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json,'$.payload.event_name'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_event_name,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json,'$.payload.event_time_utc'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_event_time,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json,'$.payload.received_at_utc'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_received_at,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json,'$.payload.session_id'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_session_id
FROM bronze.app_events_raw;

PRINT '06 | EVENT NAME DISTRIBUTIONS VS MANIFEST';
WITH expected AS (
  SELECT * FROM (VALUES
    (N'added_to_cart',CONVERT(bigint,230000)),
    (N'checkout_cancelled',CONVERT(bigint,20000)),
    (N'checkout_started',CONVERT(bigint,200000)),
    (N'order_submitted',CONVERT(bigint,200000)),
    (N'payment_submitted',CONVERT(bigint,140000)),
    (N'product_viewed',CONVERT(bigint,350000)),
    (N'purchase_completed',CONVERT(bigint,140000)),
    (N'session_started',CONVERT(bigint,350000))
  ) v(event_name,expected_rows)
), actual AS (
  SELECT JSON_VALUE(raw_json,'$.payload.event_name') AS event_name,
         COUNT_BIG(*) AS actual_rows
  FROM bronze.app_events_raw
  GROUP BY JSON_VALUE(raw_json,'$.payload.event_name')
)
SELECT COALESCE(e.event_name,a.event_name) AS event_name,
       e.expected_rows,a.actual_rows,
       CASE WHEN e.expected_rows IS NOT NULL AND a.actual_rows=e.expected_rows
            THEN 'PASS' ELSE 'FAIL' END AS count_check
FROM expected e FULL OUTER JOIN actual a ON a.event_name=e.event_name
ORDER BY event_name;

PRINT '07 | EVENT ID UNIQUENESS; EXPECT 1,630,000 DISTINCT';
SELECT COUNT_BIG(*) AS total_rows,
       COUNT_BIG(DISTINCT JSON_VALUE(raw_json,'$.payload.event_id')) AS distinct_event_ids,
       SUM(CASE WHEN JSON_VALUE(raw_json,'$.payload.event_id') NOT LIKE N'EVT[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
                THEN 1 ELSE 0 END) AS invalid_event_id_format
FROM bronze.app_events_raw;

PRINT '08 | DUPLICATE EVENT ID SAMPLES (EXPECT ZERO ROWS)';
SELECT TOP(20) JSON_VALUE(raw_json,'$.payload.event_id') AS event_id,
       COUNT_BIG(*) AS occurrences
FROM bronze.app_events_raw
GROUP BY JSON_VALUE(raw_json,'$.payload.event_id')
HAVING COUNT_BIG(*) > 1
ORDER BY occurrences DESC;

PRINT '09 | UTC TIMESTAMP PARSE / LATE ARRIVING EVENTS';
-- TRY_CONVERT and DATEDIFF_BIG(second) >= 86400 mirror Python source profiler.
-- Z suffix normalized to +00:00; do not truncate fractional timestamps.
WITH timestamps AS (
  SELECT JSON_VALUE(raw_json,'$.payload.event_time_utc') AS event_raw,
         JSON_VALUE(raw_json,'$.payload.received_at_utc') AS received_raw
  FROM bronze.app_events_raw
), parsed AS (
  SELECT event_raw,received_raw,
         TRY_CONVERT(datetimeoffset(7),CASE WHEN RIGHT(event_raw,1)=N'Z'
           THEN LEFT(event_raw,LEN(event_raw)-1)+N'+00:00' ELSE event_raw END) AS event_dt,
         TRY_CONVERT(datetimeoffset(7),CASE WHEN RIGHT(received_raw,1)=N'Z'
           THEN LEFT(received_raw,LEN(received_raw)-1)+N'+00:00' ELSE received_raw END) AS received_dt
  FROM timestamps
)
SELECT COUNT_BIG(*) AS total_rows,
       SUM(CASE WHEN event_dt IS NULL OR received_dt IS NULL THEN 1 ELSE 0 END) AS invalid_timestamps,
       SUM(CASE WHEN event_dt IS NOT NULL AND received_dt IS NOT NULL
                     AND DATEDIFF_BIG(second,event_dt,received_dt)>=86400 THEN 1 ELSE 0 END) AS late_arriving_24h_or_more,
       CONVERT(bigint,11897) AS expected_late_arriving,
       CASE WHEN SUM(CASE WHEN event_dt IS NOT NULL AND received_dt IS NOT NULL
                     AND DATEDIFF_BIG(second,event_dt,received_dt)>=86400 THEN 1 ELSE 0 END)=11897
            THEN 'PASS' ELSE 'REVIEW' END AS late_event_check
FROM parsed;
-- Note: boundary check uses DATEDIFF_BIG(second); if an event lies within a
-- fractional second of exactly 24h, Python timedelta criterion is definitive.

PRINT '10 | OBSERVED SOURCE SYSTEM DISTRIBUTION';
SELECT JSON_VALUE(raw_json,'$._source_system') AS source_system,COUNT_BIG(*) AS rows_per_system
FROM bronze.app_events_raw
GROUP BY JSON_VALUE(raw_json,'$._source_system')
ORDER BY source_system;

PRINT '11 | FILE AND LINE LINEAGE (NULL ALLOWED, BUT TRACK AS A GAP)';
SELECT COUNT_BIG(*) AS target_rows,
       SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END) AS missing_source_file_name,
       COUNT_BIG(source_line_number) AS populated_line_numbers,
       MIN(source_line_number) AS first_line_number,
       MAX(source_line_number) AS last_line_number
FROM bronze.app_events_raw;

PRINT '12 | PIPELINE AUDIT LOG';
SELECT TOP (10) run_id,execution_id,pipeline_name,source_system,source_object,
       target_object,start_time,end_time,status,rows_processed,error_message
FROM control.etl_run_log
WHERE target_object=N'bronze.app_events_raw'
   OR pipeline_name=N'mt_bronze_app_events_initial'
ORDER BY run_id DESC;

PRINT 'NEXT: RUN 03_reconcile_SOURCE_TARGET_events.py FOR EXACT 9-FILE ROW TEXT MATCH';
GO
