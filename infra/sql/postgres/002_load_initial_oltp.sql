-- Commerce Analytics Platform | PostgreSQL OLTP | DEV ONLY
-- Loads the prodlike initial synthetic batch in a single transaction.
-- IMPORTANT: Replaces the contents of only these five commerce tables.
-- Run through psql inside the postgres_oltp container.
\set ON_ERROR_STOP on

BEGIN;

-- Referencing tables and referenced tables are truncated together.
-- The earlier app.preflight_customer table is NOT touched.
TRUNCATE TABLE
    commerce.payments,
    commerce.order_items,
    commerce.orders,
    commerce.products,
    commerce.customers
RESTART IDENTITY;

-- Explicit column lists prevent accidental mismatches if table column order changes.
\copy commerce.customers (customer_id, customer_code, full_name, email, city, created_at, updated_at) FROM '/tmp/commerce_oltp_initial/customers.csv' WITH (FORMAT csv, HEADER true)
\copy commerce.products (product_id, sku, product_name, category, list_price_egp, created_at, updated_at) FROM '/tmp/commerce_oltp_initial/products.csv' WITH (FORMAT csv, HEADER true)
\copy commerce.orders (order_id, order_number, customer_id, order_status, sales_channel, order_date, updated_at) FROM '/tmp/commerce_oltp_initial/orders.csv' WITH (FORMAT csv, HEADER true)
\copy commerce.order_items (order_item_id, order_id, product_id, quantity, unit_price_egp, discount_amount_egp) FROM '/tmp/commerce_oltp_initial/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy commerce.payments (payment_id, transaction_id, order_id, payment_method, payment_status, amount_egp, payment_date) FROM '/tmp/commerce_oltp_initial/payments.csv' WITH (FORMAT csv, HEADER true)

-- Verify the full batch before committing any data.
DO $$
BEGIN
    IF (SELECT count(*) FROM commerce.customers) <> 50000
       OR (SELECT count(*) FROM commerce.products) <> 3000
       OR (SELECT count(*) FROM commerce.orders) <> 200000
       OR (SELECT count(*) FROM commerce.order_items) <> 500000
       OR (SELECT count(*) FROM commerce.payments) <> 215000 THEN
        RAISE EXCEPTION 'Initial-load row counts do not match prodlike manifest; rolling back';
    END IF;
END
$$;

-- The CSV supplies explicit identity IDs; align future generated IDs.
SELECT setval(pg_get_serial_sequence('commerce.customers', 'customer_id'), (SELECT max(customer_id) FROM commerce.customers), true);
SELECT setval(pg_get_serial_sequence('commerce.products', 'product_id'), (SELECT max(product_id) FROM commerce.products), true);
SELECT setval(pg_get_serial_sequence('commerce.orders', 'order_id'), (SELECT max(order_id) FROM commerce.orders), true);
SELECT setval(pg_get_serial_sequence('commerce.order_items', 'order_item_id'), (SELECT max(order_item_id) FROM commerce.order_items), true);
SELECT setval(pg_get_serial_sequence('commerce.payments', 'payment_id'), (SELECT max(payment_id) FROM commerce.payments), true);

COMMIT;

-- Visible post-load counts; only successful if the transaction committed.
SELECT 'customers' AS table_name, count(*) AS row_count FROM commerce.customers
UNION ALL SELECT 'products', count(*) FROM commerce.products
UNION ALL SELECT 'orders', count(*) FROM commerce.orders
UNION ALL SELECT 'order_items', count(*) FROM commerce.order_items
UNION ALL SELECT 'payments', count(*) FROM commerce.payments;
