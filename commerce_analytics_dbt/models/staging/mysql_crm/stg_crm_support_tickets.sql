
with source as (

    select *
    from {{ source('mysql_crm', 'crm_support_tickets') }}

),

renamed as (

    select
        ticket_id,
        ticket_number,
        crm_customer_id,
        issue_category,
        ticket_status,
        created_at,
        resolved_at,
        updated_at

    from source

)

select *
from renamed
