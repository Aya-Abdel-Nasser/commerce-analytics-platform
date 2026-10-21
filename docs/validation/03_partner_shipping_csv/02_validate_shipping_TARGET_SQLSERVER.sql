/*
PROJECT 2 | Partner Shipping CSV -> SQL Server Bronze | TARGET VALIDATION
Run in SSMS or VS Code SQL extension on SQL Server Express.
READ ONLY. No CREATE/DROP/INSERT/UPDATE/DELETE/TRUNCATE.

Baseline: initial source manifest from actual four CSV files, 2026-10-08.
Rules are appropriate for THIS 120k initial snapshot; do not silently reuse
baseline expectations for a later incremental shipment batch.
No physical CSV constraints exist; this checks observed business conditions.
*/
USE [commerce_warehouse_dev];
GO

-- 00 | Preconditions. Fail explicitly if the target is absent.
IF OBJECT_ID(N'bronze.partner_shipments', N'U') IS NULL
    THROW 51080, 'Missing bronze.partner_shipments target table.', 1;
GO

-- 01 | Actual SQL Server catalog metadata vs intended 9-column Bronze layout.
-- These ARE declared SQL types/lengths/nullable values (unlike CSV inference).
SELECT
    c.column_id AS ordinal_position,
    c.name AS column_name,
    ty.name AS declared_sql_type,
    CASE WHEN ty.name IN ('nvarchar','nchar') THEN c.max_length/2 ELSE c.max_length END AS declared_max_characters,
    c.is_nullable,
    c.precision AS sql_catalog_precision,
    c.scale AS sql_catalog_scale
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id=ty.user_type_id
WHERE c.object_id = OBJECT_ID(N'bronze.partner_shipments')
ORDER BY c.column_id;

-- Schema expectation: exact 9 names, order, declared NVARCHAR lengths, nullable.
WITH expected AS (
  SELECT * FROM (VALUES
   (1,N'shipment_id',64),(2,N'order_number',64),(3,N'carrier_code',16),
   (4,N'tracking_number',64),(5,N'shipment_status',32),(6,N'shipped_at',32),
   (7,N'delivered_at',32),(8,N'shipping_fee_egp',32),(9,N'source_updated_at',32)
  ) x(ordinal_position,column_name,max_characters)
), actual AS (
 SELECT c.column_id AS ordinal_position,c.name AS column_name,
        ty.name AS type_name,c.max_length/2 AS max_characters,c.is_nullable
 FROM sys.columns c JOIN sys.types ty ON c.user_type_id=ty.user_type_id
 WHERE c.object_id=OBJECT_ID(N'bronze.partner_shipments')
)
SELECT COALESCE(e.ordinal_position,a.ordinal_position) AS ordinal_position,
       e.column_name AS expected_name, a.column_name AS actual_name,
       e.max_characters AS expected_max_characters,
       a.type_name, a.max_characters AS actual_max_characters, a.is_nullable,
       CASE WHEN e.column_name=a.column_name AND a.type_name=N'nvarchar'
                    AND e.max_characters=a.max_characters AND a.is_nullable=1
            THEN 'PASS' ELSE 'FAIL' END AS column_check
FROM expected e FULL OUTER JOIN actual a ON e.ordinal_position=a.ordinal_position
ORDER BY COALESCE(e.ordinal_position,a.ordinal_position);

-- 02 | Enforced constraints (the CSV has none; check whether SQL target has any).
SELECT o.name AS constraint_name, o.type_desc
FROM sys.objects o
WHERE o.parent_object_id = OBJECT_ID(N'bronze.partner_shipments')
  AND o.type IN ('PK','UQ','F','C','D');

-- 03 | Row count: target total equals initial-source 120,000.
SELECT COUNT_BIG(*) AS target_rows, CONVERT(BIGINT,120000) AS initial_source_rows,
       CASE WHEN COUNT_BIG(*)=120000 THEN 'PASS' ELSE 'FAIL' END AS count_check
FROM bronze.partner_shipments;

-- 04 | Source-to-target aggregation comparison by carrier.
WITH expected AS (
 SELECT * FROM (VALUES
  (N'DLV',CONVERT(BIGINT,30018)),
  (N'EGX',CONVERT(BIGINT,29943)),
  (N'FST',CONVERT(BIGINT,30136)),
  (N'NIL',CONVERT(BIGINT,29903))
 ) v(carrier_code,source_rows)
), actual AS (
 SELECT carrier_code, COUNT_BIG(*) AS target_rows
 FROM bronze.partner_shipments GROUP BY carrier_code
)
SELECT COALESCE(e.carrier_code,a.carrier_code) AS carrier_code,
       e.source_rows,a.target_rows,
       CASE WHEN e.source_rows=a.target_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e FULL OUTER JOIN actual a ON e.carrier_code=a.carrier_code
ORDER BY carrier_code;

-- 05 | Source-to-target aggregation comparison by status.
WITH expected AS (
 SELECT * FROM (VALUES
  (N'DELIVERED',CONVERT(BIGINT,80000)),
  (N'IN_TRANSIT',CONVERT(BIGINT,37647)),
  (N'DELAYED',CONVERT(BIGINT,2353))
 ) v(shipment_status,source_rows)
), actual AS (
 SELECT shipment_status,COUNT_BIG(*) AS target_rows
 FROM bronze.partner_shipments GROUP BY shipment_status
)
SELECT COALESCE(e.shipment_status,a.shipment_status) AS shipment_status,
       e.source_rows,a.target_rows,
       CASE WHEN e.source_rows=a.target_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e FULL OUTER JOIN actual a ON e.shipment_status=a.shipment_status
ORDER BY shipment_status;

-- 05b | Source-to-target carrier x status CROSS-TAB (12 observed combinations).
-- Stronger than checking carrier and status marginals separately.
WITH expected AS (
 SELECT * FROM (VALUES
  (N'DLV',N'DELAYED',CONVERT(BIGINT,521)),
  (N'DLV',N'DELIVERED',CONVERT(BIGINT,20085)),
  (N'DLV',N'IN_TRANSIT',CONVERT(BIGINT,9412)),
  (N'EGX',N'DELAYED',CONVERT(BIGINT,618)),
  (N'EGX',N'DELIVERED',CONVERT(BIGINT,19966)),
  (N'EGX',N'IN_TRANSIT',CONVERT(BIGINT,9359)),
  (N'FST',N'DELAYED',CONVERT(BIGINT,635)),
  (N'FST',N'DELIVERED',CONVERT(BIGINT,20056)),
  (N'FST',N'IN_TRANSIT',CONVERT(BIGINT,9445)),
  (N'NIL',N'DELAYED',CONVERT(BIGINT,579)),
  (N'NIL',N'DELIVERED',CONVERT(BIGINT,19893)),
  (N'NIL',N'IN_TRANSIT',CONVERT(BIGINT,9431))
 ) v(carrier_code,shipment_status,source_rows)
), actual AS (
 SELECT carrier_code,shipment_status,COUNT_BIG(*) AS target_rows
 FROM bronze.partner_shipments GROUP BY carrier_code,shipment_status
)
SELECT COALESCE(e.carrier_code,a.carrier_code) AS carrier_code,
       COALESCE(e.shipment_status,a.shipment_status) AS shipment_status,
       e.source_rows,a.target_rows,
       CASE WHEN e.source_rows=a.target_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e FULL OUTER JOIN actual a
 ON e.carrier_code=a.carrier_code AND e.shipment_status=a.shipment_status
ORDER BY carrier_code,shipment_status;

-- 06 | NULL vs empty string per EACH column (important Bronze source fidelity).
-- SQL NULL and CSV '' are not equivalent at byte/value level.
SELECT x.column_name,
       SUM(CASE WHEN x.column_value IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS sql_nulls,
       SUM(CASE WHEN x.column_value=N'' THEN CONVERT(BIGINT,1) ELSE 0 END) AS empty_strings,
       SUM(CASE WHEN x.column_value IS NOT NULL AND x.column_value<>N''
                  AND LEN(LTRIM(RTRIM(x.column_value)))=0
                THEN CONVERT(BIGINT,1) ELSE 0 END) AS whitespace_only
FROM bronze.partner_shipments s
CROSS APPLY (VALUES
 (N'shipment_id',s.shipment_id),
 (N'order_number',s.order_number),
 (N'carrier_code',s.carrier_code),
 (N'tracking_number',s.tracking_number),
 (N'shipment_status',s.shipment_status),
 (N'shipped_at',s.shipped_at),
 (N'delivered_at',s.delivered_at),
 (N'shipping_fee_egp',s.shipping_fee_egp),
 (N'source_updated_at',s.source_updated_at)
) x(column_name,column_value)
GROUP BY x.column_name
ORDER BY x.column_name;

-- 07 | Legitimate missing delivered_at vs missing shipment ID.
SELECT shipment_status, COUNT_BIG(*) AS target_rows,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(delivered_at)),N'') IS NULL
                THEN CONVERT(BIGINT,1) ELSE 0 END) AS blank_or_null_delivered_at,
       SUM(CASE WHEN delivered_at IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS actual_sql_null_delivered_at,
       SUM(CASE WHEN delivered_at=N'' THEN CONVERT(BIGINT,1) ELSE 0 END) AS actual_empty_string_delivered_at,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(shipment_id)),N'') IS NULL
                THEN CONVERT(BIGINT,1) ELSE 0 END) AS blank_or_null_shipment_id
FROM bronze.partner_shipments
GROUP BY shipment_status ORDER BY shipment_status;

-- 08 | Observed candidate-key uniqueness (NOT enforced PK/UNIQUE constraints).
SELECT COUNT_BIG(*) AS target_rows,
       COUNT_BIG(DISTINCT shipment_id) AS distinct_shipment_ids,
       COUNT_BIG(DISTINCT order_number) AS distinct_order_numbers,
       COUNT_BIG(DISTINCT tracking_number) AS distinct_tracking_numbers
FROM bronze.partner_shipments;
-- Actual samples if a candidate key is duplicated:
SELECT TOP (20) shipment_id,COUNT_BIG(*) AS duplicate_count
FROM bronze.partner_shipments
GROUP BY shipment_id HAVING COUNT_BIG(*)>1
ORDER BY duplicate_count DESC;
SELECT TOP (20) order_number,COUNT_BIG(*) AS duplicate_count
FROM bronze.partner_shipments
GROUP BY order_number HAVING COUNT_BIG(*)>1
ORDER BY duplicate_count DESC;
SELECT TOP (20) tracking_number,COUNT_BIG(*) AS duplicate_count
FROM bronze.partner_shipments
GROUP BY tracking_number HAVING COUNT_BIG(*)>1
ORDER BY duplicate_count DESC;

-- 09 | Complete full-row duplicates, across all nine columns.
SELECT TOP (20) shipment_id, order_number, carrier_code, tracking_number,
       shipment_status, shipped_at, delivered_at, shipping_fee_egp, source_updated_at,
       COUNT_BIG(*) AS duplicate_count
FROM bronze.partner_shipments
GROUP BY shipment_id, order_number, carrier_code, tracking_number,
         shipment_status, shipped_at, delivered_at, shipping_fee_egp, source_updated_at
HAVING COUNT_BIG(*)>1 ORDER BY duplicate_count DESC;

-- 10 | Data quality violations summary: ideally every issue_count = 0.
-- datetime2 parsing uses US MM/dd/yyyy datetime style 101.
-- Length/pattern tests additionally check the observed 19-character timestamp format.
WITH parsed AS (
 SELECT s.*,
   TRY_CONVERT(DATETIME2(0),NULLIF(s.shipped_at,N''),101) AS shipped_dt,
   TRY_CONVERT(DATETIME2(0),NULLIF(s.delivered_at,N''),101) AS delivered_dt,
   TRY_CONVERT(DATETIME2(0),NULLIF(s.source_updated_at,N''),101) AS updated_dt,
   TRY_CONVERT(DECIMAL(18,2),NULLIF(s.shipping_fee_egp,N'')) AS fee
 FROM bronze.partner_shipments s
), summary AS (
 SELECT
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(shipment_id)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(order_number)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(carrier_code)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(tracking_number)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(shipment_status)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(shipped_at)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(shipping_fee_egp)),N'') IS NULL
                OR NULLIF(LTRIM(RTRIM(source_updated_at)),N'') IS NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS missing_required_field_rows,
  SUM(CASE WHEN carrier_code NOT IN (N'EGX',N'FST',N'NIL',N'DLV') OR carrier_code IS NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_carrier_code,
  SUM(CASE WHEN shipment_status NOT IN (N'DELIVERED',N'IN_TRANSIT',N'DELAYED') OR shipment_status IS NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_shipment_status,
  SUM(CASE WHEN shipment_status=N'DELIVERED' AND NULLIF(LTRIM(RTRIM(delivered_at)),N'') IS NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS delivered_missing_date,
  SUM(CASE WHEN shipment_status<>N'DELIVERED' AND NULLIF(LTRIM(RTRIM(delivered_at)),N'') IS NOT NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS undelivered_has_date,
  SUM(CASE WHEN LEFT(tracking_number,3)<>carrier_code
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS tracking_prefix_mismatch,
  SUM(CASE WHEN shipped_dt IS NULL OR LEN(shipped_at)<>19 OR
                shipped_at NOT LIKE N'[01][0-9]/[0-3][0-9]/[12][0-9][0-9][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]'
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_shipped_at,
  SUM(CASE WHEN NULLIF(LTRIM(RTRIM(delivered_at)),N'') IS NOT NULL AND
                  (delivered_dt IS NULL OR LEN(delivered_at)<>19 OR
                   delivered_at NOT LIKE N'[01][0-9]/[0-3][0-9]/[12][0-9][0-9][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]')
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_delivered_at,
  SUM(CASE WHEN updated_dt IS NULL OR LEN(source_updated_at)<>19 OR
                source_updated_at NOT LIKE N'[01][0-9]/[0-3][0-9]/[12][0-9][0-9][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9]'
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_source_updated_at,
  SUM(CASE WHEN shipped_dt IS NOT NULL AND delivered_dt IS NOT NULL AND delivered_dt<shipped_dt
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS delivered_before_shipped,
  SUM(CASE WHEN shipped_dt IS NOT NULL AND updated_dt IS NOT NULL AND updated_dt<shipped_dt
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS updated_before_shipped,
  SUM(CASE WHEN fee IS NULL
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS invalid_shipping_fee,
  SUM(CASE WHEN fee<0
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS negative_shipping_fee,
  SUM(CASE WHEN shipping_fee_egp NOT LIKE N'[0-9][0-9].[0-9][0-9]'
                  OR LEN(shipping_fee_egp)<>5 OR SUBSTRING(shipping_fee_egp,3,1)<>N'.'
      THEN CONVERT(BIGINT,1) ELSE 0 END) AS unexpected_fee_format
 FROM parsed
)
SELECT v.check_name, v.issue_count,
       CASE WHEN v.issue_count=0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM summary s
CROSS APPLY (VALUES
 (N'missing_required_field_rows',s.missing_required_field_rows),
 (N'invalid_carrier_code',s.invalid_carrier_code),
 (N'invalid_shipment_status',s.invalid_shipment_status),
 (N'delivered_missing_date',s.delivered_missing_date),
 (N'undelivered_has_date',s.undelivered_has_date),
 (N'tracking_prefix_mismatch',s.tracking_prefix_mismatch),
 (N'invalid_shipped_at',s.invalid_shipped_at),
 (N'invalid_delivered_at',s.invalid_delivered_at),
 (N'invalid_source_updated_at',s.invalid_source_updated_at),
 (N'delivered_before_shipped',s.delivered_before_shipped),
 (N'updated_before_shipped',s.updated_before_shipped),
 (N'invalid_shipping_fee',s.invalid_shipping_fee),
 (N'negative_shipping_fee',s.negative_shipping_fee),
 (N'unexpected_fee_format',s.unexpected_fee_format)
) v(check_name,issue_count)
ORDER BY v.check_name;

-- 11 | Cross-source business reference; not a declared FOREIGN KEY.
IF OBJECT_ID(N'bronze.oltp_orders',N'U') IS NOT NULL
   AND COL_LENGTH(N'bronze.oltp_orders',N'order_number') IS NOT NULL
BEGIN
  EXEC(N'SELECT COUNT_BIG(*) AS shipping_rows,
    SUM(CASE WHEN o.order_number IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS unmatched_order_numbers
    FROM bronze.partner_shipments s
    LEFT JOIN bronze.oltp_orders o ON s.order_number=o.order_number;');
END
ELSE
  SELECT 'SKIPPED: bronze.oltp_orders.order_number not present' AS reference_check;

-- 12 | Latest pipeline audit record; verify SUCCESS, 120000 and execution UUID.
IF OBJECT_ID(N'control.etl_run_log',N'U') IS NOT NULL
 SELECT TOP (5) * FROM control.etl_run_log
 WHERE pipeline_name=N'mt_bronze_partner_shipments_initial'
 ORDER BY run_id DESC;
ELSE SELECT 'SKIPPED: control.etl_run_log not present' AS audit_check;
GO
