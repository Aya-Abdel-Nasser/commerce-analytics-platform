
-- Validate loyalty transaction counts and points integrity.
-- Any returned row represents a data quality failure.
-- NULL measures are covered by existing generic tests.

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

where
    loyalty_transaction_count <= 0

    or earn_transaction_count < 0
    or redeem_transaction_count < 0
    or adjust_transaction_count < 0

    or loyalty_transaction_count
       <> earn_transaction_count
        + redeem_transaction_count
        + adjust_transaction_count

    or earned_points < 0
    or redeemed_points < 0

    or (
        earn_transaction_count = 0
        and earned_points <> 0
    )

    or (
        earn_transaction_count > 0
        and earned_points <= 0
    )

    or (
        redeem_transaction_count = 0
        and redeemed_points <> 0
    )

    or (
        redeem_transaction_count > 0
        and redeemed_points <= 0
    )

    or net_points_delta
       <> earned_points
        - redeemed_points
        + net_adjustment_points
