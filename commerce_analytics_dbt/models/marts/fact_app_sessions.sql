
-- Gold Application Sessions Fact
-- Grain: one row per session_id
--
-- Derived from validated Gold application events.
--
-- Event counts represent observed events.
-- They are not verified business conversions.
--
-- Observed session duration is the time between
-- the first and last recorded events.
-- It is NOT confirmed active user time.
--
-- Timestamps are UTC (+00:00).

with events as (

    select
        event_id,
        event_name,
        session_id,
        channel,
        customer_code,
        anonymous_id,
        customer_id,
        event_time_utc

    from {{ ref('fact_app_events') }}

),

session_aggregates as (

    select
        session_id,

        -- Session identity
        max(channel) as channel,
        max(customer_code) as customer_code,
        max(anonymous_id) as anonymous_id,
        max(customer_id) as customer_id,

        -- Session timestamps
        min(event_time_utc) as first_event_at_utc,
        max(event_time_utc) as last_event_at_utc,

        max(
            case
                when event_name = 'session_started'
                then event_time_utc
            end
        ) as session_started_at_utc,

        -- Event volume
        count_big(*) as event_count,

        -- Event-type counts
        sum(case
            when event_name = 'session_started'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as session_started_event_count,

        sum(case
            when event_name = 'product_viewed'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as product_view_event_count,

        sum(case
            when event_name = 'added_to_cart'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as add_to_cart_event_count,

        sum(case
            when event_name = 'checkout_started'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as checkout_started_event_count,

        sum(case
            when event_name = 'order_submitted'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as order_submitted_event_count,

        sum(case
            when event_name = 'payment_submitted'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as payment_submitted_event_count,

        sum(case
            when event_name = 'purchase_completed'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as purchase_completed_event_count,

        sum(case
            when event_name = 'checkout_cancelled'
            then cast(1 as bigint)
            else cast(0 as bigint)
        end) as checkout_cancelled_event_count

    from events

    group by session_id

),

final as (

    select
        -- Session grain
        session_id,

        -- Identity and channel
        channel,
        customer_code,
        anonymous_id,
        customer_id,

        -- Session timestamps
        session_started_at_utc,
        first_event_at_utc,
        last_event_at_utc,

        -- Session start UTC date
        convert(
            int,
            convert(
                char(8),
                cast(session_started_at_utc as date),
                112
            )
        ) as session_date_key,

        -- Observed duration in seconds
        datediff_big(
            second,
            first_event_at_utc,
            last_event_at_utc
        ) as observed_session_duration_seconds,

        -- Additive session count
        1 as session_count,

        -- Event measures
        event_count,
        session_started_event_count,
        product_view_event_count,
        add_to_cart_event_count,
        checkout_started_event_count,
        order_submitted_event_count,
        payment_submitted_event_count,
        purchase_completed_event_count,
        checkout_cancelled_event_count

    from session_aggregates

)

select *
from final
