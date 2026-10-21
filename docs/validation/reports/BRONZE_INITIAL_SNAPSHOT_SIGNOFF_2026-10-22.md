# Bronze Initial Snapshot — Final Validation Sign-off

**Project:** Commerce Analytics Platform
**Date:** 2026-10-22
**Target:** SQL Server — `commerce_warehouse_dev`
**Schema:** `bronze`
**Scope:** Initial ingestion snapshot and source-to-target validation

## 1. Executive Summary

The initial Bronze ingestion snapshot has successfully passed the documented validation and reconciliation checks.

- **Source groups:** 5
- **Bronze tables:** 14
- **Total validated target rows:** 3,405,213
- **Global row-count validation:** PASS
- **Application Events clean reload:** SUCCESS
- **Latest Application Events audit:** SUCCESS (Run ID 20)

## 2. Source-to-Target Validation Results

| Source Group | Records | Result |
|---|---:|---|
| PostgreSQL OLTP | 968,000 | PASS |
| MySQL CRM | 665,120 | PASS |
| Partner Shipping CSV | 120,000 | PASS |
| Returns API Snapshot | 22,093 | PASS |
| Application Events JSONL | 1,630,000 | PASS |
| **Total** | **3,405,213** | **PASS** |

## 3. Supporting Evidence

- PostgreSQL: `01_POSTGRES_OLTP_FULL_RECONCILIATION_POST_REPAIR.json`
- MySQL: `02_MYSQL_CRM_FULL_RECONCILIATION.json`
- MySQL sign-off: `02_MYSQL_CRM_VALIDATION_SIGNOFF_2026-10-18.md`
- Shipping: `03_SHIPPING_RECONCILIATION_FINAL_20261022.json`
- Returns: `04_RETURNS_RECONCILIATION_FINAL_20261022.json`
- Application Events: `05_EVENTS_RECONCILIATION_POST_RELOAD_20261022.json`
- Global validation script: `01_ALL_FIVE_TARGETS_AND_AUDIT.sql`

## 4. Application Events Recovery

A direct Mapping run had appended a second copy of the dataset, increasing the target row count to 3,260,000.

The Mapping was configured for a clean full reload using `Truncate target`, and the Application Events Taskflow was executed successfully.

Post-reload validation confirmed:

- Target row count: 1,630,000
- Missing filenames: 0
- Invalid line numbers: 0
- Distinct source files: 9
- Per-file line-number counts and ranges: PASS
- Exact Unicode JSON text reconciliation: PASS
- Missing / unexpected raw-text occurrences: 0 / 0
- Taskflow audit: SUCCESS

## 5. Known Limitations and Deferred Work

- Application Events filename and line-number completeness, ranges, and uniqueness passed; exact per-row JSON-to-original-file-line association was not independently verified.
- Historical audit records 3, 8, and 9 remain `RUNNING` and require separate investigation or documentation.
- MySQL's independently documented initial-snapshot sign-off does not certify future retries or failure-path behavior.
- Incremental loading, CDC, and general reload idempotency are outside this sign-off.
- Informatica Cloud assets are not fully represented as native deployable exports in the GitHub repository.
- This sign-off does not certify production readiness.

## 6. Final Decision

**INITIAL BRONZE SNAPSHOT VALIDATION: PASS**

The validated Bronze snapshot is accepted as the starting point for the dbt transformation phase, subject to the limitations documented above.

**Next phase:** Validation knowledge review, followed by dbt project initialization and transformation modeling.