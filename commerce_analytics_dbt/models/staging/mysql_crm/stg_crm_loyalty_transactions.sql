
with source as (

    select *
    from {{ source('mysql_crm', 'crm_loyalty_transactions') }}

),

renamed as (

    select
        loyalty_transaction_id,
        loyalty_account_id,
        transaction_type,
        points_delta,
        reference_order_number,
        occurred_at

    from source

)

select *
from renamed
