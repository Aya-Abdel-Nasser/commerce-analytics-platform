# Project 2 — Bronze Validation, all 5 source systems

**Purpose:** a single, reusable `docs/validation` folder for independently validating physical **SOURCE**, SQL Server **TARGET**, audit records, and—where supported—full **SOURCE-to-TARGET reconciliation**. This is for *initial snapshots*, not CDC/incremental refreshes.

> **Safety:** never rerun any of the successful Informatica initial-load mappings just to test data. All packaged validation routines leave the original sources and permanent SQL Server tables unchanged. A few relational scripts use session-only temporary tables; the Application Events reconciliation writes temporary working files that it automatically deletes.

## Folder inventory

| Folder | SOURCE | TARGET (SQL Server) | Full reconciliation |
|---|---|---|---|
| `01_postgresql_oltp` | `01_validate_SOURCE_postgresql.sql`, run **in PostgreSQL** | `02_validate_TARGET_sqlserver.sql`, run **in SSMS** | Counts, schema/PK, and NULL profiles; exact row equality still requires source/target keyed comparison |
| `02_mysql_crm` | `01_validate_SOURCE_mysql.sql`, run **in MySQL** | `02_validate_TARGET_sqlserver.sql`, run **in SSMS** | Counts, schema/PK, and NULL profiles; exact row equality still requires source/target keyed comparison |
| `03_partner_shipping_csv` | `01_validate_shipping_SOURCE.py` | `02_validate_shipping_TARGET_SQLSERVER.sql` | `03_reconcile_shipping_SOURCE_TARGET.py`, 9 fields per shipment |
| `04_returns_api` | `01_validate_returns_SOURCE.py` | `02_validate_returns_TARGET_SQLSERVER.sql` | `03_reconcile_returns_SOURCE_TARGET.py`, Unicode JSON text |
| `05_application_events` | `01_validate_SOURCE_events.py` | `02_validate_TARGET_events_SQLSERVER.sql` | `03_reconcile_SOURCE_TARGET_events.py`, every Unicode JSON line across 9 files |
| `00_project_wide` | Reference expected counts and audit checklist | `01_ALL_FIVE_TARGETS_AND_AUDIT.sql` | Cross-source initial-count and latest-audit report |
| `reports` | Empty by default | Save local run reports/results here | Save final evidence here |

**Important:** Scripts validate the **actual live database/source files when you execute them**, not the historical README alone. The Source Application Events JSONL files are on *your computer*, not included in this ZIP. `05_application_events/manifest_REFERENCE.json` is a supplied manifest copy, *not evidence that all nine physical files were scanned*. Use `manifest.json` in the real source directory during validation.

## Expected initial-load inventory

| Source system | Source objects | Target tables | Manifest/baseline rows |
|---|---:|---:|---:|
| PostgreSQL OLTP | 5 tables | 5 tables | 968,000 |
| MySQL CRM | 6 tables | 6 tables | 665,120 |
| Partner Shipping CSV | 4 files | 1 table | 120,000 |
| Returns API | 1 JSONL | 1 table | 22,093 |
| Application Events | 9 JSONL | 1 table | 1,630,000 |
| **TOTAL** | **25 source objects** | **14 target tables** | **3,405,213** |

**SQL Server database:** `commerce_warehouse_dev`; schemas `bronze` and `control`; audit `control.etl_run_log`.

## Current evidence (as supplied in the conversation, 14 Oct 2026)

| System | Informatica evidence | SQL Server evidence | Full reconciliation evidence | Closeout status |
|---|---|---|---|---|
| PostgreSQL | Load completed (5 tables) | Previous count confirmations | Not yet an exact full-row comparison | Baseline loaded; review SOURCE/TARGET scripts for evidence |
| MySQL | Load completed (6 tables) | Previous count confirmations | Not yet an exact full-row comparison | Baseline loaded; review SOURCE/TARGET scripts for evidence |
| Shipping | Success; 120,000 | 120,000; carrier/status distributions match | Script created; no user PASS run supplied yet | Pending exact row reconciliation |
| Returns | Success; 22,093 | Target SQL tests passed, audit run 16 SUCCESS | **PASS** direct ODBC: 22,093 exact Unicode JSON texts, zero mismatches | **Validated** (optional lineage fields still NULL) |
| Events | Success; 1,630,000 rows processed | **Not yet checked from target**, screenshot is a job monitor | **Not yet run against live target** | **Pending target validation + exact reconciliation** |

A screenshot of `Rows Processed=1,630,000` establishes Informatica job activity, **not** SQL table contents. Do not mark the entire folder *fully validated* until the above pending checks have run.

## Install/copy location

Extract **the contents of this folder** into your project as:

```text
D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\docs\validation\
    README_START_HERE.md
    00_project_wide\
    01_postgresql_oltp\
    02_mysql_crm\
    03_partner_shipping_csv\
    04_returns_api\
    05_application_events\
    reports\
```

The commands below assume PowerShell is opened at the root of `commerce-analytics-platform`.

## RUN FIRST: global SQL Server target & audit counts (all 14 tables)

Open `docs\validation\00_project_wide\01_ALL_FIVE_TARGETS_AND_AUDIT.sql` in SSMS, run against `commerce_warehouse_dev`.

Expected: **14** `PASS` target count rows, five source-group count PASS results, grand total **3,405,213** PASS, and latest audit success with matching `rows_processed` for each relevant initial mapping. Save screenshot or CSV export under `docs/validation/reports/`.

**Heads-up:** old MySQL `run_id` 8/9 were seen as `RUNNING` with NULL `end_time`; this is an audit hygiene issue to review separately, not a reason to rerun any load. Global script only reports them; it will not modify audit history.

## RUN SECOND: Application Events (source + target + reconciliation)

**A. Source** — scans all 9 JSONL files locally, checks full JSON parse, IDs, type distributions, UTC timestamps, manifest counts, and 11,897 late events (>=24 h):

```powershell
python ".\docs\validation\05_application_events\01_validate_SOURCE_events.py" --input-dir ".\data\landing\events\prodlike\initial" --output-json ".\docs\validation\reports\05_EVENTS_SOURCE.json"
```

Expected output: `RESULT: PASS`, `Total rows: 1,630,000`, `Late events >=24h: 11,897`, `Event IDs duplicated: 0`.
The Events profiler also reports **maximum JSON line length (characters and UTF-8 bytes)** plus number of lines containing the `|` delimiter. If the `|` count is not zero, review the Informatica flat-file parsing configuration before approving the ingest.

**B. Target** — open `docs\validation\05_application_events\02_validate_TARGET_events_SQLSERVER.sql` in **SSMS**; execute it. Look for row count PASS, zero invalid JSON and missing IDs, eight event-type distribution PASS results, ID uniqueness, and 11,897 late events. Data-quality checks may take minutes on SQL Server Express.

**C. Exact SOURCE ↔ TARGET text comparison** — use the already installed `pyodbc` and `ODBC Driver 18 for SQL Server`. Run this **as one PowerShell command** from the project root:

```powershell
python ".\docs\validation\05_application_events\03_reconcile_SOURCE_TARGET_events.py" --source-dir ".\data\landing\events\prodlike\initial" --connection-string 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly' --out ".\docs\validation\reports\05_EVENTS_RECONCILIATION.json"
```

> Windows PowerShell: the server name is **`.\SQLEXPRESS` with one backslash**, as shown in the raw code above. Do not add a second backslash when typing it.

This comparison uses **256 temporary disk partitions** and exact Unicode JSON text equality (including duplicate counts and JSON property order). It is designed to avoid holding 1.63 million text strings in RAM. **Ensure sufficient free temporary disk space (roughly 2× the source JSONL volume plus overhead)**. It writes only to a temporary folder and the requested report file. Expected: `PASS`, `Source rows: 1,630,000`, `Target rows: 1,630,000`, `Missing: 0`, `Unexpected: 0`.

> This proves text preservation within SQL NVARCHAR. It does **not** prove original UTF-8 byte equality because source line delimiters and optional BOM do not live inside `raw_json`. Source file checksums belong in immutable source archives; successful row comparison doesn't check `source_file_name` or `source_line_number` lineage.

If the command fails, **do not rerun the ETL**. Review the JSON report, missing/extra hashes, actual SQL row count, SQL Agent logs or field precision. Keep the source files unchanged.

## RUN THIRD: remaining sources and warehouse

**Partner Shipping, source:**

```powershell
python ".\docs\validation\03_partner_shipping_csv\01_validate_shipping_SOURCE.py" --source-dir ".\data\landing\partners\prodlike\initial" --baseline ".\docs\validation\03_partner_shipping_csv\05_SHIPPING_INITIAL_SOURCE_BASELINE.json" --out ".\docs\validation\reports\03_SHIPPING_SOURCE.json"
```

**Shipping target:** `03_partner_shipping_csv/02_validate_shipping_TARGET_SQLSERVER.sql` (SSMS). **Shipping exact 9-column comparison:**

```powershell
python ".\docs\validation\03_partner_shipping_csv\03_reconcile_shipping_SOURCE_TARGET.py" --source-dir ".\data\landing\partners\prodlike\initial" --connection-string 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly' --allow-null-delivered-at --out ".\docs\validation\reports\03_SHIPPING_RECONCILIATION.json"
```

`--allow-null-delivered-at` permits **only** expected CSV `''` to SQL `NULL` conversions in `delivered_at`. The resulting report counts this exception; all other differences must fail. If you want byte/string strictness including empty vs NULL, rerun **without** this switch; whether it passes depends on the mapping's actual NULL handling.

**Returns source:**

```powershell
python ".\docs\validation\04_returns_api\01_validate_returns_SOURCE.py" --source-dir ".\data\landing\api\prodlike\initial" --out ".\docs\validation\reports\04_RETURNS_SOURCE.json"
```

**Returns target:** `04_returns_api/02_validate_returns_TARGET_SQLSERVER.sql` (SSMS). **Returns exact text comparison (previously PASSED, rerunnable for evidence):**

```powershell
python ".\docs\validation\04_returns_api\03_reconcile_returns_SOURCE_TARGET.py" --source-file ".\data\landing\api\prodlike\initial\returns_initial.jsonl" --connection-string 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly' --out ".\docs\validation\reports\04_RETURNS_RECONCILIATION.json"
```

**PostgreSQL:** run `01_postgresql_oltp/01_validate_SOURCE_postgresql.sql` **in PG** (source database, schema `commerce`), then `01_postgresql_oltp/02_validate_TARGET_sqlserver.sql` **in SSMS**. Compare five table counts, catalogs, actual source PK/FK definitions, source/target NULL counts and audit records. PG script creates a session temporary table for reporting only; it doesn't alter persistent source tables.

**MySQL:** run `02_mysql_crm/01_validate_SOURCE_mysql.sql` **in MySQL Workbench** connected to `commerce_crm_dev`, then `02_mysql_crm/02_validate_TARGET_sqlserver.sql` **in SSMS**. Compare six table counts, column data types/precision/scale, PK/FK, target NULL profiles and audit. MySQL script runs dynamic SQL via `PREPARE`; it doesn't alter persistent tables.

### Scope and remaining correctness limits

- Source/target **count equality** (PG and MySQL) plus matching column-level NULL profiles **do not prove every row value is the same**. A production-grade *full* sign-off for these 11 relational tables still needs keyed row-level reconciliation, using source table PK and an agreed canonical datatype/precision mapping.
- Shipping candidate keys are observed in CSV, not enforced database PK constraints.
- Returns and Events are sourced from *snapshot files produced upstream*. This validates the local extracts → Bronze ingest, not completeness against a live external REST service or all application production events.
- Some Bronze file/line lineage columns may be NULL by design of the current ingestion; log as a follow-up improvement.
- Keep source manifests, validation logs, final JSON reports and relevant taskflow run IDs with the project. Do **not** commit passwords/connection strings containing secrets or full customer data dumps to GitHub.

## How to sign off

Fill in `00_project_wide/VALIDATION_SIGNOFF_TEMPLATE.md` after you run the checks. Record **PASS / FAIL / NOT RUN**, date/time, row count, report path, issue reference and audit run ID. Preserve pre-existing validation evidence, don't manufacture proof of checks not run. Only mark "ALL 5 VALIDATED" after all mandatory stages are truly PASS; defer PG/CRM full row equality explicitly if not in scope.
