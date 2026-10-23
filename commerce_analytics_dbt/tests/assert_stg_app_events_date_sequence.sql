
-- Validate application event timestamp chronology.
-- The event must not be received before it occurred.
-- NULL timestamps are covered by existing generic tests.
-- This is a provisional temporal integrity rule.

select
    event_id,
    event_name,
    session_id,
    event_time_utc,
    received_at_utc

from {{ ref('stg_app_events') }}

where received_at_utc < event_time_utc
