-- Commerce Analytics Platform | MySQL CRM -> SQL Server Bronze
-- Primary key integrity validation (read-only)
-- Source of truth for key definitions: MySQL information_schema PRIMARY KEY metadata.
-- Run in SSMS against commerce_warehouse_dev.
-- Does not change source, bronze, or control tables.
-- Initial snapshot only; counts and audit were validated separately.

USE [commerce_warehouse_dev];
GO

-- Each row in key_groups represents one distinct key (or composite key).
-- rows_per_key > 1 means that the key appears more than once.
-- null_key_flag = 1 means at least one PK component is NULL.
;WITH key_groups AS (
    SELECT N'crm_customers' AS table_name,
           COUNT_BIG(*) AS rows_per_key,
           CASE WHEN crm_customer_id IS NULL THEN 1 ELSE 0 END AS null_key_flag
    FROM bronze.crm_customers
    GROUP BY crm_customer_id

    UNION ALL
    SELECT N'crm_loyalty_accounts',
           COUNT_BIG(*),
           CASE WHEN loyalty_account_id IS NULL THEN 1 ELSE 0 END
    FROM bronze.crm_loyalty_accounts
    GROUP BY loyalty_account_id

    UNION ALL
    SELECT N'crm_loyalty_transactions',
           COUNT_BIG(*),
           CASE WHEN loyalty_transaction_id IS NULL THEN 1 ELSE 0 END
    FROM bronze.crm_loyalty_transactions
    GROUP BY loyalty_transaction_id

    UNION ALL
    SELECT N'crm_campaigns',
           COUNT_BIG(*),
           CASE WHEN campaign_id IS NULL THEN 1 ELSE 0 END
    FROM bronze.crm_campaigns
    GROUP BY campaign_id

    UNION ALL
    SELECT N'crm_campaign_memberships',
           COUNT_BIG(*),
           CASE WHEN campaign_id IS NULL OR crm_customer_id IS NULL THEN 1 ELSE 0 END
    FROM bronze.crm_campaign_memberships
    GROUP BY campaign_id, crm_customer_id

    UNION ALL
    SELECT N'crm_support_tickets',
           COUNT_BIG(*),
           CASE WHEN ticket_id IS NULL THEN 1 ELSE 0 END
    FROM bronze.crm_support_tickets
    GROUP BY ticket_id
),
key_summary AS (
    SELECT table_name,
           SUM(rows_per_key) AS total_rows,
           SUM(CASE WHEN null_key_flag = 1 THEN rows_per_key ELSE CONVERT(bigint, 0) END) AS null_key_rows,
           SUM(CASE WHEN rows_per_key > 1 THEN CONVERT(bigint, 1) ELSE CONVERT(bigint, 0) END) AS duplicate_key_groups,
           SUM(CASE WHEN rows_per_key > 1 THEN rows_per_key - 1 ELSE CONVERT(bigint, 0) END) AS extra_duplicate_rows
    FROM key_groups
    GROUP BY table_name
)
SELECT table_name, total_rows, null_key_rows, duplicate_key_groups, extra_duplicate_rows,
       CASE WHEN null_key_rows = 0 AND duplicate_key_groups = 0
            THEN 'PASS' ELSE 'FAIL' END AS key_integrity_check
FROM key_summary
ORDER BY table_name;
GO

-- Interpretation:
-- 6 rows, each PASS, null_key_rows = 0, duplicate_key_groups = 0,
-- extra_duplicate_rows = 0 -> key integrity validated in Bronze.
-- This does NOT prove other column values equal the MySQL source.
