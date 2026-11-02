
-- Campaign Dimension Business Integrity
-- Expected result: zero rows
-- Each returned row represents an invalid campaign.

with campaign_checks as (

    select
        campaign_id,
        campaign_status,
        starts_at,
        ends_at,
        start_date_key,
        end_date_key,

        convert(
            int,
            convert(char(8), starts_at, 112)
        ) as expected_start_date_key,

        convert(
            int,
            convert(char(8), ends_at, 112)
        ) as expected_end_date_key

    from {{ ref('dim_campaigns') }}

)

select *
from campaign_checks

where

    -- Required timestamps and date keys
    starts_at is null
    or ends_at is null
    or start_date_key is null
    or end_date_key is null

    -- Campaign must not end before it starts
    or ends_at < starts_at

    -- Start date key must match source date
    or start_date_key <> expected_start_date_key

    -- End date key must match source date
    or end_date_key <> expected_end_date_key
