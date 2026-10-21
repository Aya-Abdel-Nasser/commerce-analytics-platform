-- PROJECT 2 | PostgreSQL OLTP | SOURCE VALIDATION
-- Run in PostgreSQL (for example, pgAdmin Query Tool), NOT SQL Server.
-- Connection: PostgreSQL OLTP database | Schema assumed: commerce.
-- Purpose: verify baseline row counts, source metadata, nulls and primary-key integrity.
-- Read-only for permanent source tables. Temporary validation table is session-scoped.
-- IMPORTANT: Use the source metadata section to confirm that all source tables are in commerce.

-- 01 | Counts vs known initial-load baseline
WITH row_counts AS (
    SELECT 'orders'::text AS table_name, 200000::bigint AS expected_rows, COUNT(*)::bigint AS actual_rows FROM commerce.orders UNION ALL
    SELECT 'order_items'::text AS table_name, 500000::bigint AS expected_rows, COUNT(*)::bigint AS actual_rows FROM commerce.order_items UNION ALL
    SELECT 'customers'::text AS table_name, 50000::bigint AS expected_rows, COUNT(*)::bigint AS actual_rows FROM commerce.customers UNION ALL
    SELECT 'products'::text AS table_name, 3000::bigint AS expected_rows, COUNT(*)::bigint AS actual_rows FROM commerce.products UNION ALL
    SELECT 'payments'::text AS table_name, 215000::bigint AS expected_rows, COUNT(*)::bigint AS actual_rows FROM commerce.payments
)
SELECT table_name, expected_rows, actual_rows,
       (actual_rows - expected_rows) AS difference,
       CASE WHEN actual_rows = expected_rows THEN 'PASS' ELSE 'REVIEW' END AS count_check
FROM row_counts
UNION ALL
SELECT 'ALL_TABLES', SUM(expected_rows), SUM(actual_rows),
       SUM(actual_rows - expected_rows),
       CASE WHEN SUM(actual_rows - expected_rows) = 0 THEN 'PASS' ELSE 'REVIEW' END
FROM row_counts;

-- 02 | Source column metadata: compare names and nullability with SQL Server script
SELECT table_name, ordinal_position, column_name, data_type,
       is_nullable, character_maximum_length, numeric_precision, numeric_scale
FROM information_schema.columns
WHERE table_schema = 'commerce' AND table_name IN ('orders', 'order_items', 'customers', 'products', 'payments')
ORDER BY table_name, ordinal_position;

-- 03 | Source PK/FK and other constraints (understand source semantics)
SELECT t.relname AS table_name,
       c.conname AS constraint_name,
       CASE c.contype
         WHEN 'p' THEN 'PRIMARY KEY'
         WHEN 'f' THEN 'FOREIGN KEY'
         WHEN 'u' THEN 'UNIQUE'
         WHEN 'c' THEN 'CHECK'
         ELSE c.contype::text
       END AS constraint_type,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace ns ON ns.oid = t.relnamespace
WHERE ns.nspname = 'commerce' AND t.relname IN ('orders', 'order_items', 'customers', 'products', 'payments')
ORDER BY t.relname, constraint_type, constraint_name;

-- 04 | Source PK integrity. Discovers PK columns (including composite keys) dynamically.
-- The checks are executed using only table/column names read from PostgreSQL's catalog.
DROP TABLE IF EXISTS pg_temp.pg_pk_validation;
CREATE TEMP TABLE pg_pk_validation (
    table_name text, key_columns text, null_key_rows bigint,
    duplicate_key_groups bigint, duplicate_extra_rows bigint
);
DO $validate_pk$
DECLARE
    r record;
    null_rows bigint;
    dup_groups bigint;
    dup_extra bigint;
BEGIN
    FOR r IN
        SELECT k.table_name,
               string_agg(format('%I', k.column_name), ', ' ORDER BY k.ordinal_position) AS key_columns,
               string_agg(format('%I IS NULL', k.column_name), ' OR ' ORDER BY k.ordinal_position) AS null_condition
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage k
          ON k.constraint_catalog = tc.constraint_catalog
         AND k.constraint_schema = tc.constraint_schema
         AND k.constraint_name = tc.constraint_name
         AND k.table_schema = tc.table_schema
         AND k.table_name = tc.table_name
        WHERE tc.table_schema = 'commerce'
          AND tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_name IN ('orders', 'order_items', 'customers', 'products', 'payments')
        GROUP BY k.table_name
    LOOP
        EXECUTE format('SELECT count(*) FROM commerce.%I WHERE %s', r.table_name, r.null_condition)
        INTO null_rows;
        EXECUTE format(
            'SELECT count(*), coalesce(sum(n-1),0) FROM '
            || '(SELECT count(*) AS n FROM commerce.%I GROUP BY %s HAVING count(*) > 1) d',
            r.table_name, r.key_columns
        ) INTO dup_groups, dup_extra;
        INSERT INTO pg_pk_validation VALUES (r.table_name, r.key_columns, null_rows, dup_groups, dup_extra);
    END LOOP;
END
$validate_pk$;
SELECT *, CASE WHEN null_key_rows = 0 AND duplicate_key_groups = 0 THEN 'PASS' ELSE 'FAIL' END AS pk_check
FROM pg_pk_validation ORDER BY table_name;
-- If fewer than 5 PK results appear, inspect the source constraint report above.

-- 05 | Per-column NULL profile. Can be slower: scans all source rows and columns.
-- Compare table_name + column_name + null_count to the warehouse profile.
SELECT 'orders'::text AS table_name, kv.key AS column_name, COUNT(*)::bigint AS row_count,
       COUNT(*) FILTER (WHERE kv.value = 'null'::jsonb)::bigint AS null_count
FROM commerce.orders AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS kv(key, value)
GROUP BY kv.key UNION ALL
SELECT 'order_items'::text AS table_name, kv.key AS column_name, COUNT(*)::bigint AS row_count,
       COUNT(*) FILTER (WHERE kv.value = 'null'::jsonb)::bigint AS null_count
FROM commerce.order_items AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS kv(key, value)
GROUP BY kv.key UNION ALL
SELECT 'customers'::text AS table_name, kv.key AS column_name, COUNT(*)::bigint AS row_count,
       COUNT(*) FILTER (WHERE kv.value = 'null'::jsonb)::bigint AS null_count
FROM commerce.customers AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS kv(key, value)
GROUP BY kv.key UNION ALL
SELECT 'products'::text AS table_name, kv.key AS column_name, COUNT(*)::bigint AS row_count,
       COUNT(*) FILTER (WHERE kv.value = 'null'::jsonb)::bigint AS null_count
FROM commerce.products AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS kv(key, value)
GROUP BY kv.key UNION ALL
SELECT 'payments'::text AS table_name, kv.key AS column_name, COUNT(*)::bigint AS row_count,
       COUNT(*) FILTER (WHERE kv.value = 'null'::jsonb)::bigint AS null_count
FROM commerce.payments AS t
CROSS JOIN LATERAL jsonb_each(to_jsonb(t)) AS kv(key, value)
GROUP BY kv.key
ORDER BY table_name, column_name;
