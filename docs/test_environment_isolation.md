# TEST Environment Isolation — Setup & Validation

## 1. Purpose

The TEST environment provides an isolated SQL Server database for validating dbt transformations before production deployment.

The project uses the same dbt models across environments, with environment-specific connection settings.

| Environment | Database                  | Purpose                            |
| ----------- | ------------------------- | ---------------------------------- |
| DEV         | `commerce_warehouse_dev`  | Development and debugging          |
| TEST        | `commerce_warehouse_test` | Integration and regression testing |
| PROD        | Not configured yet        | Future production deployment       |

## 2. Isolation Architecture

**Isolation strategy:** Separate SQL Server databases on the same SQL Server Express instance.

- DEV and TEST use independent data and log files.
- dbt selects the database through `profiles.yml` targets.
- Silver and Gold use the existing `generate_schema_name` macro.
- Source definitions must resolve to the intended target database.
- TEST must not contain unintended references to DEV.

The SCD Lab source was updated to use:

```yaml
database: "{{ target.database }}"
```

This replaces the previous hardcoded DEV database reference.

## 3. Initial TEST Setup

TEST was provisioned from a `COPY_ONLY` full backup of DEV.

Setup and recovery operations:

1. Create a DEV backup with `CHECKSUM`.
2. Validate the backup with `RESTORE VERIFYONLY WITH CHECKSUM`.
3. Inspect logical files using `RESTORE FILELISTONLY`.
4. Restore to `commerce_warehouse_test` using `WITH MOVE` and separate physical file names.
5. Verify both databases are `ONLINE` and use different physical files.
6. Configure a local dbt `test` target with `database: commerce_warehouse_test` and `schema: dbt_test`.
7. Verify the connection with `dbt debug --target test`.

**Safety:** Do not use `WITH REPLACE` or reuse DEV physical file paths. Keep connection credentials outside version control.

This is an initial provisioning procedure, not a requirement for every routine TEST run.

## 4. Post-Restore Preparation

Restored SQL Server Views initially retained references to DEV.

Resolution:

- Compiled all 21 Staging and Intermediate models with `--target test`.
- Verified their current compiled SQL contained no explicit DEV database references.
- Rebuilt the 21 Silver Views in TEST.
- Verified zero DEV references across the current Silver View definitions.
- Removed one obsolete `dbt_dev_silver.stg_oltp_customers` View in TEST after dependency inspection.

### Business Snapshot

The restored Business Snapshot initially existed under `dbt_dev_snapshots`.

It was transferred inside TEST to:

`commerce_warehouse_test.dbt_test_snapshots.snap_customers`

Validation after transfer:

- Total rows: **50,000**
- Active versions: **50,000**
- Historical versions: **0**
- Distinct SCD IDs: **50,000**
- Clustered columnstore index preserved
- dbt `ref('snap_customers')` access verified

### Experimental SCD Lab

The experimental `snap_customers_scd_lab` remains preserved in `dbt_dev_scd_lab_snapshots` inside TEST.

It contains two versions: one active and one historical.

It has not been migrated to the TEST snapshot destination or included in a new snapshot execution. This requires a separate testing decision.

## 5. Validation Evidence

| Check                                       | Verified Result |
| ------------------------------------------- | --------------- |
| TEST dbt connection                         | PASS            |
| Six representative compiled relations       | TEST database   |
| Silver rebuild                              | 21/21 PASS      |
| Silver runtime sample                       | 4/4 PASS        |
| Gold rebuild                                | 14/14 PASS      |
| Gold runtime sample                         | 3/3 PASS        |
| Gold regression                             | 264/264 PASS    |
| Full dbt regression                         | 502/502 PASS    |
| SQL modules referencing DEV                 | 0               |
| Registered SQL dependencies referencing DEV | 0               |
| Synonyms referencing DEV                    | 0               |

Gold runtime sample counts:

| Model             |      Rows |
| ----------------- | --------: |
| `dim_customers`   |    50,000 |
| `fact_orders`     |   200,000 |
| `fact_app_events` | 1,630,000 |

All 502 dbt data tests passed with zero warnings, errors, or skips.

## 6. Routine TEST Workflow

After initial provisioning, routine validation uses the existing TEST database.

```powershell
dbt debug --target test
dbt run --target test --threads 2
dbt test --target test --threads 2
```

These commands cover the current dbt models and data tests. Snapshot execution is a separate operation and must follow the intended snapshot test strategy.

Develop changes in DEV first, validate on TEST, review the results, and promote approved changes through the Git workflow.

## 7. Limitations and Follow-Up

The following are not yet fully validated:

- TEST-specific Informatica ingestion pipelines.
- Snapshot updates and historical change tracking in TEST.
- Routine execution and lifecycle of the experimental SCD Lab.
- PROD configuration and deployment.
- Automated CI/CD execution and environment provisioning.
- External applications, dynamic SQL, and all possible cross-database access paths.

The successful SQL metadata audit establishes that no explicit DEV references were detected in the inspected SQL modules, registered dependencies, or synonyms. It is not proof that every possible external dependency has been eliminated.

## 8. Current Status

**TEST environment validated for the current dbt model rebuild and regression-testing workflow.**

Evidence: 35 dbt models rebuilt across Silver and Gold, 502/502 data tests passed, Business Snapshot accessible, and SQL metadata isolation checks passed.

Next phase: documentation review, Git commit, pull request, and CI/CD preparation.
