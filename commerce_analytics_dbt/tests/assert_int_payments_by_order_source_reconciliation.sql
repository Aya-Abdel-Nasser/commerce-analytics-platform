
-- Reconcile order-level payment aggregates with staging.
-- Any returned row represents a reconciliation failure.

with source_aggregates as (

    select
        order_id,

        count_big(*) as payment_attempt_count,

        sum(
            case
                when payment_status = 'SUCCESS'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as successful_payment_count,

        sum(
            case
                when payment_status = 'FAILED'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as failed_payment_count,

        sum(
            case
                when payment_status = 'PENDING'
                then cast(1 as bigint)
                else cast(0 as bigint)
            end
        ) as pending_payment_count,

        sum(
            case
                when payment_status = 'SUCCESS'
                then amount_egp
                else 0
            end
        ) as successful_payment_amount_egp

    from {{ ref('stg_oltp_payments') }}
    group by order_id

),

reconciliation as (

    select
        s.order_id as source_order_id,
        i.order_id as intermediate_order_id,

        s.payment_attempt_count as source_attempt_count,
        i.payment_attempt_count as intermediate_attempt_count,

        s.successful_payment_count as source_success_count,
        i.successful_payment_count as intermediate_success_count,

        s.failed_payment_count as source_failed_count,
        i.failed_payment_count as intermediate_failed_count,

        s.pending_payment_count as source_pending_count,
        i.pending_payment_count as intermediate_pending_count,

        s.successful_payment_amount_egp as source_success_amount,
        i.successful_payment_amount_egp as intermediate_success_amount

    from source_aggregates as s

    full outer join {{ ref('int_payments_by_order') }} as i
        on s.order_id = i.order_id

)

select *
from reconciliation

where
    source_order_id is null
    or intermediate_order_id is null

    or source_attempt_count <> intermediate_attempt_count
    or source_success_count <> intermediate_success_count
    or source_failed_count <> intermediate_failed_count
    or source_pending_count <> intermediate_pending_count

    or source_success_amount <> intermediate_success_amount

    or source_attempt_count is null
    or intermediate_attempt_count is null
    or source_success_count is null
    or intermediate_success_count is null
    or source_failed_count is null
    or intermediate_failed_count is null
    or source_pending_count is null
    or intermediate_pending_count is null
    or source_success_amount is null
    or intermediate_success_amount is null
