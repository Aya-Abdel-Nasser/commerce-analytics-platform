# TEST Data Validation — Final Sign-off

## 1. Overview

- Project: Commerce Analytics Platform
- Environment: TEST
- Warehouse: `commerce_warehouse_test`
- Validation date: 2026-11-06
- Status: **PASS — Data Validation Scope**

This report records the evidence supporting closure of
the TEST data validation phase.

It does not represent production deployment approval.

## 2. dbt Resource Verification

The dbt project contains:

- 35 models
- 2 snapshots
- 502 data tests
- 15 sources

A SQL Server metadata inspection confirmed that all 35
named models exist as tables or views in the TEST warehouse.

Snapshot verification:

- `dbt_test_snapshots.snap_customers`
- Observed rows: 58,500
- Status: Consistent with the approved customer SCD2 scenario

## 3. Full Data Quality Execution

Command:

```bash
dbt test --target test --no-partial-parse
```

Execution evidence:

| Metric      | Result |
| ----------- | -----: |
| Total tests |    502 |
| Passed      |    502 |
| Warnings    |      0 |
| Failures    |      0 |
| Errors      |      0 |
| Skipped     |      0 |

- Result: **PASS**
- Duration: approximately 7 minutes 4 seconds
- Artifact generated at: `2026-11-06T18:08:44.872873Z`
- Artifact: `target/run_results.json`

All selected and enabled data tests completed successfully.

## 4. Customer SCD Type 2 Validation

The customer SCD2 validation was completed separately
using a controlled change scenario.

Observed results:

| Metric                       | Result |
| ---------------------------- | -----: |
| Source customers             | 50,000 |
| Current snapshot versions    | 50,000 |
| Historical snapshot versions |  8,500 |
| Total snapshot versions      | 58,500 |

Historical preservation, temporal integrity,
and current-version reconciliation passed for
the documented TEST scenario.

Evidence:

`docs/validation/SCD2_CUSTOMERS_TEST_SIGNOFF_20261106.md`

## 5. Bronze Validation Evidence

Previous source-to-target validation reports are retained
under `docs/validation/reports/`.

They cover:

- PostgreSQL OLTP
- MySQL CRM
- Partner Shipping CSV
- Returns API
- Application Events

The earlier Bronze validation reports are referenced
as existing evidence. This sign-off does not claim that
all Bronze ingestion pipelines were rerun on TEST today.

## 6. CI Evidence

The isolated customer-domain CI workflow passed.

Evidence:

- PR #12 — Customer integration and SCD2 tests
- PR #13 — Customer CI validation documentation

CI operates independently from the local TEST warehouse.

## 7. Known Limitations

- The separate SCD lab snapshot remains outside the
  customer SCD2 sign-off scope.
- An existing lab table uses the schema
  `dbt_dev_scd_lab_snapshots` inside the TEST database,
  while the current dbt configuration resolves to
  `dbt_test_scd_lab_snapshots`.
- The lab schema discrepancy requires review before
  reusing that experimental snapshot.
- Full operational recovery, scheduling, monitoring,
  and production deployment have not been certified.
- Passing data tests does not independently prove that
  every pipeline can be reconstructed from scratch.

## 8. Final Decision

**PASS — TEST Data Validation**

The available evidence supports successful dbt data
quality validation, customer SCD2 validation, and
the documented source-to-target checks.

The TEST data validation phase is accepted within
the stated scope.

Operational and production readiness remain separate
workstreams.
