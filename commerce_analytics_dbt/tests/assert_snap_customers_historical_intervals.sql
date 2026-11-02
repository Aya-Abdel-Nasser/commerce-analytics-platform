
-- Production SCD Type 2 historical interval integrity
-- Expected result: zero rows
-- Grain: one row per invalid customer version

WITH ordered_versions AS (

    SELECT
        customer_id,
        dbt_scd_id,
        dbt_valid_from,
        dbt_valid_to,

        LEAD(dbt_valid_from) OVER (
            PARTITION BY customer_id
            ORDER BY dbt_valid_from, dbt_scd_id
        ) AS next_valid_from

    FROM {{ ref('snap_customers') }}

)

SELECT
    customer_id,
    dbt_scd_id,
    dbt_valid_from,
    dbt_valid_to,
    next_valid_from

FROM ordered_versions

WHERE
    -- Every version must have a start timestamp
    dbt_valid_from IS NULL

    -- Closed versions must have positive duration
    OR (
        dbt_valid_to IS NOT NULL
        AND dbt_valid_to <= dbt_valid_from
    )

    -- Earlier versions cannot remain open
    -- or overlap the next version
    OR (
        next_valid_from IS NOT NULL
        AND (
            dbt_valid_to IS NULL
            OR dbt_valid_to > next_valid_from
        )
    )
