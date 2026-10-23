
with source as (

    select *
    from {{ source('mysql_crm', 'crm_campaigns') }}

),

renamed as (

    select
        campaign_id,
        campaign_code,
        campaign_name,
        channel,
        campaign_status,
        starts_at,
        ends_at,
        updated_at

    from source

)

select *
from renamed
