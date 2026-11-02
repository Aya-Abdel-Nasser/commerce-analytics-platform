
-- Gold Shipments: Delivery Business Integrity
-- Expected result: zero rows
-- Grain: one row per invalid shipment

WITH delivery_checks AS (

    SELECT
        shipment_id,
        shipment_status,
        shipped_at,
        delivered_at,
        delivered_date_key,
        delivery_duration_seconds,
        is_delivered,
        is_currently_delayed,

        CASE
            WHEN shipment_status = 'DELIVERED'
            THEN 1 ELSE 0
        END AS expected_delivered_flag,

        CASE
            WHEN shipment_status = 'DELAYED'
            THEN 1 ELSE 0
        END AS expected_delayed_flag,

        CASE
            WHEN delivered_at IS NOT NULL
            THEN CONVERT(
                INT,
                CONVERT(CHAR(8), delivered_at, 112)
            )
            ELSE NULL
        END AS expected_delivered_date_key,

        CASE
            WHEN delivered_at IS NOT NULL
             AND shipped_at IS NOT NULL
            THEN DATEDIFF_BIG(
                SECOND,
                shipped_at,
                delivered_at
            )
            ELSE NULL
        END AS expected_delivery_duration

    FROM {{ ref('fact_shipments') }}

)

SELECT *
FROM delivery_checks

WHERE

    -- Every shipment must have a dispatch timestamp
    shipped_at IS NULL

    -- Delivered shipments require completion metadata
    OR (
        shipment_status = 'DELIVERED'
        AND (
            delivered_at IS NULL
            OR delivered_date_key IS NULL
            OR delivery_duration_seconds IS NULL
        )
    )

    -- Undelivered shipments cannot have delivery metadata
    OR (
        shipment_status <> 'DELIVERED'
        AND (
            delivered_at IS NOT NULL
            OR delivered_date_key IS NOT NULL
            OR delivery_duration_seconds IS NOT NULL
        )
    )

    -- Delivery cannot happen before dispatch
    OR (
        delivered_at IS NOT NULL
        AND delivered_at < shipped_at
    )

    -- Delivery duration must match the timestamps
    OR (
        shipment_status = 'DELIVERED'
        AND delivery_duration_seconds
            <> expected_delivery_duration
    )

    -- Delivery date key must match delivery timestamp
    OR (
        delivered_at IS NOT NULL
        AND delivered_date_key
            <> expected_delivered_date_key
    )

    -- Flags must match shipment status
    OR is_delivered <> expected_delivered_flag

    OR is_currently_delayed <> expected_delayed_flag
