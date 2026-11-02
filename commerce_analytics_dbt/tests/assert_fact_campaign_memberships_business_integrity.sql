
-- Campaign Memberships Business Integrity
-- Expected result: zero rows
-- Grain: one row per campaign/customer membership

with membership_checks as (

    select
        m.campaign_id,
        m.crm_customer_id,
        m.engagement_status,

        m.membership_count,
        m.targeted_status_count,
        m.sent_status_count,
        m.opened_status_count,
        m.converted_status_count,

        m.targeted_at,
        m.targeted_date_key,
        m.engaged_at,
        m.engaged_date_key,

        c.starts_at,
        c.ends_at,

        convert(
            int,
            convert(char(8), m.targeted_at, 112)
        ) as expected_targeted_date_key,

        case
            when m.engaged_at is not null
            then convert(
                int,
                convert(char(8), m.engaged_at, 112)
            )
        end as expected_engaged_date_key

    from {{ ref('fact_campaign_memberships') }} as m

    left join {{ ref('dim_campaigns') }} as c
        on m.campaign_id = c.campaign_id
)

select *
from membership_checks

where
    -- Required membership count
    membership_count is null
    or membership_count <> 1

    -- Exactly one current status
    or coalesce(targeted_status_count, -1)
     + coalesce(sent_status_count, -1)
     + coalesce(opened_status_count, -1)
     + coalesce(converted_status_count, -1) <> 1

    -- Each indicator must match its status
    or coalesce(targeted_status_count, -1) <>
        case when engagement_status = 'TARGETED'
             then 1 else 0 end

    or coalesce(sent_status_count, -1) <>
        case when engagement_status = 'SENT'
             then 1 else 0 end

    or coalesce(opened_status_count, -1) <>
        case when engagement_status = 'OPENED'
             then 1 else 0 end

    or coalesce(converted_status_count, -1) <>
        case when engagement_status = 'CONVERTED'
             then 1 else 0 end

    -- TARGETED has no engagement timestamp
    or (
        engagement_status = 'TARGETED'
        and engaged_at is not null
    )

    -- Progressed statuses have engagement timestamps
    or (
        engagement_status in ('SENT', 'OPENED', 'CONVERTED')
        and engaged_at is null
    )

    -- Engagement cannot precede targeting
    or (
        engaged_at is not null
        and engaged_at < targeted_at
    )

    -- Targeting date key integrity
    or targeted_at is null
    or targeted_date_key is null
    or targeted_date_key <> expected_targeted_date_key

    -- Engagement date key integrity, including NULL
    or (
        engaged_at is null
        and engaged_date_key is not null
    )

    or (
        engaged_at is not null
        and (
            engaged_date_key is null
            or engaged_date_key <> expected_engaged_date_key
        )
    )

    -- Campaign relationship and timeframe
    or starts_at is null
    or ends_at is null

    or targeted_at < starts_at
    or targeted_at > ends_at

    or (
        engaged_at is not null
        and (
            engaged_at < starts_at
            or engaged_at > ends_at
        )
    )
