
-- Gold Order Item Fact Table
-- Grain: one row per order_item_id
-- Currency: EGP
--
-- Financial calculations follow
-- int_order_items_by_order business logic.

with order_items as (

    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price_egp,
        discount_amount_egp

    from {{ ref('stg_oltp_order_items') }}

),

orders as (

    select
        order_id,
        customer_id,
        order_date_key

    from {{ ref('fact_orders') }}

),

final as (

    select
        -- Transaction identity
        i.order_item_id,
        i.order_id,
        i.product_id,

        -- Related dimension identifiers
        o.customer_id,
        o.order_date_key,

        -- Item-level additive count
        1 as order_item_count,

        -- Transaction measures
        i.quantity,
        i.unit_price_egp,
        i.discount_amount_egp,

        -- Gross amount before discounts
        cast(
            i.quantity * i.unit_price_egp
            as decimal(18, 2)
        ) as gross_item_amount_egp,

        -- Net amount after item discount
        cast(
            i.quantity * i.unit_price_egp
            - i.discount_amount_egp
            as decimal(18, 2)
        ) as net_item_amount_egp

    from order_items as i

    inner join orders as o
        on i.order_id = o.order_id

)

select *
from final
