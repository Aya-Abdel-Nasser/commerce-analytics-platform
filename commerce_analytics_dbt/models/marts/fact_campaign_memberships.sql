
-- Gold Campaign Membership Fact Table
-- Grain: one row per (campaign_id, crm_customer_id)
--
-- Current-state membership fact.
-- Engagement statuses are mutually exclusive
-- within each membership row.
--
-- Status indicators are NOT historical funnel events.
-- CONVERTED represents a CRM-reported status,
-- not a verified purchase or attributed revenue.
--
-- Date keys use source calendar dates.
-- Source timezone is not independently verified.

with campaign_memberships as (

    select
        campaign_id,
        crm_customer_id,
        engagement_status,
        targeted_at,
        engaged_at,
        updated_at

    from {{ ref('stg_crm_campaign_memberships') }}

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

        -- Composite business grain
        m.campaign_id,
        m.crm_customer_id,

        -- Stable customer identity
        d.customer_id,

        -- Current CRM membership status
        m.engagement_status,

        -- Targeting timestamp
        m.targeted_at,

        convert(
            int,
            convert(char(8), m.targeted_at, 112)
        ) as targeted_date_key,

        -- Source engagement timestamp
        -- NULL is valid for TARGETED status
        m.engaged_at,

        case
            when m.engaged_at is not null
            then convert(
                int,
                convert(char(8), m.engaged_at, 112)
            )
            else null
        end as engaged_date_key,

        -- Source update metadata
        m.updated_at as membership_updated_at,

        -- Additive membership count
        1 as membership_count,

        -- Current-status indicators
        case
            when m.engagement_status = 'TARGETED'
            then 1 else 0
        end as targeted_status_count,

        case
            when m.engagement_status = 'SENT'
            then 1 else 0
        end as sent_status_count,

        case
            when m.engagement_status = 'OPENED'
            then 1 else 0
        end as opened_status_count,

        case
            when m.engagement_status = 'CONVERTED'
            then 1 else 0
        end as converted_status_count

    from campaign_memberships as m

    inner join crm_customers as c
        on m.crm_customer_id = c.crm_customer_id

    inner join current_customers as d
        on c.external_customer_code = d.customer_code

)

select *
from final
