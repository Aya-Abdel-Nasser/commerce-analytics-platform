# Informatica Asset Inventory — 04_RETURNS_API_INGESTION

**Project:** Commerce Analytics Platform\
**IICS location:** `Default / 04_RETURNS_API_INGESTION`\
**Inventory observed:** 2026-10-18 (from Data Integration → Explore screenshot)\
**Evidence type:** UI inventory; **not** a portable Informatica asset export.

## 1. Observed assets

| Asset name | Informatica type | Explore status | Last updated (as displayed in UI) |
|---|---|---|---|
| `m_bronze_returns_api_initial` | Mapping | Valid | Oct 14, 2026, 12:16 PM |
| `mt_bronze_returns_api_initial` | Mapping Task | Valid | Oct 14, 2026, 12:20 PM |
| `tf_bronze_returns_api_audit` | Taskflow | Valid | Oct 14, 2026, 12:28 PM |

**Inventory total: 3 assets / 3 Valid.**

## 2. Pipeline context

- **Input represented in this project:** initial JSONL snapshot from the simulated/mock Returns API workflow; this is not direct proof of completeness against a live external API.
- **SQL Server destination:** `commerce_warehouse_dev.bronze.returns_raw`.
- **Expected initial snapshot size:** 22,093 records.
- **Intended logical flow to verify in the UI:** Mapping → Mapping Task → Taskflow; associated audit-start and audit-finish steps and their dependencies must be confirmed within the Taskflow designer. Asset names alone do not prove the exact internal wiring.

## 3. Prior evidence vs current observation

| Item | Status / limitation |
|---|---|
| Asset existence and UI validation | **Observed Valid** for all three assets on 2026-10-18. |
| Initial ingestion | Earlier project evidence indicated `control.etl_run_log` run **16**, SUCCESS, 22,093 rows. Not re-executed in this inventory step. |
| Source ↔ target reconciliation | Prior project report documented a PASS for 22,093 JSON text comparisons; recheck saved output and provenance before final sign-off. |
| Detailed mapping transformations and connection settings | Not inspected in the submitted Explore screenshot. |
| Taskflow error handling, audit-finish failure route, and restart safety | Not verified by this inventory. |
| Importable/portable Informatica export | Not available from the explored UI under current account; no export file was obtained. |

## 4. Remaining documentation and verification

1. Capture the mapping Source/Target objects, transformations, and relevant field mappings (exclude connection secrets).
2. Capture the Mapping Task load options and error-handling settings.
3. Capture Taskflow steps, dependency wiring, parameters, success and failure paths.
4. Link the relevant SQL Server validation and dated reconciliation report from `docs/validation/04_returns_api/` and `docs/validation/reports/`.
5. Keep screenshots and supporting evidence free of passwords, tokens, or raw sensitive records.

**Sign-off scope:** Inventory complete; detailed design documentation and operational validation are separate tasks.
