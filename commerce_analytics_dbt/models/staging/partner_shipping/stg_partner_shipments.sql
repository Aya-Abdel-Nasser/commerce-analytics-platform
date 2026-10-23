
with source as (

    select *
    from {{ source('partner_shipping', 'partner_shipments') }}

),

normalized as (

    select
        nullif(ltrim(rtrim(shipment_id)), '') as shipment_id,
        nullif(ltrim(rtrim(order_number)), '') as order_number,
        nullif(ltrim(rtrim(carrier_code)), '') as carrier_code,
        nullif(ltrim(rtrim(tracking_number)), '') as tracking_number,
        nullif(ltrim(rtrim(shipment_status)), '') as shipment_status,

        nullif(ltrim(rtrim(shipped_at)), '') as shipped_at_raw,
        nullif(ltrim(rtrim(delivered_at)), '') as delivered_at_raw,
        nullif(ltrim(rtrim(shipping_fee_egp)), '') as shipping_fee_egp_raw,
        nullif(ltrim(rtrim(source_updated_at)), '') as source_updated_at_raw

    from source

),

typed as (

    select
        shipment_id,
        order_number,
        carrier_code,
        tracking_number,
        shipment_status,

        try_convert(
            datetime2(0),
            shipped_at_raw,
            101
        ) as shipped_at,

        try_convert(
            datetime2(0),
            delivered_at_raw,
            101
        ) as delivered_at,

        try_convert(
            decimal(18, 2),
            shipping_fee_egp_raw
        ) as shipping_fee_egp,

        try_convert(
            datetime2(0),
            source_updated_at_raw,
            101
        ) as source_updated_at

    from normalized

)

select *
from typed
