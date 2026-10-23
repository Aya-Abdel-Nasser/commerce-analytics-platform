
with source as (

    select *
    from {{ source('mysql_crm', 'crm_customers') }}

),

renamed as (

    select
        crm_customer_id,
        external_customer_code,
        signup_at,
        customer_segment,
        marketing_opt_in,
        preferred_channel,
        updated_at

    from source

)

select *
from renamed
