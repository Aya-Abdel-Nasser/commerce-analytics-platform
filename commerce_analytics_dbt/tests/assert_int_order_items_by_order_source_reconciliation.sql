
-- Reconcile order item aggregates with staging.
-- Any returned row represents a data quality failure.

with source_aggregates as (

    select
        order_id,

        count_big(*) as source_item_count,

        sum(
            cast(quantity as bigint)
        ) as source_quantity,

        cast(
            sum(quantity * unit_price_egp)
            as decimal(18, 2)
        ) as source_gross_egp,

        cast(
            sum(discount_amount_egp)
            as decimal(18, 2)
        ) as source_discount_egp,

        cast(
            sum(
                quantity * unit_price_egp
                - discount_amount_egp
            ) as decimal(18, 2)
        ) as source_net_egp

    from {{ ref('stg_oltp_order_items') }}

    group by order_id

),

reconciliation as (

    select
        s.order_id as source_order_id,
        i.order_id as intermediate_order_id,

        s.source_item_count,
        i.order_item_count,

        s.source_quantity,
        i.total_quantity,

        s.source_gross_egp,
        i.gross_item_amount_egp,

        s.source_discount_egp,
        i.total_discount_amount_egp,

        s.source_net_egp,
        i.net_item_amount_egp

    from source_aggregates as s

    full outer join {{ ref('int_order_items_by_order') }} as i
        on s.order_id = i.order_id

)

select *
from reconciliation

where
    source_order_id is null
    or intermediate_order_id is null

    or source_item_count <> order_item_count
    or source_quantity <> total_quantity

    or source_gross_egp <> gross_item_amount_egp
    or source_discount_egp <> total_discount_amount_egp
    or source_net_egp <> net_item_amount_egp

    or source_item_count is null
    or order_item_count is null
    or source_quantity is null
    or total_quantity is null

    or source_gross_egp is null
    or gross_item_amount_egp is null
    or source_discount_egp is null
    or total_discount_amount_egp is null
    or source_net_egp is null
    or net_item_amount_egp is null
