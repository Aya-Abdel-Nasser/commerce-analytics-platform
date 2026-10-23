
-- Each application event must have exactly one identity.
-- Either customer_code or anonymous_id must be present.
-- Both missing or both present are invalid.
-- This is a provisional business rule.

select
    event_id,
    event_name,
    session_id,
    customer_code,
    anonymous_id

from {{ ref('stg_app_events') }}

where
    (
        customer_code is null
        and anonymous_id is null
    )

    or (
        customer_code is not null
        and anonymous_id is not null
    )
