
-- Production SCD Type 2 version key integrity
-- Expected result: zero rows

WITH version_key_checks AS (

    SELECT
        dbt_scd_id,
        COUNT_BIG(*) AS version_count

    FROM {{ ref('snap_customers') }}

    GROUP BY dbt_scd_id

)

SELECT
    dbt_scd_id,
    version_count

FROM version_key_checks

WHERE dbt_scd_id IS NULL
   OR version_count > 1
