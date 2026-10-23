
-- Ensure CRM external customer codes are not blank.
-- Any returned row represents a data quality failure.

select
    crm_customer_id,
    external_customer_code

from {{ ref('stg_crm_customers') }}

where
    nullif(
        ltrim(rtrim(external_customer_code)),
        ''
    ) is null
