
with order_items as (

    select
        order_id,
        order_item_id,
        quantity,
        unit_price_egp,
        discount_amount_egp

    from {{ ref('stg_oltp_order_items') }}

),

aggregated as (

    select
        order_id,

        count_big(*) as order_item_count,

        sum(
            cast(quantity as bigint)
        ) as total_quantity,

        cast(
            sum(
                quantity * unit_price_egp
            ) as decimal(18, 2)
        ) as gross_item_amount_egp,

        cast(
            sum(discount_amount_egp)
            as decimal(18, 2)
        ) as total_discount_amount_egp,

        cast(
            sum(
                quantity * unit_price_egp
                - discount_amount_egp
            ) as decimal(18, 2)
        ) as net_item_amount_egp

    from order_items
    group by order_id

)

select *
from aggregated
