
-- Production SCD Type 2 integrity test
-- Expected result: zero rows
-- Grain: one row per customer with invalid current versions

SELECT
    customer_id,
    COUNT_BIG(*) AS current_version_count

FROM {{ ref('snap_customers') }}

WHERE dbt_valid_to IS NULL

GROUP BY customer_id

HAVING COUNT_BIG(*) > 1
