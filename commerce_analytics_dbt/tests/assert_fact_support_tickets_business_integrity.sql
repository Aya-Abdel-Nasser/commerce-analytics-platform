
-- Support Tickets Business Integrity
-- Expected result: zero rows
-- Each returned row represents an invalid ticket.

with ticket_checks as (

    select
        t.ticket_id,
        t.crm_customer_id,
        t.customer_id,
        t.ticket_status,

        t.ticket_count,
        t.open_status_count,
        t.in_progress_status_count,
        t.resolved_status_count,
        t.closed_status_count,

        t.created_at,
        t.created_date_key,
        t.resolved_at,
        t.resolved_date_key,
        t.updated_at,

        t.resolution_duration_seconds,

        convert(
            int,
            convert(char(8), t.created_at, 112)
        ) as expected_created_date_key,

        case
            when t.resolved_at is not null
            then convert(
                int,
                convert(char(8), t.resolved_at, 112)
            )
        end as expected_resolved_date_key,

        case
            when t.resolved_at is not null
             and t.created_at is not null
            then datediff_big(
                second,
                t.created_at,
                t.resolved_at
            )
        end as expected_resolution_seconds

    from {{ ref('fact_support_tickets') }} as t

)

select *
from ticket_checks as t

where

    -- Exactly one ticket per row
    t.ticket_count is null
    or t.ticket_count <> 1

    -- Exactly one current-status indicator
    or (
        coalesce(t.open_status_count, -1)
        + coalesce(t.in_progress_status_count, -1)
        + coalesce(t.resolved_status_count, -1)
        + coalesce(t.closed_status_count, -1)
    ) <> 1

    -- Indicators must match current ticket status
    or coalesce(t.open_status_count, -1) <>
        case when t.ticket_status = 'OPEN'
             then 1 else 0 end

    or coalesce(t.in_progress_status_count, -1) <>
        case when t.ticket_status = 'IN_PROGRESS'
             then 1 else 0 end

    or coalesce(t.resolved_status_count, -1) <>
        case when t.ticket_status = 'RESOLVED'
             then 1 else 0 end

    or coalesce(t.closed_status_count, -1) <>
        case when t.ticket_status = 'CLOSED'
             then 1 else 0 end

    -- Active tickets must not have resolution timestamps
    or (
        t.ticket_status in ('OPEN', 'IN_PROGRESS')
        and t.resolved_at is not null
    )

    -- Resolved and closed tickets require timestamps
    or (
        t.ticket_status in ('RESOLVED', 'CLOSED')
        and t.resolved_at is null
    )

    -- Timestamp ordering
    or t.created_at is null
    or t.updated_at is null
    or t.updated_at < t.created_at

    or (
        t.resolved_at is not null
        and t.resolved_at < t.created_at
    )

    -- Creation date key integrity
    or t.created_date_key is null
    or t.created_date_key <> t.expected_created_date_key

    -- No resolution timestamp => no resolution date key
    or (
        t.resolved_at is null
        and t.resolved_date_key is not null
    )

    -- Resolution date key must match timestamp
    or (
        t.resolved_at is not null
        and (
            t.resolved_date_key is null
            or t.resolved_date_key
                <> t.expected_resolved_date_key
        )
    )

    -- No resolution timestamp => no duration
    or (
        t.resolved_at is null
        and t.resolution_duration_seconds is not null
    )

    -- Recorded resolution duration integrity
    or (
        t.resolved_at is not null
        and (
            t.resolution_duration_seconds is null
            or t.resolution_duration_seconds < 0
            or t.resolution_duration_seconds
                <> t.expected_resolution_seconds
        )
    )

    -- Stable customer must have a current dimension row
    or t.customer_id is null
    or not exists (

        select 1
        from {{ ref('dim_customers') }} as d

        where d.customer_id = t.customer_id
          and d.is_current = 1

    )
