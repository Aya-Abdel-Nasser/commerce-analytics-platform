
-- Gold Product Dimension
-- SCD Type 1: Current Product State
-- Grain: one row per product_id
--
-- Product attributes are overwritten when
-- the model is rebuilt from refreshed source data.
-- Historical transaction prices are preserved
-- separately in fact_order_items.

with products as (

    select
        product_id,
        sku,
        product_name,
        category,
        list_price_egp,
        created_at,
        updated_at

    from {{ ref('stg_oltp_products') }}

),

final as (

    select
        -- Product identity
        product_id,
        sku,

        -- Current product attributes
        product_name,
        category,

        -- Current catalog price, not transaction price
        list_price_egp as current_list_price_egp,

        -- Product lifecycle metadata
        created_at as product_created_at,
        updated_at as product_updated_at

    from products

)

select *
from final
