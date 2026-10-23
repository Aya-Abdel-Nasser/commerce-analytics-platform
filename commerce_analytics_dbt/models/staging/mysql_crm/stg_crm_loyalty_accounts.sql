
with source as (

    select *
    from {{ source('mysql_crm', 'crm_loyalty_accounts') }}

),

renamed as (

    select
        loyalty_account_id,
        crm_customer_id,
        loyalty_tier,
        points_balance,
        enrolled_at,
        updated_at

    from source

)

select *
from renamed
