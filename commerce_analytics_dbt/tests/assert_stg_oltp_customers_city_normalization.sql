
-- Test: Staging city values must match
-- the approved Bronze normalization rule.

with expected as (

    select
        customer_id,
        NULLIF(LTRIM(RTRIM(city)), '') as city
    from {{ source('postgres_oltp', 'oltp_customers') }}

),

actual as (

    select
        customer_id,
        city
    from {{ ref('stg_oltp_customers') }}

),

missing_or_different as (

    select customer_id, city from expected
    except
    select customer_id, city from actual

),

unexpected_or_different as (

    select customer_id, city from actual
    except
    select customer_id, city from expected

)

select
    'missing_or_different' as issue_type,
    customer_id,
    city
from missing_or_different

union all

select
    'unexpected_or_different' as issue_type,
    customer_id,
    city
from unexpected_or_different
