
with oltp_customers as (

    select
        customer_id,
        customer_code,
        full_name,
        email,
        city,
        created_at,
        updated_at,
        ingested_at_utc

    from {{ ref('stg_oltp_customers') }}

),

crm_customers as (

    select
        crm_customer_id,
        external_customer_code,
        signup_at,
        customer_segment,
        marketing_opt_in,
        preferred_channel,
        updated_at

    from {{ ref('stg_crm_customers') }}

),

loyalty_accounts as (

    select
        loyalty_account_id,
        crm_customer_id,
        loyalty_tier,
        points_balance,
        loyalty_transaction_count,
        earn_transaction_count,
        redeem_transaction_count,
        adjust_transaction_count,
        earned_points,
        redeemed_points,
        net_adjustment_points,
        net_points_delta

    from {{ ref('int_loyalty_accounts_integrated') }}

),

integrated as (

    select
        -- OLTP customer identity and attributes
        o.customer_id,
        o.customer_code,
        o.full_name,
        o.email,
        o.city,
        o.created_at as customer_created_at,
        o.updated_at as oltp_updated_at,
        o.ingested_at_utc,

        -- CRM attributes
        c.crm_customer_id,
        c.external_customer_code,
        c.signup_at as crm_signup_at,
        c.customer_segment,
        c.marketing_opt_in,
        c.preferred_channel,
        c.updated_at as crm_updated_at,

        -- Loyalty account attributes
        l.loyalty_account_id,
        l.loyalty_tier,
        l.points_balance,

        case
            when l.loyalty_account_id is not null
            then 1
            else 0
        end as has_loyalty_account,

        -- Loyalty transaction counts
        l.loyalty_transaction_count,
        l.earn_transaction_count,
        l.redeem_transaction_count,
        l.adjust_transaction_count,

        -- Loyalty points measures
        l.earned_points,
        l.redeemed_points,
        l.net_adjustment_points,
        l.net_points_delta

    from oltp_customers as o

    left join crm_customers as c
        on o.customer_code = c.external_customer_code

    left join loyalty_accounts as l
        on c.crm_customer_id = l.crm_customer_id

)

select *
from integrated
