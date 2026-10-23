
with source as (

    select
        raw_json,
        source_file_name,
        source_line_number

    from {{ source('application_events', 'app_events_raw') }}

),

extracted as (

    select
        -- Event identifiers
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.event_id')
        )), '') as event_id,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.event_name')
        )), '') as event_name,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.session_id')
        )), '') as session_id,

        -- Event attributes
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.channel')
        )), '') as channel,

        -- Customer identity: mutually exclusive in current data
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.customer_code')
        )), '') as customer_code,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.anonymous_id')
        )), '') as anonymous_id,

        -- Optional business references
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.order_number')
        )), '') as order_number,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.product_sku')
        )), '') as product_sku,

        -- Raw timestamps
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.event_time_utc')
        )), '') as event_time_raw,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.received_at_utc')
        )), '') as received_at_raw,

        -- JSON envelope metadata
        nullif(ltrim(rtrim(
            json_value(raw_json, '$._source_system')
        )), '') as source_system,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$._batch')
        )), '') as source_batch,

        -- File-level lineage
        source_file_name,
        source_line_number

    from source

),

typed as (

    select
        event_id,
        event_name,
        session_id,
        channel,
        customer_code,
        anonymous_id,
        order_number,
        product_sku,

        try_convert(
            datetimeoffset(0),
            event_time_raw
        ) as event_time_utc,

        try_convert(
            datetimeoffset(0),
            received_at_raw
        ) as received_at_utc,

        source_system,
        source_batch,
        source_file_name,
        source_line_number

    from extracted

)

select *
from typed
