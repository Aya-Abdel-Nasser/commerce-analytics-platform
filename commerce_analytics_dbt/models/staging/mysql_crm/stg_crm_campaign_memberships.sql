
with source as (

    select *
    from {{ source('mysql_crm', 'crm_campaign_memberships') }}

),

renamed as (

    select
        campaign_id,
        crm_customer_id,
        engagement_status,
        targeted_at,
        engaged_at,
        updated_at

    from source

)

select *
from renamed
