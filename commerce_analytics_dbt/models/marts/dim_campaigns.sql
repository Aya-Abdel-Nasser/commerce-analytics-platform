
-- Gold Campaign Dimension
-- Grain: one row per campaign_id
-- SCD Type 1: current-state campaign attributes
--
-- Date keys use source calendar dates.
-- Source timezone is not independently verified.
--
-- DRAFT campaigns are retained even when
-- they have no campaign memberships.

with campaigns as (

    select
        campaign_id,
        campaign_code,
        campaign_name,
        channel,
        campaign_status,
        starts_at,
        ends_at,
        updated_at

    from {{ ref('stg_crm_campaigns') }}

),

final as (

    select
        -- Campaign identity
        campaign_id,
        campaign_code,
        campaign_name,

        -- Current campaign attributes
        channel,
        campaign_status,

        -- Campaign start
        starts_at,

        convert(
            int,
            convert(char(8), starts_at, 112)
        ) as start_date_key,

        -- Campaign end
        ends_at,

        convert(
            int,
            convert(char(8), ends_at, 112)
        ) as end_date_key,

        -- Source update metadata
        updated_at as campaign_updated_at

    from campaigns

)

select *
from final
