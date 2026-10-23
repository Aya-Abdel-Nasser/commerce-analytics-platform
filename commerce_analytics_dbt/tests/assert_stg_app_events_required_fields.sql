
-- Validate required fields based on event type.
-- Conditional requirements are provisional.
-- Any returned row represents a data quality failure.

select
    event_id,
    event_name,
    session_id,
    order_number,
    product_sku

from {{ ref('stg_app_events') }}

where
    (
        event_name in (
            'order_submitted',
            'payment_submitted',
            'purchase_completed',
            'checkout_cancelled'
        )
        and order_number is null
    )

    or (
        event_name in (
            'product_viewed',
            'added_to_cart',
            'checkout_started',
            'order_submitted',
            'payment_submitted',
            'purchase_completed',
            'checkout_cancelled'
        )
        and product_sku is null
    )
