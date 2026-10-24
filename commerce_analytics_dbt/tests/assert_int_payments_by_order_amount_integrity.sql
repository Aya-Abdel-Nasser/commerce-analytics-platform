
-- Validate successful payment amount integrity.
-- Orders without successful payments must have zero amount.
-- Orders with successful payments must have positive amount.
-- Any returned row represents a data quality failure.

select
    order_id,
    successful_payment_count,
    successful_payment_amount_egp

from {{ ref('int_payments_by_order') }}

where
    successful_payment_amount_egp < 0

    or (
        successful_payment_count = 0
        and successful_payment_amount_egp <> 0
    )

    or (
        successful_payment_count > 0
        and successful_payment_amount_egp <= 0
    )
