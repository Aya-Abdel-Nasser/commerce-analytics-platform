# MySQL CRM — Bronze Initial Snapshot Validation Sign-off

**Project:** Commerce Analytics Platform\
**Date of supplied execution evidence:** 2026-10-18\
**Source:** MySQL `commerce_crm_dev` (six tables)\
**Target:** SQL Server `commerce_warehouse_dev`, schema `bronze`\
**Scope:** Initial snapshot only; no CDC, future retries or failure-path certification.

## Full keyed source-to-target comparison

User supplied the following terminal output after executing:

`python docs/validation/02_mysql_crm/05_reconcile_SOURCE_TARGET_mysql_crm.py`

| Source table | Target table | Source rows | Target rows | Missing | Unexpected | Value mismatch rows | Outcome |
|---|---|---:|---:|---:|---:|---:|---|
| `crm_customers` | `bronze.crm_customers` | 50,000 | 50,000 | 0 | 0 | 0 | PASS |
| `loyalty_accounts` | `bronze.crm_loyalty_accounts` | 35,000 | 35,000 | 0 | 0 | 0 | PASS |
| `loyalty_transactions` | `bronze.crm_loyalty_transactions` | 175,000 | 175,000 | 0 | 0 | 0 | PASS |
| `campaigns` | `bronze.crm_campaigns` | 120 | 120 | 0 | 0 | 0 | PASS |
| `campaign_memberships` | `bronze.crm_campaign_memberships` | 360,000 | 360,000 | 0 | 0 | 0 | PASS |
| `support_tickets` | `bronze.crm_support_tickets` | 45,000 | 45,000 | 0 | 0 | 0 | PASS |
| **TOTAL** | **Six bronze tables** | **665,120** | **665,120** | **0** | **0** | **0** | **PASS** |

Total compared mapped columns: **41** (respectively 7, 6, 6, 8, 6, 8).

**Persistent machine-readable evidence:** `docs/validation/reports/02_MYSQL_CRM_FULL_RECONCILIATION.json` (generated on the user's machine; review file contents before commit).\
**Implementation:** `docs/validation/02_mysql_crm/05_reconcile_SOURCE_TARGET_mysql_crm.py`.

## Corroborating validation evidence

| Validation | Result | Basis |
|---|---|---|
| Six target baseline row counts | PASS | `01_ALL_FIVE_TARGETS_AND_AUDIT.sql`, six per-table matches |
| Latest audit per target | PASS | Six latest corresponding runs `SUCCESS` with matching row counts, including `crm_customers` run 19 |
| Target PK-null / duplicate checks | PASS | `04_validate_TARGET_key_integrity.sql`, 6/6 PASS, zero null key rows and duplicates |
| Source/target NULL-count comparison | PASS for three populated-null columns | Campaign memberships `engaged_at`: 43,264; loyalty transactions `reference_order_number`: 117,036; support tickets `resolved_at`: 8,911, matched on both engines |
| Schema and PK metadata inventory | Reviewed | MySQL source metadata and SQL Server target metadata retrieved; mapping rules underpin cross-engine reconciliation |

## Exceptions and boundaries

- Historical audit rows `run_id` 3, 8, 9 remain `RUNNING` with no `end_time`; retain as separately documented historical audit exceptions. Do not modify them automatically or interpret a newer successful run as proof of their original outcome.
- The separate end-to-end failure path after the latest CRM audit configuration fix has not been run; its status is **NOT TESTED**.
- Row comparison covers the script's enumerated **mapped columns** for the current consistent initial snapshot; it does not attest unmapped ingestion metadata, CDC behavior, disaster recovery, or future reload idempotency.
- User-supplied console output supports this sign-off; this document does not imply the assistant connected to the live databases or independently inspected the generated JSON report.

**Decision: MySQL CRM INITIAL SNAPSHOT DATA RECONCILIATION = PASS.**
