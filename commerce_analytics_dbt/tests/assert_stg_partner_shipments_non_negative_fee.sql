
-- Validate that shipping fees are non-negative.
-- Zero shipping fee is allowed.
-- NULL values are covered by the existing not_null test.
-- Any returned row represents a data quality failure.

select
    shipment_id,
    order_number,
    shipping_fee_egp

from {{ ref('stg_partner_shipments') }}

where shipping_fee_egp < 0
