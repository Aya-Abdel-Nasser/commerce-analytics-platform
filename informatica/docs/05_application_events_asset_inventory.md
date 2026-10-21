# Informatica Asset Inventory — 05 Application Events Ingestion

## Scope and evidence

- **Project / folder:** `Default / 05_APPLICATION_EVENTS_INGESTION`
- **Captured:** 2026-10-18 (Informatica Explore screenshot supplied during project review)
- **Inventory:** 3 assets visible; all display `Valid` in the Explore `Status` column.
- **Evidence type:** Screenshot-based UI inventory. **Not** an Informatica export and **not** proof of end-to-end execution, taskflow dependencies, or source-to-target data accuracy.

## Verified asset list

| # | Asset name as displayed | Asset type | Explore status | Updated on (as displayed) |
|---|---|---|---|---|
| 1 | `mt_bronze_app_events_initial` | Taskflow | Valid | Oct 14, 2026, 1:48 PM |
| 2 | `mt_bronze_app_events_initial` | Mapping Task | Valid | Oct 14, 2026, 1:41 PM |
| 3 | `m_bronze_app_events_initial` | Mapping | Valid | Oct 14, 2026, 1:34 PM |

> **Naming collision:** The *Taskflow* and *Mapping Task* are shown with exactly the same name (`mt_bronze_app_events_initial`). Their **asset types** distinguish them. Do not automatically rename either asset; first inspect dependencies and execution references. A `tf_` prefix for the Taskflow can be considered during a later controlled refactor.

## Data contract and target (project baseline)

- Source: local Application Events initial JSONL snapshot (9 files according to the project validation baseline).
- Expected initial volume: **1,630,000** events.
- SQL Server target: `commerce_warehouse_dev.bronze.app_events_raw`.
- Validation package: `docs/validation/05_application_events/`.
- Target profile script: `02_validate_TARGET_events_SQLSERVER.sql`.
- Exact source/target comparison script: `03_reconcile_SOURCE_TARGET_events.py`.

These values describe the **project baseline**. The screenshot alone does not establish which specific source connection/paths or target field mappings each asset currently uses; open the mapping and taskflow configurations to confirm.

## Verification and outstanding work

| Check | Current evidence / next action |
|---|---|
| Mapping and Mapping Task design status | `Valid` displayed in Explore on 2026-10-18 |
| Taskflow design status | `Valid` displayed in Explore on 2026-10-18 |
| Taskflow to Mapping Task dependency and error handling | **Not verified from the inventory screenshot**; inspect Taskflow design |
| Live SQL Server target row-count / JSON quality | **Not verified by this screenshot**; save dated SSMS result |
| Exact JSONL source-to-target reconciliation | Historical report exists in the project, but **not independently re-executed/verified during this inventory**; preserve provenance and run evidence |
| Audit log (`control.etl_run_log`) | Verify latest matching `execution_id`, `status`, and `rows_processed` with SSMS |
| Official export package | Export control not shown in current account; this inventory is **documentation only**, not a restorable asset package |

## Review notes

1. Keep the screenshot/evidence reference in the local project documentation or validation report, without secrets.
2. Do not mark `SOURCE_TO_TARGET = PASS` solely from `Valid` asset status or Informatica `Rows Processed`.
3. Do not rerun initial load solely for documentation.
4. Record actual Taskflow steps, connection references (names only), source/target settings, and failure route when design screenshots are available.
