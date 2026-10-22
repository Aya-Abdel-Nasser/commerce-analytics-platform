
-- Payments business rules.
-- Any returned row represents a data quality failure.

select
    payment_id,
    transaction_id,
    payment_status,
    amount_egp,
    payment_date

from {{ ref('stg_oltp_payments') }}

where
    amount_egp <= 0

    or (
        payment_status = 'SUCCESS'
        and payment_date is null
    )
