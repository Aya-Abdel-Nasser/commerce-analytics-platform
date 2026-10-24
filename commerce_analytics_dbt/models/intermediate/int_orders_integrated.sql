
with orders as (

    select
        order_id,
        order_number,
        customer_id,
        order_status,
        sales_channel,
        order_date,
        updated_at

    from {{ ref('stg_oltp_orders') }}

),

order_items as (

    select
        order_id,
        order_item_count,
        total_quantity,
        gross_item_amount_egp,
        total_discount_amount_egp,
        net_item_amount_egp

    from {{ ref('int_order_items_by_order') }}

),

payments as (

    select
        order_id,
        payment_attempt_count,
        successful_payment_count,
        failed_payment_count,
        pending_payment_count,
        successful_payment_amount_egp,
        has_successful_payment,
        has_payment_retry

    from {{ ref('int_payments_by_order') }}

),

integrated as (

    select
        -- Order attributes
        o.order_id,
        o.order_number,
        o.customer_id,
        o.order_status,
        o.sales_channel,
        o.order_date,
        o.updated_at,

        -- Order item measures
        i.order_item_count,
        i.total_quantity,
        i.gross_item_amount_egp,
        i.total_discount_amount_egp,
        i.net_item_amount_egp,

        -- Payment measures
        p.payment_attempt_count,
        p.successful_payment_count,
        p.failed_payment_count,
        p.pending_payment_count,
        p.successful_payment_amount_egp,
        p.has_successful_payment,
        p.has_payment_retry

    from orders as o

    left join order_items as i
        on o.order_id = i.order_id

    left join payments as p
        on o.order_id = p.order_id

)

select *
from integrated
