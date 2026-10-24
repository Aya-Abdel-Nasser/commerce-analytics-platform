
-- Reconcile integrated orders against their upstream models.
-- Any returned row indicates a reconciliation failure.

with expected_orders as (

    select
        o.order_id,
        o.order_number,
        o.customer_id,
        o.order_status,
        o.sales_channel,
        o.order_date,
        o.updated_at,

        i.order_item_count,
        i.total_quantity,
        i.gross_item_amount_egp,
        i.total_discount_amount_egp,
        i.net_item_amount_egp,

        p.payment_attempt_count,
        p.successful_payment_count,
        p.failed_payment_count,
        p.pending_payment_count,
        p.successful_payment_amount_egp,
        p.has_successful_payment,
        p.has_payment_retry

    from {{ ref('stg_oltp_orders') }} as o

    left join {{ ref('int_order_items_by_order') }} as i
        on o.order_id = i.order_id

    left join {{ ref('int_payments_by_order') }} as p
        on o.order_id = p.order_id

),

reconciliation as (

    select
        e.order_id as expected_order_id,
        a.order_id as actual_order_id,

        case
            when e.order_id is not null
             and a.order_id is not null
             and exists (

                select
                    e.order_number,
                    e.customer_id,
                    e.order_status,
                    e.sales_channel,
                    e.order_date,
                    e.updated_at,

                    e.order_item_count,
                    e.total_quantity,
                    e.gross_item_amount_egp,
                    e.total_discount_amount_egp,
                    e.net_item_amount_egp,

                    e.payment_attempt_count,
                    e.successful_payment_count,
                    e.failed_payment_count,
                    e.pending_payment_count,
                    e.successful_payment_amount_egp,
                    e.has_successful_payment,
                    e.has_payment_retry

                except

                select
                    a.order_number,
                    a.customer_id,
                    a.order_status,
                    a.sales_channel,
                    a.order_date,
                    a.updated_at,

                    a.order_item_count,
                    a.total_quantity,
                    a.gross_item_amount_egp,
                    a.total_discount_amount_egp,
                    a.net_item_amount_egp,

                    a.payment_attempt_count,
                    a.successful_payment_count,
                    a.failed_payment_count,
                    a.pending_payment_count,
                    a.successful_payment_amount_egp,
                    a.has_successful_payment,
                    a.has_payment_retry
             )
            then 1
            else 0
        end as has_mismatch

    from expected_orders as e

    full outer join {{ ref('int_orders_integrated') }} as a
        on e.order_id = a.order_id

)

select
    expected_order_id,
    actual_order_id,
    has_mismatch

from reconciliation

where
    expected_order_id is null
    or actual_order_id is null
    or has_mismatch = 1
