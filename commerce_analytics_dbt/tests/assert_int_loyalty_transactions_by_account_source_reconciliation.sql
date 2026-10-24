
-- Reconcile loyalty transaction aggregates with staging.
-- Any returned row represents a data quality failure.

with source_aggregates as (

    select
        loyalty_account_id,

        count_big(*) as source_transaction_count,

        sum(
            case when transaction_type = 'EARN'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as source_earn_count,

        sum(
            case when transaction_type = 'REDEEM'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as source_redeem_count,

        sum(
            case when transaction_type = 'ADJUST'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as source_adjust_count,

        sum(
            case when transaction_type = 'EARN'
                then cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as source_earned_points,

        sum(
            case when transaction_type = 'REDEEM'
                then -cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as source_redeemed_points,

        sum(
            case when transaction_type = 'ADJUST'
                then cast(points_delta as bigint)
                else cast(0 as bigint)
            end
        ) as source_adjustment_points,

        sum(cast(points_delta as bigint))
            as source_net_points

    from {{ ref('stg_crm_loyalty_transactions') }}

    group by loyalty_account_id

),

reconciliation as (

    select
        s.loyalty_account_id as source_account_id,
        i.loyalty_account_id as intermediate_account_id,

        case
            when s.loyalty_account_id is not null
             and i.loyalty_account_id is not null
             and exists (

                select
                    s.source_transaction_count,
                    s.source_earn_count,
                    s.source_redeem_count,
                    s.source_adjust_count,
                    s.source_earned_points,
                    s.source_redeemed_points,
                    s.source_adjustment_points,
                    s.source_net_points

                except

                select
                    i.loyalty_transaction_count,
                    i.earn_transaction_count,
                    i.redeem_transaction_count,
                    i.adjust_transaction_count,
                    i.earned_points,
                    i.redeemed_points,
                    i.net_adjustment_points,
                    i.net_points_delta

             )
            then 1
            else 0
        end as has_mismatch

    from source_aggregates as s

    full outer join
        {{ ref('int_loyalty_transactions_by_account') }} as i
        on s.loyalty_account_id = i.loyalty_account_id

)

select
    source_account_id,
    intermediate_account_id,
    has_mismatch

from reconciliation

where
    source_account_id is null
    or intermediate_account_id is null
    or has_mismatch = 1
