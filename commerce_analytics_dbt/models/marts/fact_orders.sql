
-- Gold Order Fact Table
-- Grain: one row per order_id
-- Monetary currency: EGP
--
-- Customer historical attribution is not performed
-- because observed SCD history does not cover
-- the historical order dates.

with orders as (

    select
        order_id,
        order_number,
        customer_id,
        order_status,
        sales_channel,
        order_date,
        updated_at,

        -- Item measures
        order_item_count,
        total_quantity,
        gross_item_amount_egp,
        total_discount_amount_egp,
        net_item_amount_egp,

        -- Payment measures
        payment_attempt_count,
        successful_payment_count,
        failed_payment_count,
        pending_payment_count,
        successful_payment_amount_egp,
        has_successful_payment,
        has_payment_retry

    from {{ ref('int_orders_integrated') }}

),

final as (

    select

        -- Degenerate dimension / order identifiers
        order_id,
        order_number,

        -- Stable customer identifier
        customer_id,

        -- Date dimension relationship
        convert(
            int,
            convert(char(8), order_date, 112)
        ) as order_date_key,

        -- Preserve the full source timestamp
        order_date,
        updated_at as order_updated_at,

        -- Descriptive attributes
        order_status,
        sales_channel,

        -- Additive order measure
        1 as order_count,

        -- Item measures
        order_item_count,
        total_quantity,
        gross_item_amount_egp,
        total_discount_amount_egp,
        net_item_amount_egp,

        -- Payment measures
        payment_attempt_count,
        successful_payment_count,
        failed_payment_count,
        pending_payment_count,
        successful_payment_amount_egp,

        -- Payment behavior flags
        has_successful_payment,
        has_payment_retry,

        -- Data availability indicators
        case
            when order_item_count is not null then 1
            else 0
        end as has_order_items,

        case
            when payment_attempt_count is not null then 1
            else 0
        end as has_payment_attempts

    from orders

)

select *
from final
