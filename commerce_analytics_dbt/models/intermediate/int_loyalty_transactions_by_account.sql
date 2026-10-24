
with loyalty_transactions as (

    select
        loyalty_account_id,
        loyalty_transaction_id,
        transaction_type,
        points_delta

    from {{ ref('stg_crm_loyalty_transactions') }}

),

aggregated as (

    select
        loyalty_account_id,

        count_big(*) as loyalty_transaction_count,

        sum(
            case
                when transaction_type = 'EARN'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as earn_transaction_count,

        sum(
            case
                when transaction_type = 'REDEEM'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as redeem_transaction_count,

        sum(
            case
                when transaction_type = 'ADJUST'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as adjust_transaction_count,

        sum(
            case
                when transaction_type = 'EARN'
                then cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as earned_points,

        sum(
            case
                when transaction_type = 'REDEEM'
                then -cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as redeemed_points,

        sum(
            case
                when transaction_type = 'ADJUST'
                then cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as net_adjustment_points,

        sum(
            cast(points_delta as bigint)
        ) as net_points_delta

    from loyalty_transactions

    group by loyalty_account_id

)

select *
from aggregated
