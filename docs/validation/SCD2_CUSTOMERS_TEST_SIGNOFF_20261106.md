# SCD Type 2 — Customers TEST Validation Sign-off

## 1. Scope

- Project: Commerce Analytics Platform
- Environment: TEST
- Snapshot: `snap_customers`
- Database: `commerce_warehouse_test`
- Snapshot relation: `dbt_test_snapshots.snap_customers`
- Validation date: 2026-11-06
- Status: PASS for the tested change scenario

This sign-off covers the tested customer update batch.
It does not certify all possible SCD Type 2 scenarios.

## 2. Test Scenario

The test validates whether dbt correctly preserves historical
customer attribute values after a controlled source update.

Compared attributes:

- `customer_segment`
- `preferred_channel`
- `marketing_opt_in`

The pre-batch values were preserved in:

`commerce_crm_test.crm_customers_backup_before_batch_20261105`

## 3. Snapshot Results

| Metric                       | Result |
| ---------------------------- | -----: |
| Source customers             | 50,000 |
| Current snapshot versions    | 50,000 |
| Historical snapshot versions |  8,500 |
| Total snapshot versions      | 58,500 |
| Customers with one version   | 41,500 |
| Customers with two versions  |  8,500 |

## 4. Historical Value Preservation

The historical versions were compared against the MySQL
pre-batch backup using `customer_code`.

| Validation                   | Result |
| ---------------------------- | -----: |
| Backup rows                  | 50,000 |
| Historical versions compared |  8,500 |
| Duplicate backup keys        |      0 |
| Duplicate historical keys    |      0 |
| Missing customers            |      0 |
| Customer segment mismatches  |      0 |
| Preferred channel mismatches |      0 |
| Marketing opt-in mismatches  |      0 |

Result: PASS

## 5. Temporal Integrity

| Validation                | Result |
| ------------------------- | -----: |
| Historical versions       |  8,500 |
| Invalid date ranges       |      0 |
| Broken version boundaries |      0 |

Result: PASS

## 6. Current Version Reconciliation

All 50,000 current snapshot versions were matched to the
Silver SCD source for the tested customer attributes.

- Missing current versions: 0
- Segment mismatches: 0
- Channel mismatches: 0
- Marketing opt-in mismatches: 0

Result: PASS

## 7. dbt Data Tests

Command:

`dbt test --select snap_customers --target test`

Execution date: 2026-11-06

Results:

- PASS: 5
- WARN: 0
- ERROR: 0
- SKIP: 0

Tests passed:

1. `assert_snap_customers_current_coverage`
2. `assert_snap_customers_historical_intervals`
3. `assert_snap_customers_one_current_version`
4. `assert_snap_customers_version_key_integrity`
5. `relationships_dim_customers_customer_version_key__dbt_scd_id__ref_snap_customers_`

## 8. Evidence

Historical preservation report:

`docs/validation/reports/SCD2_HISTORICAL_VALUE_PRESERVATION_20261106.json`

Evidence commit:

`3ddbd06`

The MySQL pre-batch TSV export is retained locally
and is not committed to Git.

## 9. Limitations

- Validation covers the TEST environment only.
- Validation covers the controlled customer update scenario.
- Historical value comparison covers three customer attributes.
- The separate `snap_customers_scd_lab` snapshot is out of scope.
- Additional change scenarios require separate validation.
- The manual reconciliation was executed in PowerShell;
  its result is documented, but the comparison script
  has not yet been committed as a reusable automated test.

## 10. Sign-off Decision

**PASS — Tested SCD Type 2 customer update scenario**

The available evidence supports successful historical value
preservation, current version reconciliation, temporal integrity,
and the five selected dbt Data Tests.

This sign-off does not imply production readiness.
