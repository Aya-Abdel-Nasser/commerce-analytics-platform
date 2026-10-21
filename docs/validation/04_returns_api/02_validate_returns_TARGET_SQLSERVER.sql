/*
 Project 2 — Returns REST API snapshot → SQL Server Bronze TARGET VALIDATION
 Environment: SQL Server / commerce_warehouse_dev
 Source: 22,093 objects in returns_initial.jsonl
 Target: bronze.returns_raw(raw_json NVARCHAR(MAX) NOT NULL,
                            source_file_name NVARCHAR(260) NULL,
                            source_line_number BIGINT NULL)
 READ ONLY: no table modifications or destructive commands.
 IMPORTANT: Run entire file. A THROW indicates a prerequisite failed.
 This does not read your local source file; execute 01 and 03 for source-side/exact reconciliation.
*/
USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;
IF OBJECT_ID(N'bronze.returns_raw', N'U') IS NULL
    THROW 51201, 'Target table bronze.returns_raw is missing.', 1;
IF OBJECT_ID(N'control.etl_run_log', N'U') IS NULL
    THROW 51202, 'Audit table control.etl_run_log is missing.', 1;

PRINT '01 | TARGET SCHEMA / SQL TYPES / SQL NULLABILITY';
SELECT c.column_id, c.name AS column_name, ty.name AS data_type,
       c.max_length AS max_bytes, c.precision AS sql_precision,
       c.scale AS sql_scale, c.is_nullable,
       CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CONVERT(varchar(30), c.max_length / 2) END AS nvarchar_character_capacity
FROM sys.columns c
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'bronze.returns_raw', N'U')
ORDER BY c.column_id;

PRINT '02 | EXACT THREE-COLUMN CONTRACT';
WITH expected AS (
    SELECT * FROM (VALUES
      (1, N'raw_json', N'nvarchar', -1, 0),
      (2, N'source_file_name', N'nvarchar', 520, 1),
      (3, N'source_line_number', N'bigint', 8, 1)
    ) v(column_id, column_name, data_type, max_bytes, is_nullable)
), actual AS (
    SELECT c.column_id, c.name AS column_name, ty.name AS data_type,
           c.max_length AS max_bytes, CONVERT(int, c.is_nullable) AS is_nullable
    FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
    WHERE c.object_id = OBJECT_ID(N'bronze.returns_raw', N'U')
)
SELECT COALESCE(e.column_id, a.column_id) AS position,
       e.column_name AS expected_column, a.column_name AS actual_column,
       e.data_type AS expected_type, a.data_type AS actual_type,
       e.max_bytes AS expected_max_bytes, a.max_bytes AS actual_max_bytes,
       e.is_nullable AS expected_nullable, a.is_nullable AS actual_nullable,
       CASE WHEN e.column_id IS NOT NULL AND a.column_id IS NOT NULL
                     AND e.column_name = a.column_name
                     AND e.data_type = a.data_type
                     AND e.max_bytes = a.max_bytes
                     AND e.is_nullable = a.is_nullable
            THEN 'PASS' ELSE 'FAIL' END AS column_contract
FROM expected e FULL OUTER JOIN actual a ON a.column_id = e.column_id
ORDER BY position;

PRINT '03 | ACTUAL ENFORCED KEY/CHECK CONSTRAINTS (NO ROWS IF NONE)';
SELECT tc.name AS constraint_name, tc.type_desc
FROM sys.objects tc
WHERE tc.parent_object_id = OBJECT_ID(N'bronze.returns_raw', N'U')
  AND tc.type IN ('PK', 'UQ', 'F', 'C')
ORDER BY tc.type_desc, tc.name;

PRINT '04 | INITIAL SNAPSHOT ROW COUNT';
SELECT COUNT_BIG(*) AS target_rows, CONVERT(bigint,22093) AS expected_source_rows,
       CASE WHEN COUNT_BIG(*) = 22093 THEN 'PASS' ELSE 'FAIL' END AS count_check
FROM bronze.returns_raw;

PRINT '05 | RAW TEXT STORAGE / JSON PARSER';
SELECT COUNT_BIG(*) AS total,
       SUM(CASE WHEN raw_json IS NULL THEN 1 ELSE 0 END) AS null_raw_json,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(raw_json)), N'') IS NULL THEN 1 ELSE 0 END) AS blank_raw_json,
       SUM(CASE WHEN ISJSON(raw_json) <> 1 THEN 1 ELSE 0 END) AS invalid_json,
       MIN(LEN(raw_json)) AS shortest_raw_json_characters,
       MAX(LEN(raw_json)) AS longest_raw_json_characters,
       SUM(CASE WHEN LEN(raw_json) < 360 OR LEN(raw_json) > 369 THEN 1 ELSE 0 END) AS lengths_outside_source_range,
       SUM(CASE WHEN LEN(raw_json) >= 1000 THEN 1 ELSE 0 END) AS rows_at_or_over_1000_chars,
       SUM(CASE WHEN LEFT(LTRIM(raw_json), 1) <> '{' THEN 1 ELSE 0 END) AS not_object_looking_text
FROM bronze.returns_raw;

-- Do not invoke JSON_VALUE/OPENJSON on invalid JSON. Stop this batch early.
IF NOT EXISTS (SELECT 1 FROM bronze.returns_raw)
    THROW 51203, 'Target is empty. No source-to-target comparison is possible.', 1;
IF EXISTS (SELECT 1 FROM bronze.returns_raw WHERE ISJSON(raw_json) <> 1)
    THROW 51204, 'One or more raw_json values are not valid JSON. Stop and investigate.', 1;

PRINT '06 | ENVELOPE METADATA / REQUIRED PAYLOAD FIELDS';
SELECT COUNT_BIG(*) AS total_rows,
       SUM(CASE WHEN JSON_VALUE(raw_json, '$._source_system') <> N'MOCK_RETURNS_API'
                     OR JSON_VALUE(raw_json, '$._source_system') IS NULL THEN 1 ELSE 0 END) AS wrong_source_system,
       SUM(CASE WHEN JSON_VALUE(raw_json, '$._source_endpoint') <> N'/api/v1/returns'
                     OR JSON_VALUE(raw_json, '$._source_endpoint') IS NULL THEN 1 ELSE 0 END) AS wrong_endpoint,
       SUM(CASE WHEN JSON_VALUE(raw_json, '$._ingested_at_utc') <> N'2026-10-08T17:16:15+00:00'
                     OR JSON_VALUE(raw_json, '$._ingested_at_utc') IS NULL THEN 1 ELSE 0 END) AS wrong_ingested_timestamp,
       SUM(CASE WHEN JSON_QUERY(raw_json, '$.payload') IS NULL THEN 1 ELSE 0 END) AS missing_payload,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.return_id'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_return_ids,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.order_number'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_order_numbers,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.reason_code'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_reason_codes,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.return_status'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_return_statuses,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.requested_at'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_requested_at,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.updated_at'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_updated_at,
       SUM(CASE WHEN NULLIF(JSON_VALUE(raw_json, '$.payload.requested_refund_egp'),N'') IS NULL THEN 1 ELSE 0 END) AS missing_refund_values
FROM bronze.returns_raw;

PRINT '07 | STATUS DISTRIBUTION: EXACT EXPECTED INITIAL SNAPSHOT COUNTS';
WITH expected AS (
  SELECT * FROM (VALUES
    (N'REJECTED',CONVERT(bigint,5611)),
    (N'REFUNDED',CONVERT(bigint,5558)),
    (N'REQUESTED',CONVERT(bigint,5518)),
    (N'APPROVED',CONVERT(bigint,5406))
  ) v(return_status, expected_rows)
), observed AS (
  SELECT JSON_VALUE(raw_json, '$.payload.return_status') AS return_status,
         COUNT_BIG(*) AS actual_rows
  FROM bronze.returns_raw GROUP BY JSON_VALUE(raw_json, '$.payload.return_status')
)
SELECT COALESCE(e.return_status, a.return_status) AS return_status,
       e.expected_rows, a.actual_rows,
       CASE WHEN e.expected_rows IS NOT NULL AND e.expected_rows = a.actual_rows
            THEN 'PASS' ELSE 'FAIL' END AS count_check
FROM expected e FULL OUTER JOIN observed a ON e.return_status = a.return_status
ORDER BY return_status;

PRINT '08 | REASON DISTRIBUTION: EXACT EXPECTED INITIAL SNAPSHOT COUNTS';
WITH expected AS (
  SELECT * FROM (VALUES
    (N'WRONG_ITEM',CONVERT(bigint,5579)),
    (N'CHANGED_MIND',CONVERT(bigint,5552)),
    (N'NOT_AS_DESCRIBED',CONVERT(bigint,5550)),
    (N'QUALITY_ISSUE',CONVERT(bigint,5412))
  ) v(reason_code,expected_rows)
), observed AS (
  SELECT JSON_VALUE(raw_json,'$.payload.reason_code') AS reason_code,
         COUNT_BIG(*) AS actual_rows
  FROM bronze.returns_raw GROUP BY JSON_VALUE(raw_json,'$.payload.reason_code')
)
SELECT COALESCE(e.reason_code,a.reason_code) AS reason_code,
       e.expected_rows, a.actual_rows,
       CASE WHEN e.expected_rows IS NOT NULL AND e.expected_rows = a.actual_rows
            THEN 'PASS' ELSE 'FAIL' END AS count_check
FROM expected e FULL OUTER JOIN observed a ON e.reason_code = a.reason_code
ORDER BY reason_code;

PRINT '09 | OBSERVED CANDIDATE KEY UNIQUENESS';
SELECT COUNT_BIG(*) AS rows,
       COUNT_BIG(DISTINCT JSON_VALUE(raw_json,'$.payload.return_id')) AS unique_return_ids,
       COUNT_BIG(DISTINCT JSON_VALUE(raw_json,'$.payload.order_number')) AS unique_order_numbers
FROM bronze.returns_raw;

PRINT '10 | DUPLICATE RETURN IDs (EXPECT NO ROWS)';
SELECT TOP (20) JSON_VALUE(raw_json,'$.payload.return_id') AS return_id,
                COUNT_BIG(*) AS duplicate_rows
FROM bronze.returns_raw
GROUP BY JSON_VALUE(raw_json,'$.payload.return_id')
HAVING COUNT_BIG(*) > 1 ORDER BY duplicate_rows DESC;

PRINT '11 | DUPLICATE ORDER NUMBERS IN THIS SNAPSHOT (EXPECT NO ROWS)';
-- Snapshot-only observed uniqueness: one return per order is NOT a universal API constraint.
SELECT TOP (20) JSON_VALUE(raw_json,'$.payload.order_number') AS order_number,
                COUNT_BIG(*) AS duplicate_rows
FROM bronze.returns_raw
GROUP BY JSON_VALUE(raw_json,'$.payload.order_number')
HAVING COUNT_BIG(*) > 1 ORDER BY duplicate_rows DESC;

PRINT '12 | RAW TEXT DUPLICATES VIA SHA-256 (EXPECT NO ROWS)';
-- SHA-256 duplicates are strong indicators, not a mathematical proof of exact equality.
SELECT TOP (20) CONVERT(varchar(64), HASHBYTES('SHA2_256', CONVERT(nvarchar(max), raw_json)),2) AS raw_text_sha256,
                COUNT_BIG(*) AS duplicate_count
FROM bronze.returns_raw
GROUP BY HASHBYTES('SHA2_256', CONVERT(nvarchar(max), raw_json))
HAVING COUNT_BIG(*) > 1 ORDER BY duplicate_count DESC;

PRINT '13 | TIMESTAMPS, REFUND VALUES AND BUSINESS RELATIONSHIPS';
SELECT
 SUM(CASE WHEN TRY_CONVERT(datetimeoffset(0), JSON_VALUE(raw_json,'$.payload.requested_at')) IS NULL THEN 1 ELSE 0 END) AS invalid_requested_at,
 SUM(CASE WHEN TRY_CONVERT(datetimeoffset(0), JSON_VALUE(raw_json,'$.payload.updated_at')) IS NULL THEN 1 ELSE 0 END) AS invalid_updated_at,
 SUM(CASE WHEN JSON_VALUE(raw_json,'$.payload.requested_at') NOT LIKE N'%+00:00' THEN 1 ELSE 0 END) AS requested_at_not_utc_format,
 SUM(CASE WHEN JSON_VALUE(raw_json,'$.payload.updated_at') NOT LIKE N'%+00:00' THEN 1 ELSE 0 END) AS updated_at_not_utc_format,
 SUM(CASE WHEN TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.updated_at')) <
                   TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.requested_at')) THEN 1 ELSE 0 END) AS updated_before_requested,
 SUM(CASE WHEN TRY_CONVERT(decimal(20,2),JSON_VALUE(raw_json,'$.payload.requested_refund_egp')) IS NULL THEN 1 ELSE 0 END) AS unparseable_refund,
 SUM(CASE WHEN TRY_CONVERT(decimal(20,2),JSON_VALUE(raw_json,'$.payload.requested_refund_egp')) <= 0 THEN 1 ELSE 0 END) AS nonpositive_refund,
 MIN(TRY_CONVERT(decimal(20,2), JSON_VALUE(raw_json,'$.payload.requested_refund_egp'))) AS min_refund_egp,
 MAX(TRY_CONVERT(decimal(20,2), JSON_VALUE(raw_json,'$.payload.requested_refund_egp'))) AS max_refund_egp,
 MIN(TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.requested_at'))) AS earliest_requested_at,
 MAX(TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.requested_at'))) AS latest_requested_at,
 MIN(TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.updated_at'))) AS earliest_updated_at,
 MAX(TRY_CONVERT(datetimeoffset(0),JSON_VALUE(raw_json,'$.payload.updated_at'))) AS latest_updated_at
FROM bronze.returns_raw;

PRINT '14 | JSON DATA TYPE OF REFUND PROPERTY: TYPE 1 = STRING';
SELECT p.[type] AS json_type_code,
       CASE p.[type] WHEN 1 THEN 'STRING (EXPECTED)' WHEN 2 THEN 'NUMBER' ELSE 'OTHER' END AS json_type,
       COUNT_BIG(*) AS row_count
FROM bronze.returns_raw r CROSS APPLY OPENJSON(r.raw_json, '$.payload') p
WHERE p.[key] = 'requested_refund_egp'
GROUP BY p.[type];

PRINT '15 | OPTIONAL FILE AND LINE PROVENANCE';
SELECT COUNT_BIG(*) AS total_rows,
       SUM(CASE WHEN source_file_name IS NULL THEN 1 ELSE 0 END) AS null_source_file_name,
       COUNT_BIG(source_line_number) AS populated_line_numbers,
       COUNT_BIG(DISTINCT source_line_number) AS distinct_line_numbers,
       MIN(source_line_number) AS min_line_number,
       MAX(source_line_number) AS max_line_number
FROM bronze.returns_raw;

PRINT '16 | CROSS-SOURCE RETURN ORDER REFERENCE (EXPECT ZERO ORPHANS FOR THIS SNAPSHOT)';
IF OBJECT_ID(N'bronze.oltp_orders', N'U') IS NOT NULL
BEGIN
  SELECT COUNT_BIG(*) AS returns_without_matching_oltp_order
  FROM bronze.returns_raw r
  WHERE NOT EXISTS (
    SELECT 1 FROM bronze.oltp_orders o
    WHERE o.order_number = JSON_VALUE(r.raw_json,'$.payload.order_number')
  );
END
ELSE
  PRINT 'SKIPPED: bronze.oltp_orders not present';

PRINT '17 | LATEST RETURNS API AUDIT RECORDS';
SELECT TOP (10) run_id, execution_id, pipeline_name, source_system,
       source_object, target_object, start_time, end_time,
       status, rows_processed, error_message
FROM control.etl_run_log
WHERE pipeline_name = N'mt_bronze_returns_api_initial'
ORDER BY run_id DESC;

PRINT '18 | SUMMARY NOTES';
SELECT N'Row counts, envelopes, distributions, types, and audit are SQL-side validation only.' AS note
UNION ALL SELECT N'Run 03_reconcile_returns_SOURCE_TARGET.py to verify EVERY original JSON line versus SQL raw_json.'
UNION ALL SELECT N'This script never reads/modifies the source JSONL and never alters the Bronze table.';
GO
