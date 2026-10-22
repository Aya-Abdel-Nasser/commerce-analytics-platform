
-- Business rule: Product list price must be positive.

select
    product_id,
    list_price_egp
from {{ ref('stg_oltp_products') }}
where
    list_price_egp is null
    or list_price_egp <= 0
