
-- Validate financial rules for OLTP order items.
-- Any returned row represents a data quality failure.

select
    order_item_id,
    quantity,
    unit_price_egp,
    discount_amount_egp,
    quantity * unit_price_egp as gross_line_amount_egp

from {{ ref('stg_oltp_order_items') }}

where
    quantity <= 0
    or unit_price_egp <= 0
    or discount_amount_egp < 0
    or discount_amount_egp > quantity * unit_price_egp
