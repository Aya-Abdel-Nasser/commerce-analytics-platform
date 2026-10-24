
-- Validate customer identity and loyalty integration rules.
-- Any returned row represents a data quality failure.

select
    customer_id,
    customer_code,
    crm_customer_id,
    external_customer_code,
    loyalty_account_id,
    has_loyalty_account,
    loyalty_tier,
    points_balance,
    loyalty_transaction_count,
    net_points_delta

from {{ ref('int_customers_integrated') }}

where

    -- CRM business key must match OLTP business key.
    (
        crm_customer_id is not null
        and (
            external_customer_code is null
            or customer_code <> external_customer_code
        )
    )

    -- A loyalty account requires a CRM customer.
    or (
        loyalty_account_id is not null
        and crm_customer_id is null
    )

    -- Loyalty flag must match account existence.
    or (
        loyalty_account_id is not null
        and (
            has_loyalty_account is null
            or has_loyalty_account <> 1
        )
    )

    or (
        loyalty_account_id is null
        and (
            has_loyalty_account is null
            or has_loyalty_account <> 0
        )
    )

    -- Customers without loyalty accounts must not
    -- contain loyalty attributes or transaction measures.
    or (
        loyalty_account_id is null
        and (
            loyalty_tier is not null
            or points_balance is not null
            or loyalty_transaction_count is not null
            or earn_transaction_count is not null
            or redeem_transaction_count is not null
            or adjust_transaction_count is not null
            or earned_points is not null
            or redeemed_points is not null
            or net_adjustment_points is not null
            or net_points_delta is not null
        )
    )

    -- Existing loyalty accounts must retain
    -- their required account attributes.
    or (
        loyalty_account_id is not null
        and (
            loyalty_tier is null
            or points_balance is null
        )
    )
