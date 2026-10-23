
-- Validate requested refund amounts.
-- Negative refund amounts are not allowed.
-- Zero is provisionally allowed.
-- NULL values are covered by the generic not_null test.
-- Any returned row represents a data quality failure.

select
    return_id,
    order_number,
    return_status,
    requested_refund_egp

from {{ ref('stg_returns') }}

where requested_refund_egp < 0
