
-- Campaign Memberships Composite Key Integrity
-- Grain: one row per (campaign_id, crm_customer_id)
-- Expected result: zero rows

select
    campaign_id,
    crm_customer_id,
    count_big(*) as duplicate_count

from {{ ref('fact_campaign_memberships') }}

group by
    campaign_id,
    crm_customer_id

having count_big(*) > 1
