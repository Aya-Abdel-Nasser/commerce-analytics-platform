
-- Application Sessions Business Integrity
-- Expected result: zero rows
-- Grain: one row per session_id

with session_checks as (

    select
        session_id,
        channel,
        customer_code,
        anonymous_id,
        customer_id,

        session_started_at_utc,
        first_event_at_utc,
        last_event_at_utc,
        session_date_key,

        observed_session_duration_seconds,

        session_count,
        event_count,

        session_started_event_count,
        product_view_event_count,
        add_to_cart_event_count,
        checkout_started_event_count,
        order_submitted_event_count,
        payment_submitted_event_count,
        purchase_completed_event_count,
        checkout_cancelled_event_count,

        convert(
            int,
            convert(
                char(8),
                cast(session_started_at_utc as date),
                112
            )
        ) as expected_session_date_key,

        datediff_big(
            second,
            first_event_at_utc,
            last_event_at_utc
        ) as expected_duration_seconds

    from {{ ref('fact_app_sessions') }}

)

select *
from session_checks as s

where

    -- One session per fact row
    s.session_count is null
    or s.session_count <> 1

    -- Exactly one session_started event
    or s.session_started_event_count is null
    or s.session_started_event_count <> 1

    -- Required event total
    or s.event_count is null
    or s.event_count < 1

    -- Event counts must be nonnegative
    or s.product_view_event_count is null
    or s.product_view_event_count < 0

    or s.add_to_cart_event_count is null
    or s.add_to_cart_event_count < 0

    or s.checkout_started_event_count is null
    or s.checkout_started_event_count < 0

    or s.order_submitted_event_count is null
    or s.order_submitted_event_count < 0

    or s.payment_submitted_event_count is null
    or s.payment_submitted_event_count < 0

    or s.purchase_completed_event_count is null
    or s.purchase_completed_event_count < 0

    or s.checkout_cancelled_event_count is null
    or s.checkout_cancelled_event_count < 0

    -- Event-type counts must reconcile to total
    or (
        coalesce(s.session_started_event_count, -1)
        + coalesce(s.product_view_event_count, -1)
        + coalesce(s.add_to_cart_event_count, -1)
        + coalesce(s.checkout_started_event_count, -1)
        + coalesce(s.order_submitted_event_count, -1)
        + coalesce(s.payment_submitted_event_count, -1)
        + coalesce(s.purchase_completed_event_count, -1)
        + coalesce(s.checkout_cancelled_event_count, -1)
    ) <> s.event_count

    -- Exactly one identity type per session
    or (
        s.customer_code is null
        and s.anonymous_id is null
    )

    or (
        s.customer_code is not null
        and s.anonymous_id is not null
    )

    -- Identified sessions must have a customer ID
    or (
        s.customer_code is not null
        and s.customer_id is null
    )

    -- Anonymous sessions must not have a customer ID
    or (
        s.anonymous_id is not null
        and s.customer_id is not null
    )

    -- Required timestamps
    or s.session_started_at_utc is null
    or s.first_event_at_utc is null
    or s.last_event_at_utc is null

    -- UTC offsets
    or datepart(tzoffset, s.session_started_at_utc) <> 0
    or datepart(tzoffset, s.first_event_at_utc) <> 0
    or datepart(tzoffset, s.last_event_at_utc) <> 0

    -- Session start must be within observed time bounds
    or s.session_started_at_utc < s.first_event_at_utc
    or s.session_started_at_utc > s.last_event_at_utc

    -- Time ordering
    or s.last_event_at_utc < s.first_event_at_utc

    -- Session date key
    or s.session_date_key is null
    or s.session_date_key <> s.expected_session_date_key

    -- Observed duration
    or s.observed_session_duration_seconds is null
    or s.observed_session_duration_seconds < 0
    or s.observed_session_duration_seconds
        <> s.expected_duration_seconds
