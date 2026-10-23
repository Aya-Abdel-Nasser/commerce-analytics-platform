
-- Validate support ticket lifecycle chronology.
-- NULL resolved_at is allowed for unresolved tickets.
-- Any returned row represents a data quality failure.

select
    ticket_id,
    ticket_number,
    ticket_status,
    created_at,
    resolved_at,
    updated_at

from {{ ref('stg_crm_support_tickets') }}

where
    (
        resolved_at is not null
        and resolved_at < created_at
    )

    or updated_at < created_at
