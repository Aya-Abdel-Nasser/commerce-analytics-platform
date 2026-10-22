
-- Business rule:
-- An order cannot be updated before its creation date.

select
    order_id,
    order_date,
    updated_at
from {{ ref('stg_oltp_orders') }}
where updated_at < order_date
