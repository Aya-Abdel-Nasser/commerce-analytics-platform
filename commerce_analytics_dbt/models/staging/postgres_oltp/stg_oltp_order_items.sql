
with source as (

    select *
    from {{ source('postgres_oltp', 'oltp_order_items') }}

),

renamed as (

    select
        order_item_id,
        order_id,
        product_id,
        quantity,
        unit_price_egp,
        discount_amount_egp,
        _ingested_at_utc as ingested_at_utc

    from source

)

select *
from renamed
