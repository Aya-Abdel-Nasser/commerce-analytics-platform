
-- Business rule: Product SKU must not be blank or whitespace-only.

select
    product_id,
    sku
from {{ ref('stg_oltp_products') }}
where
    nullif(ltrim(rtrim(sku)), '') is null
