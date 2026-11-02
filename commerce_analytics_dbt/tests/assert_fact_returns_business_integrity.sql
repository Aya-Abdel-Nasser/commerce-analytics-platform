
-- Gold Returns: Business Integrity
-- Expected result: zero rows
-- Grain: one row per invalid return

WITH return_checks AS (

    SELECT
        return_id,
        return_status,
        requested_at,
        updated_at,
        requested_date_key,
        updated_date_key,
        requested_refund_egp,
        is_refunded_status,
        is_approved_status,

        CASE
            WHEN return_status = 'REFUNDED'
            THEN 1 ELSE 0
        END AS expected_refunded_flag,

        CASE
            WHEN return_status = 'APPROVED'
            THEN 1 ELSE 0
        END AS expected_approved_flag,

        CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                CAST(
                    SWITCHOFFSET(requested_at, '+00:00')
                    AS DATE
                ),
                112
            )
        ) AS expected_requested_date_key,

        CONVERT(
            INT,
            CONVERT(
                CHAR(8),
                CAST(
                    SWITCHOFFSET(updated_at, '+00:00')
                    AS DATE
                ),
                112
            )
        ) AS expected_updated_date_key

    FROM {{ ref('fact_returns') }}

)

SELECT *
FROM return_checks

WHERE
    -- Required timestamps
    requested_at IS NULL
    OR updated_at IS NULL

    -- Updated timestamp cannot precede request
    OR updated_at < requested_at

    -- Current project rule: positive requested refund
    OR requested_refund_egp IS NULL
    OR requested_refund_egp <= 0

    -- Status flags must be consistent
    OR is_refunded_status IS NULL
    OR is_approved_status IS NULL

    OR is_refunded_status <> expected_refunded_flag
    OR is_approved_status <> expected_approved_flag

    -- UTC calendar keys must match timestamps
    OR requested_date_key IS NULL
    OR updated_date_key IS NULL

    OR requested_date_key <> expected_requested_date_key
    OR updated_date_key <> expected_updated_date_key
