
-- Gold Customer Dimension
-- SCD Type 2
-- Grain: one row per observed customer version

WITH customer_history AS (

    SELECT
        -- Unique version identifier
        dbt_scd_id AS customer_version_key,

        -- Stable customer identity
        customer_id,
        customer_code,

        -- Customer lifecycle
        customer_created_at,
        crm_signup_at,

        -- Historically tracked attributes
        city,
        customer_segment,
        preferred_channel,
        marketing_opt_in,
        loyalty_tier,
        has_loyalty_account,

        -- Snapshot validity metadata
        dbt_valid_from AS valid_from_at,
        dbt_valid_to AS valid_to_at

    FROM {{ ref('snap_customers') }}

),

final AS (

    SELECT
        customer_version_key,
        customer_id,
        customer_code,

        customer_created_at,
        crm_signup_at,

        city,
        customer_segment,
        preferred_channel,
        marketing_opt_in,
        loyalty_tier,
        has_loyalty_account,

        valid_from_at,
        valid_to_at,

        CASE
            WHEN valid_to_at IS NULL
                THEN 1
            ELSE 0
        END AS is_current

    FROM customer_history

)

SELECT *
FROM final
