
-- Gold Application Events Fact
-- Grain: one row per event_id
--
-- All events are retained, including anonymous events.
-- Customer, order, and product relationships are optional.
--
-- Event timestamps are verified UTC (+00:00).
--
-- receive_delay_seconds measures the time between
-- event occurrence and source-reported receipt.
-- It is NOT warehouse ingestion latency.
--
-- Application events do not independently establish
-- completed orders, successful payments, or revenue.

with app_events as (

    select
        event_id,
        event_name,
        session_id,
        channel,
        customer_code,
        anonymous_id,
        order_number,
        product_sku,
        event_time_utc,
        received_at_utc,
        source_system,
        source_batch,
        source_file_name,
        source_line_number

    from {{ ref('stg_app_events') }}

),

current_customers as (

    select
        customer_code,
        customer_id

    from {{ ref('dim_customers') }}

    where is_current = 1

),

orders as (

    select
        order_number,
        order_id

    from {{ ref('fact_orders') }}

),

products as (

    select
        sku,
        product_id

    from {{ ref('dim_products') }}

),

final as (

    select

        -- Event identity
        e.event_id,
        e.event_name,
        e.session_id,

        -- Event channel
        e.channel,

        -- Original source identities
        e.customer_code,
        e.anonymous_id,

        -- Stable customer identifier
        -- NULL for anonymous events
        c.customer_id,

        -- Optional order reference
        e.order_number,
        o.order_id,

        -- Optional product reference
        e.product_sku,
        p.product_id,

        -- UTC event timestamp
        e.event_time_utc,

        convert(
            int,
            convert(
                char(8),
                cast(e.event_time_utc as date),
                112
            )
        ) as event_date_key,

        -- UTC source reception timestamp
        e.received_at_utc,

        convert(
            int,
            convert(
                char(8),
                cast(e.received_at_utc as date),
                112
            )
        ) as received_date_key,

        -- Additive event count
        1 as event_count,

        -- Observed source reception delay
        datediff_big(
            second,
            e.event_time_utc,
            e.received_at_utc
        ) as receive_delay_seconds,

        -- Source and file lineage
        e.source_system,
        e.source_batch,
        e.source_file_name,
        e.source_line_number

    from app_events as e

    left join current_customers as c
        on e.customer_code = c.customer_code

    left join orders as o
        on e.order_number = o.order_number

    left join products as p
        on e.product_sku = p.sku

)

select *
from final
