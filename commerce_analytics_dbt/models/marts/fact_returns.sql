
-- Gold Returns Fact Table
-- Grain: one row per return_id
-- Currency: EGP
--
-- requested_refund_egp represents the requested
-- refund amount, not confirmed money refunded.
--
-- Date dimension keys use UTC calendar dates.
-- Original datetimeoffset values are preserved.

with returns as (

    select
        return_id,
        order_number,
        reason_code,
        return_status,
        requested_at,
        updated_at,
        requested_refund_egp,

        -- API and file lineage
        source_system,
        source_endpoint,
        ingested_at_utc,
        source_file_name,
        source_line_number

    from {{ ref('stg_returns') }}

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

        -- Return identity
        r.return_id,

        -- Order relationship
        o.order_id,
        r.order_number,
        o.customer_id,
        o.order_date_key,

        -- Return attributes
        r.reason_code,
        r.return_status,

        -- Original timestamps with UTC offsets
        r.requested_at,
        r.updated_at,

        -- UTC date dimension keys
        convert(
            int,
            convert(
                char(8),
                cast(
                    switchoffset(
                        r.requested_at,
                        '+00:00'
                    ) as date
                ),
                112
            )
        ) as requested_date_key,

        convert(
            int,
            convert(
                char(8),
                cast(
                    switchoffset(
                        r.updated_at,
                        '+00:00'
                    ) as date
                ),
                112
            )
        ) as updated_date_key,

        -- Additive return record count
        1 as return_count,

        -- Requested refund, not actual payout
        r.requested_refund_egp,

        -- Return status indicators
        case
            when r.return_status = 'REFUNDED'
            then 1 else 0
        end as is_refunded_status,

        case
            when r.return_status = 'APPROVED'
            then 1 else 0
        end as is_approved_status,

        -- Source lineage
        r.source_system,
        r.source_endpoint,
        r.ingested_at_utc,
        r.source_file_name,
        r.source_line_number

    from returns as r

    inner join orders as o
        on r.order_number = o.order_number

)

select *
from final
