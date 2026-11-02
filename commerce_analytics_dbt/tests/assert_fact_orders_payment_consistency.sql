
-- Gold Fact Orders: Payment Consistency
-- Expected result: zero rows
-- Grain: one row per invalid order

WITH payment_checks AS (

    SELECT
        order_id,

        payment_attempt_count,
        successful_payment_count,
        failed_payment_count,
        pending_payment_count,

        has_successful_payment,
        has_payment_retry,

        successful_payment_count
        + failed_payment_count
        + pending_payment_count
            AS calculated_attempt_count,

        CASE
            WHEN successful_payment_count > 0
            THEN 1 ELSE 0
        END AS expected_success_flag,

        CASE
            WHEN payment_attempt_count > 1
            THEN 1 ELSE 0
        END AS expected_retry_flag

    FROM {{ ref('fact_orders') }}

)

SELECT *
FROM payment_checks

WHERE
    payment_attempt_count IS NULL
    OR successful_payment_count IS NULL
    OR failed_payment_count IS NULL
    OR pending_payment_count IS NULL

    OR payment_attempt_count < 0
    OR successful_payment_count < 0
    OR failed_payment_count < 0
    OR pending_payment_count < 0

    OR payment_attempt_count <> calculated_attempt_count

    OR has_successful_payment IS NULL
    OR has_payment_retry IS NULL

    OR has_successful_payment <> expected_success_flag
    OR has_payment_retry <> expected_retry_flag
