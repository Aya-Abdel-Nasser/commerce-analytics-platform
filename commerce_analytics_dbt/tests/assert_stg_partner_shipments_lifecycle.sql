
-- Validate partner shipment lifecycle and chronology.
-- Any returned row represents a data quality failure.
-- Status-to-delivery rules are provisional.

select
    shipment_id,
    order_number,
    shipment_status,
    shipped_at,
    delivered_at,
    source_updated_at

from {{ ref('stg_partner_shipments') }}

where
    (
        shipment_status = 'DELIVERED'
        and delivered_at is null
    )

    or (
        shipment_status in ('IN_TRANSIT', 'DELAYED')
        and delivered_at is not null
    )

    or (
        delivered_at is not null
        and delivered_at < shipped_at
    )

    or source_updated_at < shipped_at
