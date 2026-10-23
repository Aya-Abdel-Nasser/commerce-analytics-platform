
-- Validate Returns API timestamp chronology.
-- A return must not be updated before it was requested.
-- NULL values are covered by existing generic tests.
-- Any returned row represents a data quality failure.

select
    return_id,
    order_number,
    return_status,
    requested_at,
    updated_at

from {{ ref('stg_returns') }}

where updated_at < requested_at
