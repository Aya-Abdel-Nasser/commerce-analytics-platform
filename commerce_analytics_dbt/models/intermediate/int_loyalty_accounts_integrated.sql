
with loyalty_accounts as (

    select
        loyalty_account_id,
        crm_customer_id,
        loyalty_tier,
        points_balance

    from {{ ref('stg_crm_loyalty_accounts') }}

),

loyalty_transactions as (

    select
        loyalty_account_id,
        loyalty_transaction_count,
        earn_transaction_count,
        redeem_transaction_count,
        adjust_transaction_count,
        earned_points,
        redeemed_points,
        net_adjustment_points,
        net_points_delta

    from {{ ref('int_loyalty_transactions_by_account') }}

),

integrated as (

    select
        -- Account attributes
        a.loyalty_account_id,
        a.crm_customer_id,
        a.loyalty_tier,
        a.points_balance,

        -- Transaction counts
        t.loyalty_transaction_count,
        t.earn_transaction_count,
        t.redeem_transaction_count,
        t.adjust_transaction_count,

        -- Points movements
        t.earned_points,
        t.redeemed_points,
        t.net_adjustment_points,
        t.net_points_delta

    from loyalty_accounts as a

    left join loyalty_transactions as t
        on a.loyalty_account_id = t.loyalty_account_id

)

select *
from integrated
