# Informatica CDI — Partner Shipping Asset Inventory

**Project:** Commerce Analytics Platform\
**Informatica location:** `Default / 03_PARTNER_SHIPPING_INGESTION`\
**Inventory captured:** 2026-10-18\
**Evidence:** User-provided Informatica Data Integration → Explore screenshot displaying all three objects (3 of 3).\
**Evidence type:** Manual UI inventory. **Not** a native Informatica asset export or importable backup.

## 1. Inventory summary

| Asset type | Total | Valid | Invalid |
|---|---:|---:|---:|
| Taskflow | 1 | 1 | 0 |
| Mapping Task | 1 | 1 | 0 |
| Mapping | 1 | 1 | 0 |
| **Total** | **3** | **3** | **0** |

`Valid` is the design status displayed in Informatica Explore. It does not, by itself, establish a successful execution, data completeness, or tested failure/recovery behavior.

## 2. Full asset inventory

The timestamps below are transcribed as displayed by Informatica. The UI timezone has not been independently established.

| # | Asset name | Asset type | Updated on (UI) | Status (UI) |
|---:|---|---|---|---|
| 1 | `tf_bronze_partner_shipments_audit` | Taskflow | Oct 14, 2026, 10:33 AM | Valid |
| 2 | `mt_bronze_partner_shipments_initial` | Mapping Task | Oct 14, 2026, 10:22 AM | Valid |
| 3 | `m_bronze_partner_shipments_initial` | Mapping | Oct 14, 2026, 10:19 AM | Valid |

## 3. Expected business data flow

**Source:** Partner Shipping initial CSV snapshot(s), four physical files in the project's documented initial baseline.\
**Target:** SQL Server database `commerce_warehouse_dev`, table `bronze.partner_shipments`.\
**Expected initial row count:** **120,000** (reference baseline, not a live count verified by the UI screenshot).

**Name-based asset grouping (to verify in designers):**

```text
m_bronze_partner_shipments_initial
            ↑ referenced by (expected)
mt_bronze_partner_shipments_initial
            ↑ invoked by (expected)
tf_bronze_partner_shipments_audit
```

The expected Taskflow → Mapping Task → Mapping dependencies are inferred from asset naming conventions; the Explore screenshot does not expose internal task references, connections, transformations, or target write strategy.

## 4. Current validation status and evidence

| Check | Status / evidence |
|---|---|
| Three design assets present in folder | **Observed** (3/3) |
| All three design statuses `Valid` | **Observed** |
| Expected 120,000 initial source rows | **Reference baseline**; independently dated source check evidence must be linked |
| Actual SQL Server target count | **Not established by this inventory screenshot**; use the SQL Server target validation script and attach result |
| Exact source-to-target reconciliation (nine shipping fields) | **Not established by this inventory screenshot**; execute/review `docs/validation/03_partner_shipping_csv/03_reconcile_shipping_SOURCE_TARGET.py` and save dated evidence |
| Taskflow audit start/finish execution and error path | **Not established by this inventory screenshot**; verify in taskflow design and runtime logs |
| Native importable Informatica export | **Not available/provided**; manual documentation is not a replacement for an export |

**Relevant validation assets already in the local project:**

- `docs/validation/03_partner_shipping_csv/01_validate_shipping_SOURCE.py`
- `docs/validation/03_partner_shipping_csv/02_validate_shipping_TARGET_SQLSERVER.sql`
- `docs/validation/03_partner_shipping_csv/03_reconcile_shipping_SOURCE_TARGET.py`
- `docs/validation/03_partner_shipping_csv/04_export_SQL_TARGET_for_row_comparison.sql`
- `docs/validation/03_partner_shipping_csv/05_SHIPPING_INITIAL_SOURCE_BASELINE.json`
- `docs/validation/00_project_wide/01_ALL_FIVE_TARGETS_AND_AUDIT.sql`

## 5. Documentation follow-ups

1. Inspect the Taskflow's task references, audit start/finish parameter bindings, success/failure paths, and mapping task configuration without running the pipeline.
2. Record source file pattern, connection names (without secrets), mapping field treatment, target write operation, and replay/idempotency expectations.
3. Attach dated Source, Target, Reconciliation, and Audit evidence with run IDs before marking the ingestion stage fully validated.
4. Keep screenshots, configuration samples, and reports free of tokens, passwords, personal records, and sensitive connection details before committing to Git.

**As-built inventory conclusion:** `03_PARTNER_SHIPPING_INGESTION` contains **three design objects and all appear Valid** in Explore as captured on 2026-10-18. Data-level and end-to-end operational sign-off remain separate activities.
