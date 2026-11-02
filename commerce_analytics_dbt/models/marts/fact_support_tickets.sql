
-- Gold Support Tickets Fact Table
-- Grain: one row per ticket_id
--
-- Current-state ticket fact (SCD Type 1).
--
-- Resolution duration is elapsed time between
-- created_at and resolved_at, when available.
--
-- It is NOT active handling time or SLA compliance.
--
-- Date keys use source calendar dates.
-- Source timezone is not independently verified.

with support_tickets as (

    select
        ticket_id,
        ticket_number,
        crm_customer_id,
        issue_category,
        ticket_status,
        created_at,
        resolved_at,
        updated_at

    from {{ ref('stg_crm_support_tickets') }}

),

crm_customers as (

    select
        crm_customer_id,
        external_customer_code

    from {{ ref('stg_crm_customers') }}

),

current_customers as (

    select
        customer_id,
        customer_code

    from {{ ref('dim_customers') }}

    where is_current = 1

),

final as (

    select

        -- Ticket identity
        t.ticket_id,
        t.ticket_number,

        -- Customer identity
        t.crm_customer_id,
        d.customer_id,

        -- Current ticket attributes
        t.issue_category,
        t.ticket_status,

        -- Creation timestamp and date key
        t.created_at,

        convert(
            int,
            convert(char(8), t.created_at, 112)
        ) as created_date_key,

        -- Resolution timestamp and date key
        t.resolved_at,

        case
            when t.resolved_at is not null
            then convert(
                int,
                convert(char(8), t.resolved_at, 112)
            )
            else null
        end as resolved_date_key,

        -- Source update metadata
        t.updated_at,

        -- Additive ticket count
        1 as ticket_count,

        -- Current-status indicators
        case
            when t.ticket_status = 'OPEN'
            then 1 else 0
        end as open_status_count,

        case
            when t.ticket_status = 'IN_PROGRESS'
            then 1 else 0
        end as in_progress_status_count,

        case
            when t.ticket_status = 'RESOLVED'
            then 1 else 0
        end as resolved_status_count,

        case
            when t.ticket_status = 'CLOSED'
            then 1 else 0
        end as closed_status_count,

        -- Elapsed seconds until recorded resolution
        case
            when t.resolved_at is not null
            then datediff_big(
                second,
                t.created_at,
                t.resolved_at
            )
            else null
        end as resolution_duration_seconds

    from support_tickets as t

    inner join crm_customers as c
        on t.crm_customer_id = c.crm_customer_id

    inner join current_customers as d
        on c.external_customer_code = d.customer_code

)

select *
from final
