
-- Reconcile integrated loyalty accounts with upstream models.
-- Any returned row represents a data quality failure.

with expected_accounts as (

    select
        a.loyalty_account_id,
        a.crm_customer_id,
        a.loyalty_tier,
        a.points_balance,

        t.loyalty_transaction_count,
        t.earn_transaction_count,
        t.redeem_transaction_count,
        t.adjust_transaction_count,
        t.earned_points,
        t.redeemed_points,
        t.net_adjustment_points,
        t.net_points_delta

    from {{ ref('stg_crm_loyalty_accounts') }} as a

    left join {{ ref('int_loyalty_transactions_by_account') }} as t
        on a.loyalty_account_id = t.loyalty_account_id

),

reconciliation as (

    select
        e.loyalty_account_id as expected_account_id,
        i.loyalty_account_id as actual_account_id,

        case
            when e.loyalty_account_id is not null
             and i.loyalty_account_id is not null
             and exists (

                select
                    e.crm_customer_id,
                    e.loyalty_tier,
                    e.points_balance,
                    e.loyalty_transaction_count,
                    e.earn_transaction_count,
                    e.redeem_transaction_count,
                    e.adjust_transaction_count,
                    e.earned_points,
                    e.redeemed_points,
                    e.net_adjustment_points,
                    e.net_points_delta

                except

                select
                    i.crm_customer_id,
                    i.loyalty_tier,
                    i.points_balance,
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

    from expected_accounts as e

    full outer join
        {{ ref('int_loyalty_accounts_integrated') }} as i
        on e.loyalty_account_id = i.loyalty_account_id

)

select
    expected_account_id,
    actual_account_id,
    has_mismatch

from reconciliation

where
    expected_account_id is null
    or actual_account_id is null
    or has_mismatch = 1
