
-- Validate loyalty transaction points sign conventions.
-- Any returned row represents a data quality failure.
-- Rules are provisional pending CRM business confirmation.

select
    loyalty_transaction_id,
    loyalty_account_id,
    transaction_type,
    points_delta

from {{ ref('stg_crm_loyalty_transactions') }}

where
    (transaction_type = 'EARN' and points_delta <= 0)

    or (transaction_type = 'REDEEM' and points_delta >= 0)

    or (transaction_type = 'ADJUST' and points_delta = 0)
