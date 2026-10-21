# Project 2 — Returns REST API → Bronze: Complete Validation Study Pack

**Source system:** `MOCK_RETURNS_API` (a local/mock REST API, endpoint `/api/v1/returns`)\
**Extracted snapshot:** `returns_initial.jsonl` + `manifest.json`\
**Informatica:** `m_bronze_returns_api_initial` → `mt_bronze_returns_api_initial` → `tf_bronze_returns_api_audit`\
**Warehouse:** `commerce_warehouse_dev.bronze.returns_raw`\
**Expected source records:** **22,093** (initial snapshot only)\
**Safety:** All delivered scripts are **read-only** to source and SQL Server. They do NOT re-run loading, create tables, delete rows, or truncate anything.

## What the screenshots actually established

In Informatica **My Jobs**, the Taskflow `tf_bronze_returns_api_audit` has `Success`; all 3 subtasks are `Success`; the Returns mapping task reports **22,093 rows processed**, Audit Start `1`, Audit Finish `1`.

This establishes **orchestration success**, not full data equality. You must run the target and reconciliation checks to prove actual table content and avoid silently truncated / reserialized JSON. The SQL target was not accessible to the pack creator; no target-level PASS is claimed.

## Pack contents

| File | Purpose | Dependency |
|---|---|---|
| `01_validate_returns_SOURCE.py` | JSONL structure, full envelope & payload schema, ISO-UTC timestamps, amount as string, IDs, status/reason counts, manifest and SHA-256 | **Python standard library** |
| `02_validate_returns_TARGET_SQLSERVER.sql` | SQL Server metadata, full counts, JSON validity, missing keys, exact status/reason distributions, candidate key uniqueness, duplicates, dates, refunds, provenance, cross-system orders, audit | **SQL Server / SSMS** |
| `03_reconcile_returns_SOURCE_TARGET.py` | Compare **every full JSON text record** from source against `raw_json` from SQL, independent of row order; find missing/extra/changed records | Python standard library for exported CSV; `pyodbc` optional for direct DB |
| `04_export_returns_TARGET_for_reconciliation.sql` | Read-only `SELECT raw_json` for SSMS export to CSV when direct database connection isn't convenient | SQL Server / SSMS |
| `reports/SOURCE_returns_initial_VERIFIED.json` | **Actual validated source-only reference result** against the provided source file and its matching Returns manifest | JSON |
| `README_START_HERE.md` | Full runbook + interpretation | Markdown |

## Step 1 — Validate SOURCE (your own Windows filesystem)

The correct source folder used in your Informatica Connection is:

```text
D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\api\prodlike\initial
```

The folder must contain both `returns_initial.jsonl` and the **Returns** `manifest.json` (NOT the Shipping or App Events manifests). From **PowerShell in the extracted pack folder**:

```powershell
python .\01_validate_returns_SOURCE.py --source-dir "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\api\prodlike\initial" --out ".\reports\SOURCE_returns_initial.json"
```

Expected for the original snapshot:

```text
RETURNS SOURCE VALIDATION: PASS
Rows: 22093 | JSON objects: 22093
Max chars: 369
Errors: {}
```

The script enforces this **initial snapshot** SHA-256 (archive integrity):

```text
3a352fda4b17a5c62fc167a6d613b576dd2fb67d47e30850aab221191f12f0e7
```

For a **different future extract**, the baseline counts, manifest timestamps, and schema may be different; update a copy of the study script for that new snapshot rather than treating intentional new data as a bad load. `--skip-pinned-hash` skips only hash comparison, not the initial-snapshot expected distributions.

### Actual verified source baseline

| Metric | Count |
|---|---:|
| JSONL physical lines | 22,093 |
| Valid JSON objects | 22,093 |
| Max source JSON line length | 369 characters |
| Distinct `return_id` | 22,093 |
| Distinct `order_number` in this snapshot | 22,093 |
| Source quality validation violations | 0 |

| `return_status` | Expected rows |
|---|---:|
| REJECTED | 5,611 |
| REFUNDED | 5,558 |
| REQUESTED | 5,518 |
| APPROVED | 5,406 |

| `reason_code` | Expected rows |
|---|---:|
| WRONG_ITEM | 5,579 |
| CHANGED_MIND | 5,552 |
| NOT_AS_DESCRIBED | 5,550 |
| QUALITY_ISSUE | 5,412 |

`requested_refund_egp` is **JSON string**, not numeric JSON; observed range **188.73–41280.57 EGP**. UTF-8 source JSONL and Manifest should remain archived; an NVARCHAR target is not a byte-for-byte archive of the original source file.

## Step 2 — Validate TARGET in SQL Server

1. Open **SSMS** on the SQL Server Express instance used by Informatica.
2. Open `02_validate_returns_TARGET_SQLSERVER.sql`.
3. Execute the **entire script**; it sets `USE [commerce_warehouse_dev]`.
4. Review each labelled result set. The expected column contract is:

| Ordinal | SQL column | SQL data type | Nullable |
|---|---|---|---|
| 1 | `raw_json` | `NVARCHAR(MAX)` | NO |
| 2 | `source_file_name` | `NVARCHAR(260)` | YES |
| 3 | `source_line_number` | `BIGINT` | YES |

The target checks explicitly distinguish **SQL constraints** from source data observations. No PK/FK on this raw landing table is expected. `source_file_name` / `source_line_number` were intentionally *not populated* by the current mapping; SQL NULLs in these optional columns are not a failed load.

**Expected results:** 22,093 rows; valid JSON 22,093; exact status/reason distributions from Step 1; distinct return IDs 22,093; no duplicate IDs; no missing required fields; timestamps parse as UTC; no negative or invalid refunds; audit newest returns row `SUCCESS`, `rows_processed=22093`, correct UUID. If `bronze.oltp_orders` is present, orphan order check should be assessed too.

**Important:** `ISJSON(raw_json) = 1` does **not** prove JSON text is identical to the original: JSON may have been altered and still be valid. Use Step 3.

## Step 3 — Reconcile EVERY source JSON line against target raw_json

### Option A (recommended): direct read-only SQL using `pyodbc`

Only this third step needs an additional package, if you want a direct DB comparison:

```powershell
python -m pip install pyodbc
```

You also need an installed **ODBC Driver 18 for SQL Server** (or use its correct installed version). In PowerShell (single line):

```powershell
python .\03_reconcile_returns_SOURCE_TARGET.py --source-file "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\api\prodlike\initial\returns_initial.jsonl" --connection-string "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly" --out ".\reports\RECONCILIATION_returns_initial.json"
```

This performs `SELECT raw_json FROM bronze.returns_raw` only. Change `SERVER` or driver to match your installation; the connection must have `SELECT` permission. `ApplicationIntent=ReadOnly` requests read-only intent but **does not replace permissions**; the Python code itself never writes to SQL Server.

### Option B (without pyodbc): export target text once

1. Run `04_export_returns_TARGET_for_reconciliation.sql` in SSMS.
2. Export the **result set** as real **UTF-8 CSV** with the single header `raw_json` and all 22,093 rows. Keep this export **outside** the folder used by Informatica so it cannot be accidentally ingested.
3. Use an export that preserves embedded JSON quotes as standards-compliant CSV. SSMS export settings can differ; if double quotes are not escaped correctly, the script will detect malformed CSV.
4. Run:

```powershell
python .\03_reconcile_returns_SOURCE_TARGET.py --source-file "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\api\prodlike\initial\returns_initial.jsonl" --target-csv "D:\path\to\returns_target_export.csv" --out ".\reports\RECONCILIATION_returns_initial.json"
```

Expected if all rows are exactly preserved:

```text
RETURNS SOURCE-to-TARGET RECONCILIATION: PASS
Source rows: 22093 | Target rows: 22093
Missing raw text: 0 | Unexpected raw text: 0
Issues: {}
```

This is a **row-order-independent multiset comparison**, so it handles the intentional absence of `source_line_number` values. It detects missing/extra JSON strings, duplicates, changed property values, changed whitespace/serialization, and truncated lines. It separately identifies changed `return_id` values and reports sample record hashes/first changed positions without dumping full PII fields.

A semantically equal JSON record with different whitespace/order is still a **FAIL** under strict raw-text preservation. The report labels such cases `parsed_json_equal=true` so you can distinguish serialization changes from business-value changes.

**Testing disclosure:** the comparison program was tested locally using a generated CSV export of the original JSONL: 22,093 exact matches returned `PASS`. A second controlled test with one altered character returned `FAIL` and pinpointed its `return_id`. **Those fixtures do not represent your actual SQL Server data.** Only your own Step 3 run can establish true source-to-target equality.

## Study notes: why 1 column is correct here

**Physical file:** newline-delimited JSON; 1 physical line = 1 JSON object, not 11 SQL columns. The object has four envelope keys (`_source_system`, `_ingested_at_utc`, `_source_endpoint`, `payload`) and the nested payload has seven keys (`return_id`, `order_number`, `requested_at`, `reason_code`, `return_status`, `requested_refund_egp`, `updated_at`). All eleven names are JSON fields; they are **not relational source columns or declared constraints**.

**Informatica source:** `FIELD1` as one string field with precision **1000** (your revised metadata); each row must contain the whole raw JSON text. Current mapping: `FIELD1 → raw_json` and optional lineage fields unset.

**SQL Server Bronze:** store JSON unchanged in `raw_json NVARCHAR(MAX)`; parse / cast / model in **Silver**. `JSON_VALUE` in target SQL script is for **testing and exploration only**; nothing is transformed in the table.

### Completion criteria

**Do not mark Returns data validated solely from Informatica `Success`.** All checks needed for a complete data validation:

1. Source Python result `PASS` with matching Returns manifest and SHA-256.
2. SQL target data types/nullable column contract `PASS`, total **22,093**, expected return statuses/reasons, no JSON / key / timestamp / refund quality issues, audit matching loaded run.
3. Reconciliation (direct DB preferred): **22,093 exact source JSON text occurrences** matched with 0 missing, 0 extra, 0 changed values.

The original source is a **mock API extracted snapshot**. This pack does not test a live REST endpoint, HTTP retries, API pagination under concurrent updates, or incremental extraction; those are separate ingestion/production tests.
