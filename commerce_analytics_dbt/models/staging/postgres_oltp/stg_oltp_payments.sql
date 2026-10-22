
with source as (

    select *
    from {{ source('postgres_oltp', 'oltp_payments') }}

),

renamed as (

    select
        payment_id,
        transaction_id,
        order_id,
        payment_method,
        payment_status,
        amount_egp,
        payment_date,
        _ingested_at_utc as ingested_at_utc

    from source

)

select *
from renamed
