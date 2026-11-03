
-- Verify the date_to_key macro against known expected values.
-- The test passes when the query returns zero rows.

select
    v.input_date,
    v.expected_date_key,
    result.actual_date_key

from (
    values
        (
            cast('2026-11-03T12:08:00' as datetime2),
            20261103
        ),
        (
            cast('2024-02-29T15:30:00' as datetime2),
            20240229
        ),
        (
            cast(null as datetime2),
            cast(null as int)
        )
) as v(input_date, expected_date_key)

cross apply (
    select
        {{ date_to_key('v.input_date') }} as actual_date_key
) as result

where
    result.actual_date_key <> v.expected_date_key

    or (
        result.actual_date_key is null
        and v.expected_date_key is not null
    )

    or (
        result.actual_date_key is not null
        and v.expected_date_key is null
    )
