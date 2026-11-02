
-- Gold Loyalty Accounts: Business Integrity
-- Expected result: zero rows
-- Grain: one row per invalid loyalty account

with account_checks as (

    select
        loyalty_account_id,
        customer_id,
        current_points_balance,
        enrolled_at,
        enrollment_date_key,

        convert(
            int,
            convert(char(8), enrolled_at, 112)
        ) as expected_enrollment_date_key

    from {{ ref('dim_loyalty_accounts') }}

)

select
    a.*

from account_checks as a

where

    -- Current points balance must not be negative
    a.current_points_balance is null
    or a.current_points_balance < 0

    -- Enrollment timestamp and date key are required
    or a.enrolled_at is null
    or a.enrollment_date_key is null

    -- Date key must match the source calendar date
    or a.enrollment_date_key
        <> a.expected_enrollment_date_key

    -- Each loyalty account must have
    -- a matching current customer version
    or not exists (

        select 1

        from {{ ref('dim_customers') }} as c

        where c.customer_id = a.customer_id
          and c.is_current = 1

    )
