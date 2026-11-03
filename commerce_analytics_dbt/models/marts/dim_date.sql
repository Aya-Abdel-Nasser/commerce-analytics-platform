
-- Gold Date Dimension
-- Grain: one row per calendar date
-- Coverage: 2025-01-01 through 2027-12-31

with digits as (

    select digit
    from (
        values
            (0), (1), (2), (3), (4),
            (5), (6), (7), (8), (9)
    ) as d(digit)

),

numbers as (

    select
          ones.digit
        + tens.digit * 10
        + hundreds.digit * 100
        + thousands.digit * 1000 as day_offset

    from digits as ones
    cross join digits as tens
    cross join digits as hundreds
    cross join digits as thousands

),

calendar_dates as (

    select
        dateadd(
            day,
            day_offset,
            cast('20250101' as date)
        ) as full_date

    from numbers

    where day_offset <= datediff(
        day,
        cast('20250101' as date),
        cast('20271231' as date)
    )

),

date_attributes as (

    select
        full_date,

        datediff(
            day,
            cast('19000101' as date),
            full_date
        ) % 7 + 1 as day_of_week_iso

    from calendar_dates

)

select
    {{ date_to_key('full_date') }} as date_key,

    full_date,

    year(full_date) as year_number,

    datepart(quarter, full_date) as quarter_number,

    month(full_date) as month_number,

    day(full_date) as day_of_month,

    datepart(iso_week, full_date) as iso_week_number,

    day_of_week_iso,

    case
        when day_of_week_iso in (6, 7)
        then 1
        else 0
    end as is_weekend,

    datefromparts(
        year(full_date),
        month(full_date),
        1
    ) as month_start_date

from date_attributes
