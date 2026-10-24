
-- Validate payment attempt count consistency.
-- Each payment attempt belongs to one payment status.
-- Any returned row represents a data quality failure.

select
    order_id,
    payment_attempt_count,
    successful_payment_count,
    failed_payment_count,
    pending_payment_count

from {{ ref('int_payments_by_order') }}

where
    payment_attempt_count <= 0

    or successful_payment_count < 0

    or failed_payment_count < 0

    or pending_payment_count < 0

    or payment_attempt_count <> (
        successful_payment_count
        + failed_payment_count
        + pending_payment_count
    )
