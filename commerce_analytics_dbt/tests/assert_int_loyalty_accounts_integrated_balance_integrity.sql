
-- Validate CRM-reported loyalty balances against
-- the net points calculated from transactions.
--
-- Accounts without a transaction summary are excluded
-- from the equality rule and can be monitored separately.
--
-- Any returned row represents a reconciliation failure.

select
    loyalty_account_id,
    crm_customer_id,
    points_balance,
    loyalty_transaction_count,
    net_points_delta

from {{ ref('int_loyalty_accounts_integrated') }}

where
    loyalty_transaction_count is not null

    and (
        net_points_delta is null

        or cast(points_balance as bigint)
           <> net_points_delta
    )
