# Customer CI Integration and SCD Type 2 Validation Sign-off

## 1. Overview

- Project: Commerce Analytics Platform
- Validation date: 2026-11-06
- Environment: GitHub Actions CI
- Database: `commerce_warehouse_ci`
- Snapshot: `dbt_ci_snapshots.snap_customers`
- Gold model: `gold.dim_customers`
- Workflow: `.github/workflows/dbt-ci.yml`
- Status: **PASS — Tested CI scenarios**

This report documents the automated customer-domain integration
and SCD Type 2 validation performed in an isolated CI environment.

## 2. CI Architecture

The GitHub Actions workflow contains two jobs:

1. **Validate dbt project**
   - Runs on Windows.
   - Installs dbt dependencies.
   - Uses an isolated CI profile.
   - Parses the dbt project.

2. **dbt Integration Tests**
   - Runs on Ubuntu.
   - Starts an isolated SQL Server 2022 container.
   - Creates the CI database and Bronze tables.
   - Generates synthetic OLTP and CRM test data.
   - Loads the customer-domain Bronze tables.
   - Builds and tests selected dbt resources.
   - Applies controlled customer changes.
   - Captures and validates SCD Type 2 history.
   - Rebuilds and tests the customer dimension.

The CI environment is separate from DEV and TEST.

## 3. Test Data

The integration workflow generates reproducible synthetic
data using the project's existing `prodlike` profiles
and the configured random seed.

Customer-domain Bronze tables:

| Table                             | Expected rows |
| --------------------------------- | ------------: |
| `bronze.oltp_customers`           |        50,000 |
| `bronze.crm_customers`            |        50,000 |
| `bronze.crm_loyalty_accounts`     |        35,000 |
| `bronze.crm_loyalty_transactions` |       175,000 |
| **Total**                         |   **310,000** |

These values describe the test dataset, not production data.

## 4. Initial dbt Build

The workflow executes:

```bash
dbt build \
  --project-dir commerce_analytics_dbt \
  --target ci \
  --select "+dim_customers" \
  --indirect-selection cautious \
  --fail-fast
```

The command builds selected upstream dependencies and
the customer dimension, together with eligible tests.

The `cautious` indirect-selection mode is used to avoid
selecting relationship tests that depend on resources
outside the intentionally limited CI dataset.

**Observed result:** PASS.

## 5. Controlled SCD Type 2 Changes

Before applying changes, the workflow verifies that
the customer snapshot contains:

- 50,000 total rows.
- 50,000 current versions.

The workflow then changes `customer_segment` for exactly
8,500 selected CRM customers.

It executes:

```bash
dbt snapshot \
  --project-dir commerce_analytics_dbt \
  --target ci \
  --select snap_customers
```

The snapshot command completed successfully.

## 6. SCD Type 2 Validation Results

| Metric                                 | Expected | Actual | Status |
| -------------------------------------- | -------: | -----: | ------ |
| Total snapshot rows                    |   58,500 | 58,500 | PASS   |
| Distinct customers                     |   50,000 | 50,000 | PASS   |
| Current versions                       |   50,000 | 50,000 | PASS   |
| Historical versions                    |    8,500 |  8,500 | PASS   |
| Customers with verified segment change |    8,500 |  8,500 | PASS   |

The CI log reported:

`CUSTOMER SCD TYPE 2 VALIDATION: PASS`

These checks establish the expected row/version counts
and the tested customer-segment change behavior.

They do not, by themselves, establish full historical
attribute preservation across every column or every
possible update scenario.

## 7. Gold Dimension Rebuild

After capturing the customer changes, the workflow executes:

```bash
dbt build \
  --project-dir commerce_analytics_dbt \
  --target ci \
  --select dim_customers \
  --indirect-selection cautious \
  --fail-fast
```

Observed execution:

- 1 table model built successfully.
- 9 selected data tests passed.
- Warnings: 0.
- Errors: 0.
- Skipped: 0.

**Result: PASS (10/10 selected operations).**

## 8. GitHub Actions Evidence

- Pull Request:
  https://github.com/Aya-Abdel-Nasser/commerce-analytics-platform/pull/12

- Workflow:
  `.github/workflows/dbt-ci.yml`

- CI data loader:
  `infra/ci/load_customer_bronze.py`

- Feature commit:
  `40b4a51`

- Pull Request status: MERGED.
- GitHub Actions checks: PASSED.

The final CI results were observed in the GitHub Actions
logs associated with PR #12.

## 9. Scope and Limitations

- CI covers a selected customer-domain dataset, not all
  project sources and models.
- The test data is synthetic.
- The tested update modifies `customer_segment`.
- The CI history check does not replace the more detailed
  attribute-level preservation checks performed in TEST.
- Production deployment and operational readiness are
  outside this validation's scope.
- A SQL Server adapter safe-type-expansion warning was
  observed during snapshot execution; it did not fail
  the tested run.

The separate TEST-environment sign-off is available at:

`docs/validation/SCD2_CUSTOMERS_TEST_SIGNOFF_20261106.md`

## 10. Sign-off Decision

**PASS — Customer CI Integration and tested SCD Type 2 scenario.**

The available GitHub Actions evidence confirms successful
execution of the isolated customer-domain CI pipeline,
the expected SCD2 version counts, and the selected
customer dimension build and tests.

This sign-off does not certify production readiness.
