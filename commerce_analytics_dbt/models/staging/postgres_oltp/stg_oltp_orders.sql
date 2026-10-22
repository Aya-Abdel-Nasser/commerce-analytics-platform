
with source as (

    select *
    from {{ source('postgres_oltp', 'oltp_orders') }}

),

renamed as (

    select
        order_id,
        order_number,
        customer_id,
        order_status,
        sales_channel,
        order_date,
        updated_at,
        _ingested_at_utc as ingested_at_utc

    from source

)

select *
from renamed
