
-- Validate campaign date ranges.
-- Any returned row represents a data quality failure.

select
    campaign_id,
    campaign_code,
    campaign_status,
    starts_at,
    ends_at

from {{ ref('stg_crm_campaigns') }}

where
    ends_at < starts_at
