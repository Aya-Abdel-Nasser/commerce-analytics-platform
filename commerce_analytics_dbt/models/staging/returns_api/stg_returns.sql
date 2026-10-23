
with source as (

    select
        raw_json,
        source_file_name,
        source_line_number

    from {{ source('returns_api', 'returns_raw') }}

),

extracted as (

    select
        -- Business identifiers
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.return_id')
        )), '') as return_id,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.order_number')
        )), '') as order_number,

        -- Return attributes
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.reason_code')
        )), '') as reason_code,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.return_status')
        )), '') as return_status,

        -- Raw values requiring type conversion
        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.requested_at')
        )), '') as requested_at_raw,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.updated_at')
        )), '') as updated_at_raw,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$.payload.requested_refund_egp')
        )), '') as requested_refund_egp_raw,

        -- API metadata
        nullif(ltrim(rtrim(
            json_value(raw_json, '$._source_system')
        )), '') as source_system,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$._source_endpoint')
        )), '') as source_endpoint,

        nullif(ltrim(rtrim(
            json_value(raw_json, '$._ingested_at_utc')
        )), '') as ingested_at_raw,

        -- File-level lineage
        source_file_name,
        source_line_number

    from source

),

typed as (

    select
        return_id,
        order_number,
        reason_code,
        return_status,

        try_convert(
            datetimeoffset(0),
            requested_at_raw
        ) as requested_at,

        try_convert(
            datetimeoffset(0),
            updated_at_raw
        ) as updated_at,

        try_convert(
            decimal(18, 2),
            requested_refund_egp_raw
        ) as requested_refund_egp,

        source_system,
        source_endpoint,

        try_convert(
            datetimeoffset(0),
            ingested_at_raw
        ) as ingested_at_utc,

        source_file_name,
        source_line_number

    from extracted

)

select *
from typed
