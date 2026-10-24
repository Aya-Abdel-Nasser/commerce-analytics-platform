
-- Validate order grain and aggregate preservation.
-- Return one row if any join integrity check fails.

with orders_stats as (

    select
        count_big(*) as source_order_count
    from {{ ref('stg_oltp_orders') }}

),

items_stats as (

    select
        sum(order_item_count) as source_item_count,
        sum(total_quantity) as source_total_quantity,
        sum(net_item_amount_egp) as source_net_egp

    from {{ ref('int_order_items_by_order') }}

),

payments_stats as (

    select
        sum(payment_attempt_count) as source_payment_attempts,
        sum(successful_payment_amount_egp)
            as source_successful_payment_egp

    from {{ ref('int_payments_by_order') }}

),

integrated_stats as (

    select
        count_big(*) as integrated_order_count,
        count(distinct order_id) as distinct_order_count,

        sum(order_item_count) as integrated_item_count,
        sum(total_quantity) as integrated_total_quantity,
        sum(net_item_amount_egp) as integrated_net_egp,

        sum(payment_attempt_count)
            as integrated_payment_attempts,

        sum(successful_payment_amount_egp)
            as integrated_successful_payment_egp

    from {{ ref('int_orders_integrated') }}

)

select
    o.source_order_count,
    x.integrated_order_count,
    x.distinct_order_count,

    i.source_item_count,
    x.integrated_item_count,

    i.source_total_quantity,
    x.integrated_total_quantity,

    i.source_net_egp,
    x.integrated_net_egp,

    p.source_payment_attempts,
    x.integrated_payment_attempts,

    p.source_successful_payment_egp,
    x.integrated_successful_payment_egp

from orders_stats as o
cross join items_stats as i
cross join payments_stats as p
cross join integrated_stats as x

where
    o.source_order_count <> x.integrated_order_count

    or x.integrated_order_count <> x.distinct_order_count

    or coalesce(i.source_item_count, 0)
       <> coalesce(x.integrated_item_count, 0)

    or coalesce(i.source_total_quantity, 0)
       <> coalesce(x.integrated_total_quantity, 0)

    or coalesce(i.source_net_egp, 0)
       <> coalesce(x.integrated_net_egp, 0)

    or coalesce(p.source_payment_attempts, 0)
       <> coalesce(x.integrated_payment_attempts, 0)

    or coalesce(p.source_successful_payment_egp, 0)
       <> coalesce(x.integrated_successful_payment_egp, 0)
