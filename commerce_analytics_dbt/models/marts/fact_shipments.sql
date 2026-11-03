
-- Gold Shipment Fact Table
-- Grain: one row per shipment_id
-- Currency: EGP
--
-- Delivery duration is calculated only
-- for shipments with DELIVERED status.
--
-- DELAYED is a source-reported status,
-- not a calculated SLA violation.

with shipments as (

    select
        shipment_id,
        order_number,
        carrier_code,
        tracking_number,
        shipment_status,
        shipped_at,
        delivered_at,
        shipping_fee_egp,
        source_updated_at

    from {{ ref('stg_partner_shipments') }}

),

orders as (

    select
        order_id,
        order_number,
        customer_id,
        order_date_key

    from {{ ref('fact_orders') }}

),

final as (

    select

        -- Shipment identity
        s.shipment_id,
        s.tracking_number,

        -- Order relationship
        o.order_id,
        s.order_number,
        o.customer_id,
        o.order_date_key,

        -- Shipping attributes
        s.carrier_code,
        s.shipment_status,

        -- Original shipping timestamps
        s.shipped_at,
        s.delivered_at,
        s.source_updated_at,

        -- Date dimension keys
        {{ date_to_key('s.shipped_at') }} as shipped_date_key,

        case
            when s.delivered_at is not null
            then {{ date_to_key('s.delivered_at') }}
            else null
        end as delivered_date_key,

        -- Shipping measures
        1 as shipment_count,
        s.shipping_fee_egp,

        -- Actual delivery duration in seconds
        case
            when s.shipment_status = 'DELIVERED'
             and s.delivered_at is not null
             and s.shipped_at is not null
            then datediff_big(
                second,
                s.shipped_at,
                s.delivered_at
            )
            else null
        end as delivery_duration_seconds,

        -- Delivery flags
        case
            when s.shipment_status = 'DELIVERED'
            then 1
            else 0
        end as is_delivered,

        case
            when s.shipment_status = 'DELAYED'
            then 1
            else 0
        end as is_currently_delayed

    from shipments as s

    inner join orders as o
        on s.order_number = o.order_number

)

select *
from final
