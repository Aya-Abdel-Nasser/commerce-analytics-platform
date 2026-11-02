
-- Gold Fact Orders: Item Amount Integrity
-- Expected result: zero rows
-- Grain: one row per invalid order

WITH financial_checks AS (

    SELECT
        order_id,
        order_status,

        gross_item_amount_egp,
        total_discount_amount_egp,
        net_item_amount_egp,

        gross_item_amount_egp
        - total_discount_amount_egp
            AS expected_net_amount_egp

    FROM {{ ref('fact_orders') }}

)

SELECT
    order_id,
    order_status,

    gross_item_amount_egp,
    total_discount_amount_egp,
    net_item_amount_egp,
    expected_net_amount_egp

FROM financial_checks

WHERE
    gross_item_amount_egp IS NULL

    OR total_discount_amount_egp IS NULL

    OR net_item_amount_egp IS NULL

    OR expected_net_amount_egp <> net_item_amount_egp
