# Bronze Global Validation — Execution Evidence

**Project:** Commerce Analytics Platform\
**Database:** `commerce_warehouse_dev` (SQL Server Express)\
**Environment:** Local development\
**Evidence captured:** 2026-10-18 (date of results supplied; exact execution timestamp not provided)\
**Script:** `docs/validation/00_project_wide/01_ALL_FIVE_TARGETS_AND_AUDIT.sql`\
**Source of evidence:** SSMS result sets supplied by the project owner; this file does not claim an independent connection to the live databases.\
**Overall sign-off:** **PARTIAL — global counts and latest-run audit checks passed; other validation gates remain open.**

## 1. Per-target row count reconciliation — PASS (14/14)

| Source system | Target | Expected rows | Actual rows | Result |
|---|---|---:|---:|---|
| APPLICATION_EVENTS | `bronze.app_events_raw` | 1,630,000 | 1,630,000 | PASS |
| MOCK_RETURNS_API | `bronze.returns_raw` | 22,093 | 22,093 | PASS |
| MYSQL_CRM | `bronze.crm_campaign_memberships` | 360,000 | 360,000 | PASS |
| MYSQL_CRM | `bronze.crm_campaigns` | 120 | 120 | PASS |
| MYSQL_CRM | `bronze.crm_customers` | 50,000 | 50,000 | PASS |
| MYSQL_CRM | `bronze.crm_loyalty_accounts` | 35,000 | 35,000 | PASS |
| MYSQL_CRM | `bronze.crm_loyalty_transactions` | 175,000 | 175,000 | PASS |
| MYSQL_CRM | `bronze.crm_support_tickets` | 45,000 | 45,000 | PASS |
| PARTNER_SHIPPING_CSV | `bronze.partner_shipments` | 120,000 | 120,000 | PASS |
| POSTGRES_OLTP | `bronze.oltp_customers` | 50,000 | 50,000 | PASS |
| POSTGRES_OLTP | `bronze.oltp_order_items` | 500,000 | 500,000 | PASS |
| POSTGRES_OLTP | `bronze.oltp_orders` | 200,000 | 200,000 | PASS |
| POSTGRES_OLTP | `bronze.oltp_payments` | 215,000 | 215,000 | PASS |
| POSTGRES_OLTP | `bronze.oltp_products` | 3,000 | 3,000 | PASS |

## 2. Source group aggregate counts — PASS (5/5)

| Source system | Expected rows | Actual rows | Result |
|---|---:|---:|---|
| APPLICATION_EVENTS | 1,630,000 | 1,630,000 | PASS |
| MOCK_RETURNS_API | 22,093 | 22,093 | PASS |
| MYSQL_CRM | 665,120 | 665,120 | PASS |
| PARTNER_SHIPPING_CSV | 120,000 | 120,000 | PASS |
| POSTGRES_OLTP | 968,000 | 968,000 | PASS |
| **Grand total** | **3,405,213** | **3,405,213** | **PASS** |

## 3. Latest audit per target — PASS (14/14)

Each of the 14 current latest audit records has `status = SUCCESS` and `rows_processed = expected_rows` according to the supplied output. Every latest run has a populated `start_time` and `end_time` in the supplied results.

| Target | Latest audit run_id | Status | Rows processed | Audit check |
|---|---:|---|---:|---|
| `bronze.app_events_raw` | 17 | SUCCESS | 1,630,000 | PASS |
| `bronze.returns_raw` | 16 | SUCCESS | 22,093 | PASS |
| `bronze.crm_campaign_memberships` | 13 | SUCCESS | 360,000 | PASS |
| `bronze.crm_campaigns` | 12 | SUCCESS | 120 | PASS |
| `bronze.crm_customers` | 19 | SUCCESS | 50,000 | PASS |
| `bronze.crm_loyalty_accounts` | 10 | SUCCESS | 35,000 | PASS |
| `bronze.crm_loyalty_transactions` | 11 | SUCCESS | 175,000 | PASS |
| `bronze.crm_support_tickets` | 14 | SUCCESS | 45,000 | PASS |
| `bronze.partner_shipments` | 15 | SUCCESS | 120,000 | PASS |
| `bronze.oltp_customers` | 5 | SUCCESS | 50,000 | PASS |
| `bronze.oltp_order_items` | 4 | SUCCESS | 500,000 | PASS |
| `bronze.oltp_orders` | 7 | SUCCESS | 200,000 | PASS |
| `bronze.oltp_payments` | 2 | SUCCESS | 215,000 | PASS |
| `bronze.oltp_products` | 6 | SUCCESS | 3,000 | PASS |

**Note:** Empty `error_message` cells for successful PostgreSQL runs are not evidence of a failed load. The current SQL `audit_check` verifies status and rows processed, not every lifecycle invariant.

## 4. Historical audit exceptions — documented, deferred

| run_id | Target | Recorded status | Recorded end_time | Disposition |
|---:|---|---|---|---|
| 3 | `bronze.oltp_order_items` | RUNNING | NULL | Historical incomplete audit entry; later run 4 succeeded. |
| 8 | `bronze.crm_customers` | RUNNING | NULL | Historical incomplete audit entry; later run 19 succeeded. |
| 9 | `bronze.crm_customers` | RUNNING | NULL | Historical incomplete audit entry; later run 19 succeeded. |

Do **not** retroactively mark these attempts SUCCESS or FAILED without reconciling their original execution outcomes. These entries do not invalidate the *latest-run* checks, but represent audit-history exceptions and should remain visible at handover. The root causes/fix details are documented separately in the Informatica taskflow documentation.

## 5. Validation scope / outstanding work

- [x] All 14 target table row counts match the **expected baseline in the script**.
- [x] All five source group aggregate row counts match the baseline.
- [x] Grand total is 3,405,213.
- [x] Latest audit row for each of 14 targets has SUCCESS and expected rows processed.
- [ ] Validate key presence, uniqueness/duplicate profiles and agreed nullability contracts against actual column definitions.
- [ ] Validate source and target data values beyond counts (full keyed reconciliation for the 11 PostgreSQL/MySQL relational tables is not yet implemented in the documented package).
- [ ] Preserve current dated shipping/returns/events source-to-target reconciliation results, distinguishing historical reports from fresh reruns.
- [ ] Review other data-quality checks (JSON validity, types, date/financial fields, rejected rows) using the existing per-source scripts.
- [ ] Full integrated CRM taskflow failure-path runtime test after `FAILEDd` to `FAILED` correction is pending. The isolated Audit Finish failure test previously passed.
- [ ] Retry/idempotency behavior not established: customer reload was performed after a manual TRUNCATE, which does not prove safe reruns.

### Interpretation

This is a **PASS for the global target count and latest-audit checks only**. It is **not a blanket sign-off for data correctness, complete historical audit reconciliation or production readiness**. Do not infer physical PostgreSQL/MySQL source counts were freshly queried by the global script: its baseline is defined in SQL literals.
