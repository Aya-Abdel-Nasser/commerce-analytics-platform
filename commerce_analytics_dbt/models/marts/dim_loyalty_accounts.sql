
-- Gold Loyalty Account Dimension
-- Grain: one row per loyalty_account_id
-- Current-state dimension (SCD Type 1)
--
-- Current points balance is a snapshot balance,
-- not a sum of historical point movements.
--
-- Date keys use source calendar dates.
-- Source timezone is not yet independently verified.

with loyalty_accounts as (

    select
        loyalty_account_id,
        crm_customer_id,
        loyalty_tier,
        points_balance,
        enrolled_at,
        updated_at

    from {{ ref('stg_crm_loyalty_accounts') }}

),

crm_customers as (

    select
        crm_customer_id,
        external_customer_code

    from {{ ref('stg_crm_customers') }}

),

current_customers as (

    select
        customer_id,
        customer_code

    from {{ ref('dim_customers') }}

    where is_current = 1

),

final as (

    select
        -- Loyalty account identity
        a.loyalty_account_id,
        a.crm_customer_id,

        -- Stable customer identity
        d.customer_id,

        -- Current loyalty attributes
        a.loyalty_tier,
        a.points_balance as current_points_balance,

        -- Enrollment and update metadata
        a.enrolled_at,

        convert(
            int,
            convert(char(8), a.enrolled_at, 112)
        ) as enrollment_date_key,

        a.updated_at as account_updated_at

    from loyalty_accounts as a

    inner join crm_customers as c
        on a.crm_customer_id = c.crm_customer_id

    inner join current_customers as d
        on c.external_customer_code = d.customer_code

)

select *
from final
