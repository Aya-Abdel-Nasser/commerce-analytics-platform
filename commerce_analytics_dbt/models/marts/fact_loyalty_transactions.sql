
-- Gold Loyalty Transaction Fact Table
-- Grain: one row per loyalty_transaction_id
--
-- Points movements are signed.
-- Transaction dates use source calendar dates.
-- Source timezone is not yet independently verified.
--
-- Current loyalty tiers are not assigned
-- to historical transactions.

with loyalty_transactions as (

    select
        loyalty_transaction_id,
        loyalty_account_id,
        transaction_type,
        points_delta,
        reference_order_number,
        occurred_at

    from {{ ref('stg_crm_loyalty_transactions') }}

),

loyalty_accounts as (

    select
        loyalty_account_id,
        customer_id

    from {{ ref('dim_loyalty_accounts') }}

),

orders as (

    select
        order_id,
        order_number

    from {{ ref('fact_orders') }}

),

final as (

    select

        -- Transaction identity
        t.loyalty_transaction_id,

        -- Loyalty and customer relationships
        t.loyalty_account_id,
        a.customer_id,

        -- Optional order relationship
        t.reference_order_number,
        o.order_id,

        -- Transaction attributes
        t.transaction_type,
        t.occurred_at,

        {{ date_to_key('t.occurred_at') }} as transaction_date_key,

        -- Additive transaction count
        1 as transaction_count,

        -- Original signed points movement
        cast(t.points_delta as bigint)
            as points_delta,

        -- Positive points earned
        case
            when t.transaction_type = 'EARN'
            then cast(t.points_delta as bigint)
            else cast(0 as bigint)
        end as earned_points,

        -- Positive magnitude of redeemed points
        case
            when t.transaction_type = 'REDEEM'
            then -cast(t.points_delta as bigint)
            else cast(0 as bigint)
        end as redeemed_points,

        -- Signed adjustment movement
        case
            when t.transaction_type = 'ADJUST'
            then cast(t.points_delta as bigint)
            else cast(0 as bigint)
        end as adjustment_points

    from loyalty_transactions as t

    inner join loyalty_accounts as a
        on t.loyalty_account_id = a.loyalty_account_id

    left join orders as o
        on t.reference_order_number = o.order_number

)

select *
from final
