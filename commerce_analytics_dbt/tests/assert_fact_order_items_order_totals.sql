
-- Cross-Fact Reconciliation
-- Grain: one row per mismatched order
-- Expected result: zero rows

WITH items_by_order AS (

    SELECT
        order_id,

        COUNT_BIG(*) AS item_count,
        SUM(quantity) AS total_quantity,

        SUM(gross_item_amount_egp)
            AS gross_amount,

        SUM(discount_amount_egp)
            AS discount_amount,

        SUM(net_item_amount_egp)
            AS net_amount

    FROM {{ ref('fact_order_items') }}

    GROUP BY order_id

),

reconciliation AS (

    SELECT
        o.order_id,

        o.order_item_count AS expected_item_count,
        i.item_count AS actual_item_count,

        o.total_quantity AS expected_quantity,
        i.total_quantity AS actual_quantity,

        o.gross_item_amount_egp AS expected_gross,
        i.gross_amount AS actual_gross,

        o.total_discount_amount_egp AS expected_discount,
        i.discount_amount AS actual_discount,

        o.net_item_amount_egp AS expected_net,
        i.net_amount AS actual_net

    FROM {{ ref('fact_orders') }} AS o

    LEFT JOIN items_by_order AS i
        ON o.order_id = i.order_id

)

SELECT *
FROM reconciliation

WHERE actual_item_count IS NULL

   OR expected_item_count IS NULL
   OR expected_quantity IS NULL
   OR expected_gross IS NULL
   OR expected_discount IS NULL
   OR expected_net IS NULL

   OR actual_item_count <> expected_item_count
   OR actual_quantity <> expected_quantity
   OR actual_gross <> expected_gross
   OR actual_discount <> expected_discount
   OR actual_net <> expected_net
