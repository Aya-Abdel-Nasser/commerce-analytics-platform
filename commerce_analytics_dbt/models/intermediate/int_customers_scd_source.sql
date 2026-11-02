
-- Customer SCD Type 2 source
-- Grain: one row per customer_id
-- Purpose: provide selected customer attributes
-- for historical change detection.

with customer_attributes as (

    select
        -- Stable customer identity
        customer_id,
        customer_code,

        -- Customer lifecycle dates
        customer_created_at,
        crm_signup_at,

        -- SCD Type 2 tracked attributes
        city,
        customer_segment,
        marketing_opt_in,
        preferred_channel,
        has_loyalty_account,
        loyalty_tier

    from {{ ref('int_customers_integrated') }}

)

select
    customer_id,
    customer_code,
    customer_created_at,
    crm_signup_at,
    city,
    customer_segment,
    marketing_opt_in,
    preferred_channel,
    has_loyalty_account,
    loyalty_tier

from customer_attributes
