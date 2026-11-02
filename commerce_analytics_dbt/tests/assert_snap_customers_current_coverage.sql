
-- Customer SCD Type 2 current coverage test
-- Expected result: zero rows
-- Run after refreshing the customer source and snapshot.

WITH current_source AS (

    SELECT
        customer_id
    FROM {{ ref('int_customers_scd_source') }}

),

current_snapshot AS (

    SELECT
        customer_id
    FROM {{ ref('snap_customers') }}
    WHERE dbt_valid_to IS NULL

)

SELECT
    s.customer_id,
    'MISSING_CURRENT_SNAPSHOT_VERSION' AS issue_type

FROM current_source AS s

LEFT JOIN current_snapshot AS h
    ON s.customer_id = h.customer_id

WHERE h.customer_id IS NULL
