
-- Validate payment flag consistency.
-- Flags must match their underlying payment counts.
-- Any returned row represents a data quality failure.

select
    order_id,
    payment_attempt_count,
    successful_payment_count,
    has_successful_payment,
    has_payment_retry

from {{ ref('int_payments_by_order') }}

where
    has_successful_payment <> (
        case
            when successful_payment_count > 0
            then 1
            else 0
        end
    )

    or has_payment_retry <> (
        case
            when payment_attempt_count > 1
            then 1
            else 0
        end
    )
