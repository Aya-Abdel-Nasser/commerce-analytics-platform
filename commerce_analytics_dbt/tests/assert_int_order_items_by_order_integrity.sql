
-- Validate order-level item counts and financial integrity.
-- Any returned row represents a data quality failure.
-- NULL measures are covered by existing generic tests.

select
    order_id,
    order_item_count,
    total_quantity,
    gross_item_amount_egp,
    total_discount_amount_egp,
    net_item_amount_egp

from {{ ref('int_order_items_by_order') }}

where
    order_item_count <= 0

    or total_quantity <= 0

    or total_quantity < order_item_count

    or gross_item_amount_egp < 0

    or total_discount_amount_egp < 0

    or total_discount_amount_egp > gross_item_amount_egp

    or net_item_amount_egp < 0

    or gross_item_amount_egp
       - total_discount_amount_egp
       <> net_item_amount_egp
