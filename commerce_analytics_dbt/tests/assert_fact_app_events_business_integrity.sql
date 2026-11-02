
-- Application Events Business Integrity
-- Expected result: zero rows
-- Grain: one row per event_id
--
-- Validates identity, optional references,
-- UTC timestamps, date keys, and event measures.
--
-- No fixed maximum receive delay is enforced.

with event_checks as (

    select
        event_id,
        event_name,

        customer_code,
        anonymous_id,
        customer_id,

        order_number,
        order_id,
        product_sku,
        product_id,

        event_time_utc,
        received_at_utc,
        event_date_key,
        received_date_key,

        event_count,
        receive_delay_seconds,

        convert(
            int,
            convert(
                char(8),
                cast(event_time_utc as date),
                112
            )
        ) as expected_event_date_key,

        convert(
            int,
            convert(
                char(8),
                cast(received_at_utc as date),
                112
            )
        ) as expected_received_date_key,

        datediff_big(
            second,
            event_time_utc,
            received_at_utc
        ) as expected_receive_delay_seconds

    from {{ ref('fact_app_events') }}

)

select *
from event_checks as e

where

    -- Exactly one source identity must be present
    (
        e.customer_code is null
        and e.anonymous_id is null
    )

    or (
        e.customer_code is not null
        and e.anonymous_id is not null
    )

    -- Identified events must resolve to a customer
    or (
        e.customer_code is not null
        and e.customer_id is null
    )

    -- Anonymous events must not be assigned a customer
    or (
        e.anonymous_id is not null
        and e.customer_id is not null
    )

    -- Optional order reference and ID must agree
    or (
        e.order_number is not null
        and e.order_id is null
    )

    or (
        e.order_number is null
        and e.order_id is not null
    )

    -- Optional product reference and ID must agree
    or (
        e.product_sku is not null
        and e.product_id is null
    )

    or (
        e.product_sku is null
        and e.product_id is not null
    )

    -- Both timestamps are required
    or e.event_time_utc is null
    or e.received_at_utc is null

    -- Both timestamps must use UTC (+00:00)
    or datepart(tzoffset, e.event_time_utc) <> 0
    or datepart(tzoffset, e.received_at_utc) <> 0

    -- Receipt cannot precede event occurrence
    or e.received_at_utc < e.event_time_utc

    -- Date keys must match UTC calendar dates
    or e.event_date_key is null
    or e.event_date_key <> e.expected_event_date_key

    or e.received_date_key is null
    or e.received_date_key <> e.expected_received_date_key

    -- Event measure integrity
    or e.event_count is null
    or e.event_count <> 1

    -- Receive delay must be nonnegative and correct
    or e.receive_delay_seconds is null
    or e.receive_delay_seconds < 0
    or e.receive_delay_seconds
        <> e.expected_receive_delay_seconds
