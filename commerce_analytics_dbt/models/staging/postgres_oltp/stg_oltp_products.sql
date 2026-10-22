
with source as (

    select *
    from {{ source('postgres_oltp', 'oltp_products') }}

),

renamed as (

    select
        product_id,
        sku,
        product_name,
        category,
        list_price_egp,
        created_at,
        updated_at,
        _ingested_at_utc as ingested_at_utc

    from source

)

select *
from renamed
