
-- Validate campaign membership event chronology.
-- NULL engaged_at is allowed for memberships without engagement.
-- Any returned row represents a data quality failure.

select
    campaign_id,
    crm_customer_id,
    engagement_status,
    targeted_at,
    engaged_at,
    updated_at

from {{ ref('stg_crm_campaign_memberships') }}

where
    (
        engaged_at is not null
        and engaged_at < targeted_at
    )

    or updated_at < targeted_at
