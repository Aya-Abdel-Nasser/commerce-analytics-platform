# Commerce Analytics Engineering Platform — Ingestion Validation Pack

## Scope

Two independently executable source-system validation pairs:

| Pair | Connection / SQL dialect | Filename |
|---|---|---|
| PostgreSQL OLTP — source | PostgreSQL / `commerce` schema | `01_postgresql_oltp_SOURCE.sql` |
| PostgreSQL OLTP — warehouse | Microsoft SQL Server / `commerce_warehouse_dev` | `02_postgresql_oltp_WAREHOUSE.sql` |
| MySQL CRM — source | MySQL / `commerce_crm_dev` | `03_mysql_crm_SOURCE.sql` |
| MySQL CRM — warehouse | Microsoft SQL Server / `commerce_warehouse_dev` | `04_mysql_crm_WAREHOUSE.sql` |

Run source SQL only in the source engine; run warehouse SQL only in SQL Server.

## Initial-load baselines

- PostgreSQL OLTP: orders 200,000; order_items 500,000; customers 50,000; products 3,000; payments 215,000. Total: **968,000**.
- MySQL CRM: crm_customers 50,000; crm_loyalty_accounts 35,000; crm_loyalty_transactions 175,000; crm_campaigns 120; crm_campaign_memberships 360,000; crm_support_tickets 45,000. Total: **665,120**.
- Combined across 11 tables: **1,633,120** rows.

Expected counts are a snapshot baseline, NOT an invariant if the OLTP/CRM data is later changed or incrementally loaded. Source-to-target counts should be compared from a consistent data snapshot.

## Run order and study method

1. Execute `01` in PostgreSQL. Inspect row count results, actual column metadata, source constraints, primary key checks, and column-level null profile.
2. Execute `02` in SQL Server. Inspect target counts, target metadata, column null profiles, and ETL audit results.
3. Compare `01` vs `02`: counts per table, corresponding column names/null counts, source PK vs Bronze PK implementation, and ETL status.
4. Repeat with `03` in MySQL Workbench and `04` in SQL Server for CRM.
5. Save validation outputs (CSV/screenshots) with dates. Investigate any mismatch *before* loading other sources.

## What these scripts prove — and what they do not

- **Row-count reconciliation**: source/target load volume at the initial-load baseline.
- **Schema compatibility review**: source columns vs Bronze columns. Equivalent types can have different names (e.g., MySQL datetime vs SQL Server datetime2) and ingestion may add metadata columns.
- **PK sanity**: source defined primary key(s), their null/duplicate profile; the Bronze layer may intentionally preserve raw data without PK constraints.
- **Column-level null consistency**: counts of NULLs for corresponding columns, when mappings preserve nulls.
- **Audit reconciliation**: execution_id/status/rows_processed can be compared with Informatica Monitor. A successful data load doesn't imply the entire Taskflow succeeded.
- **Not yet proved**: exact row-by-row value equality, type/precision equivalence, FK orphan integrity in target, or CDC idempotency. Those require confirmed source PKs, target grain/mapping transformations, and a deterministic keyed comparison (anti-joins or canonical row hash across engines). Do not claim 100% equality from matching counts alone.

## Important operational notes

- These scripts **do not delete or update** persistent source, Bronze, or Audit records.
- The PostgreSQL source script creates a temporary result table for PK checks; SQL Server target scripts create `#column_profile`. MySQL uses session variables and `PREPARE`.
- NULL profiling intentionally scans large tables and can take longer than count queries; if resource-limited, execute count/metadata sections first and run NULL profiling off peak.
- For MySQL, `PREPARE` runs a query generated from `information_schema.columns` and primary keys, without assuming undocumented column names.
- The source PostgreSQL schema is assumed to be `commerce` based on the orders source. If `information_schema` shows another schema for some tables, update the fully qualified schema reference before execution.

## Standard for future sources

Use one independent pair (source validation + SQL Server Bronze validation) for each source type:
- Partner Shipping CSV: file manifest, headers/schema, per-file rows, nulls, duplicates, target row counts, completeness and file lineage.
- Returns REST API: JSONL count/schema, unique return IDs, pagination completeness, nulls, API extraction manifest, target checks.
- Application Events: nine JSONL files, event IDs, timestamps, late-arriving events, duplicates and target completeness.

Store the validation reports and defects alongside the source scripts so each ingestion can be studied and rerun independently.
