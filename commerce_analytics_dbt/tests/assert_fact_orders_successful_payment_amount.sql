
-- Gold Fact Orders: Successful Payment Amount Integrity
-- Expected result: zero rows
-- Grain: one row per invalid order

WITH payment_amount_checks AS (

    SELECT
        order_id,
        order_status,
        successful_payment_count,
        successful_payment_amount_egp

    FROM {{ ref('fact_orders') }}

)

SELECT
    order_id,
    order_status,
    successful_payment_count,
    successful_payment_amount_egp

FROM payment_amount_checks

WHERE
    successful_payment_amount_egp IS NULL

    OR successful_payment_amount_egp < 0

    OR (
        successful_payment_count = 0
        AND successful_payment_amount_egp <> 0
    )

    OR (
        successful_payment_count > 0
        AND successful_payment_amount_egp <= 0
    )
