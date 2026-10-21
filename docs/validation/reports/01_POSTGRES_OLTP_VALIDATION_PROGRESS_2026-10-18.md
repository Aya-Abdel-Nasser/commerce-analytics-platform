# PostgreSQL OLTP → SQL Server Bronze — Validation Progress

**Project:** Commerce Analytics Platform\
**Environment:** Local initial snapshots; PostgreSQL (`commerce`) → SQL Server Express (`commerce_warehouse_dev.bronze`)\
**Evidence provided:** PostgreSQL source validation output and SQL Server target validation output, 2026-10-18.\
**Overall state:** PARTIAL — key integrity and keyed full-row equality pending.

## Verified source and target counts

| Source table | Target table | Expected | Source rows | Target rows | Count check |
|---|---|---:|---:|---:|---|
| `customers` | `bronze.oltp_customers` | 50,000 | 50,000 | 50,000 | PASS |
| `order_items` | `bronze.oltp_order_items` | 500,000 | 500,000 | 500,000 | PASS |
| `orders` | `bronze.oltp_orders` | 200,000 | 200,000 | 200,000 | PASS |
| `payments` | `bronze.oltp_payments` | 215,000 | 215,000 | 215,000 | PASS |
| `products` | `bronze.oltp_products` | 3,000 | 3,000 | 3,000 | PASS |
| **Total** | | **968,000** | **968,000** | **968,000** | **PASS** |

## Source structure and quality

- 34 source columns documented via PostgreSQL system metadata.
- Source constraints inspected (21 reported).
- All five source primary-key checks: PASS; zero NULL primary keys and zero duplicate groups.
- `commerce.payments.payment_date`: 40,000 NULL values among 215,000 rows.
- All other 33 source columns: zero observed NULLs.

## Target structure and quality

- 40 SQL Server Bronze columns profiled: 34 source columns + six ingestion timestamp columns.
- Target `payment_date`: 40,000 NULLs, matching PostgreSQL source.
- All other target columns: zero observed NULLs.
- Target key-constraint query returned no rows. This is not proof of duplicate-free target data.
- In `bronze.oltp_customers`, some source NOT NULL columns are declared nullable in the target: schema-contract difference for review; no observed NULLs.
- PostgreSQL `TIMESTAMPTZ` mapped to SQL Server `DATETIME2`; full reconciliation must normalize timezone and consider timestamp precision.

## Latest audit evidence

Successful audit runs: payments 2, order_items 4, customers 5, products 6, orders 7.\
Legacy `run_id=3` remains recorded as RUNNING with no `end_time`; documented as a historical exception, not a blocker to reporting later run 4 SUCCESS. No historical audit rows modified.

## Pending before source-specific data sign-off

1. Execute `docs/validation/01_postgresql_oltp/03_validate_TARGET_postgresql_key_integrity.sql` in SSMS; save 5-row output.
2. Implement and run read-only, deterministic, primary-keyed, source-to-target comparisons of all mapped columns; normalize `TIMESTAMPTZ` to UTC for comparison with SQL Server `DATETIME2`.
3. Retain machine-readable evidence (where available), execution date, and file/commit version. Distinguish design/runtime evidence from untested recovery paths.

**Do not mark FULL ROW RECONCILIATION PASS without an actual run.**
