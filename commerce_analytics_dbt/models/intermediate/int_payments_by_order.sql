
with payments as (

    select
        order_id,
        payment_id,
        payment_status,
        amount_egp

    from {{ ref('stg_oltp_payments') }}

),

payment_aggregates as (

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

    from payments
    group by order_id

),

final as (

    select
        order_id,
        payment_attempt_count,
        successful_payment_count,
        failed_payment_count,
        pending_payment_count,
        successful_payment_amount_egp,

        case
            when successful_payment_count > 0
            then 1
            else 0
        end as has_successful_payment,

        case
            when payment_attempt_count > 1
            then 1
            else 0
        end as has_payment_retry

    from payment_aggregates

)

select *
from final
