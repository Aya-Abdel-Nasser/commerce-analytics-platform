
-- Loyalty Transactions Points Integrity
-- Expected result: zero rows
-- Each returned row represents a failed business rule.

with transactions as (

    select
        loyalty_transaction_id,
        transaction_type,
        points_delta,
        earned_points,
        redeemed_points,
        adjustment_points,
        transaction_count,
        occurred_at,
        transaction_date_key,

        convert(
            int,
            convert(char(8), occurred_at, 112)
        ) as expected_date_key

    from {{ ref('fact_loyalty_transactions') }}

)

select *
from transactions

where

    -- EARN: positive movement, earned measure only
    (
        transaction_type = 'EARN'
        and (
            points_delta <= 0
            or earned_points <> points_delta
            or redeemed_points <> 0
            or adjustment_points <> 0
        )
    )

    -- REDEEM: negative movement, positive redemption magnitude
    or (
        transaction_type = 'REDEEM'
        and (
            points_delta >= 0
            or earned_points <> 0
            or redeemed_points <> -points_delta
            or adjustment_points <> 0
        )
    )

    -- ADJUST: signed movement, adjustment measure only
    or (
        transaction_type = 'ADJUST'
        and (
            points_delta = 0
            or earned_points <> 0
            or redeemed_points <> 0
            or adjustment_points <> points_delta
        )
    )

    -- Net points movement must reconcile
    or points_delta <>
        earned_points
        - redeemed_points
        + adjustment_points

    -- One transaction per fact row
    or transaction_count <> 1

    -- Correct source calendar date
    or transaction_date_key <> expected_date_key
