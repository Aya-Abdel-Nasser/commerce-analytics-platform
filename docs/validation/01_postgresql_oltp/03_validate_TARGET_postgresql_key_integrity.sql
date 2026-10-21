-- Commerce Analytics Platform | PostgreSQL OLTP -> SQL Server Bronze
-- Target primary-key integrity validation | Initial snapshot
-- Run in SSMS against commerce_warehouse_dev.
-- READ-ONLY: SELECT only; no INSERT/UPDATE/DELETE/TRUNCATE.
-- Key definitions verified from PostgreSQL source constraints:
-- customers(customer_id), order_items(order_item_id), orders(order_id),
-- payments(payment_id), products(product_id).

USE [commerce_warehouse_dev];
GO
SET NOCOUNT ON;

-- Step 1: For each target table, group records by the source's primary key.
-- rows_per_key > 1 indicates a repeated primary-key value.
-- key_is_null = 1 indicates the key value is missing.
;WITH key_groups AS (
    SELECT N'oltp_customers' AS table_name,
           COUNT_BIG(*) AS rows_per_key,
           MAX(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS key_is_null
    FROM bronze.oltp_customers
    GROUP BY customer_id

    UNION ALL

    SELECT N'oltp_order_items',
           COUNT_BIG(*),
           MAX(CASE WHEN order_item_id IS NULL THEN 1 ELSE 0 END)
    FROM bronze.oltp_order_items
    GROUP BY order_item_id

    UNION ALL

    SELECT N'oltp_orders',
           COUNT_BIG(*),
           MAX(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END)
    FROM bronze.oltp_orders
    GROUP BY order_id

    UNION ALL

    SELECT N'oltp_payments',
           COUNT_BIG(*),
           MAX(CASE WHEN payment_id IS NULL THEN 1 ELSE 0 END)
    FROM bronze.oltp_payments
    GROUP BY payment_id

    UNION ALL

    SELECT N'oltp_products',
           COUNT_BIG(*),
           MAX(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END)
    FROM bronze.oltp_products
    GROUP BY product_id
),
-- Step 2: Turn grouped keys into per-table quality metrics.
summary AS (
    SELECT
        table_name,
        SUM(rows_per_key) AS total_rows,
        SUM(CASE WHEN key_is_null = 1
                 THEN rows_per_key ELSE CONVERT(bigint, 0) END) AS null_key_rows,
        SUM(CASE WHEN rows_per_key > 1
                 THEN CONVERT(bigint, 1) ELSE CONVERT(bigint, 0) END) AS duplicate_key_groups,
        SUM(CASE WHEN rows_per_key > 1
                 THEN rows_per_key - 1 ELSE CONVERT(bigint, 0) END) AS extra_duplicate_rows
    FROM key_groups
    GROUP BY table_name
)
-- Step 3: PASS only when no source-PK values are missing or repeated.
SELECT table_name,
       total_rows,
       null_key_rows,
       duplicate_key_groups,
       extra_duplicate_rows,
       CASE
           WHEN null_key_rows = 0 AND duplicate_key_groups = 0 THEN 'PASS'
           ELSE 'FAIL'
       END AS key_integrity_check
FROM summary
ORDER BY table_name;
GO
