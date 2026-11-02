
-- Loyalty Order Reference Business Integrity
-- Expected result: zero rows
-- Each returned row is an invalid transaction.

with loyalty_transactions as (

    select
        loyalty_transaction_id,
        loyalty_account_id,
        customer_id,
        reference_order_number,
        order_id

    from {{ ref('fact_loyalty_transactions') }}

),

orders as (

    select
        order_id,
        order_number,
        customer_id

    from {{ ref('fact_orders') }}

)

select
    l.loyalty_transaction_id,
    l.loyalty_account_id,
    l.customer_id as loyalty_customer_id,
    l.reference_order_number,
    l.order_id,
    o.order_number,
    o.customer_id as order_customer_id

from loyalty_transactions as l

left join orders as o
    on l.order_id = o.order_id

where

    -- Reference provided but order not resolved
    (
        l.reference_order_number is not null
        and l.order_id is null
    )

    -- No reference but order incorrectly assigned
    or (
        l.reference_order_number is null
        and l.order_id is not null
    )

    -- Resolved order must exist
    or (
        l.order_id is not null
        and o.order_id is null
    )

    -- Order number must match reference
    or (
        l.order_id is not null
        and (
            o.order_number is null
            or o.order_number <> l.reference_order_number
        )
    )

    -- Order and loyalty account must belong
    -- to the same stable customer
    or (
        l.order_id is not null
        and (
            l.customer_id is null
            or o.customer_id is null
            or l.customer_id <> o.customer_id
        )
    )
