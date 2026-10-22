
with source as (

    select *
    from {{ source('postgres_oltp', 'oltp_customers') }}

),

renamed as (

    select
        customer_id,
        customer_code,
        full_name,
        email,
        {{ clean_optional_text('city') }} as city,
        created_at,
        updated_at,
        _ingested_at_utc as ingested_at_utc

    from source

)

select *
from renamed
