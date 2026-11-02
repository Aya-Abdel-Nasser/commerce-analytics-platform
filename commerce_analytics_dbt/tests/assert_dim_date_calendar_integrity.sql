
-- Validate Gold Date Dimension integrity.
-- Expected coverage: 2025-01-01 to 2027-12-31.
-- Grain: one row per calendar date.
-- Any returned row represents a test failure.

with calendar_stats as (

    select
        count_big(*) as total_rows,

        count(distinct full_date) as distinct_dates,

        min(full_date) as earliest_date,

        max(full_date) as latest_date

    from {{ ref('dim_date') }}

),

invalid_attributes as (

    select
        count_big(*) as invalid_rows

    from {{ ref('dim_date') }}

    where
        date_key is null
        or full_date is null

        or date_key <> cast(
            convert(char(8), full_date, 112) as int
        )

        or year_number <> year(full_date)

        or quarter_number <> datepart(quarter, full_date)

        or month_number <> month(full_date)

        or day_of_month <> day(full_date)

        or iso_week_number <> datepart(iso_week, full_date)

        or day_of_week_iso <> (
            datediff(
                day,
                cast('19000101' as date),
                full_date
            ) % 7 + 1
        )

        or is_weekend <> (
            case
                when datediff(
                    day,
                    cast('19000101' as date),
                    full_date
                ) % 7 + 1 in (6, 7)
                then 1
                else 0
            end
        )

        or month_start_date <> datefromparts(
            year(full_date),
            month(full_date),
            1
        )

),

validation as (

    select
        s.total_rows,
        s.distinct_dates,
        s.earliest_date,
        s.latest_date,
        a.invalid_rows

    from calendar_stats as s
    cross join invalid_attributes as a

)

select *
from validation

where
    total_rows <> 1095

    or distinct_dates <> 1095

    or earliest_date <> cast('20250101' as date)

    or latest_date <> cast('20271231' as date)

    or invalid_rows <> 0
