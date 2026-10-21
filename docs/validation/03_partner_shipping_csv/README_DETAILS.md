# Project 2 — Partner Shipping: Complete Source → Bronze Validation Pack

**Scope:** `partner_shipping_prodlike_initial`, 4 CSV files → Informatica CDI File List → `commerce_warehouse_dev.bronze.partner_shipments` (120,000 initial rows).

**Safety:** All scripts in this pack are **read-only** with respect to source files and SQL Server. There are **no DELETE, TRUNCATE, UPDATE, INSERT, CREATE, DROP, or re-load operations**.

## Files and purposes

| File | Purpose | Technology |
|---|---|---|
| `01_validate_shipping_SOURCE.py` | Validate all four physical source files, manifest and optionally pinned file hashes. Outputs JSON | Python standard library |
| `02_validate_shipping_TARGET_SQLSERVER.sql` | Validate SQL Server metadata, counts, domains, NULLs, keys, business rules, order references and audit | SQL Server T-SQL / SSMS |
| `03_reconcile_shipping_SOURCE_TARGET.py` | Compare every target row and all 9 columns to source, matched by `shipment_id` | Python, optional `pyodbc` |
| `04_export_SQL_TARGET_for_row_comparison.sql` | Optional target `SELECT` for exporting to CSV if pyodbc is unavailable | SQL Server T-SQL |
| `05_SHIPPING_INITIAL_SOURCE_BASELINE.json` | The reference SHA-256 hash for each inspected source CSV + distribution/row-count baseline | JSON |
| `SOURCE_VALIDATION_REFERENCE_RESULT.json` | **Actual source-only validation** executed against the original 4 CSVs available to this project | JSON |

### 1. Run SOURCE validation locally (no external Python packages)

**Path actually used by this project's Informatica Flat File Connection:**

```text
D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\partners\prodlike\initial
```

Copy/extract this entire validation pack to a project folder, for example:

```text
commerce-analytics-platform\docs\validation\03_partner_shipping\
```

Open PowerShell in the extracted validation folder. Run as a **single line**:

```powershell
python .\01_validate_shipping_SOURCE.py --source-dir "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\partners\prodlike\initial" --baseline ".\05_SHIPPING_INITIAL_SOURCE_BASELINE.json" --out ".\reports\SOURCE_shipping_initial.json"
```

Expected terminal summary from the ORIGINAL four source files:

```text
SOURCE VALIDATION: PASS
ROWS: 120000
CARRIER COUNTS: {'DLV': 30018, 'EGX': 29943, 'FST': 30136, 'NIL': 29903}
STATUS COUNTS: {'DELAYED': 2353, 'DELIVERED': 80000, 'IN_TRANSIT': 37647}
EMPTY delivered_at: 40000
ERRORS: {}
```

It checks: files/inventory, headers and column order, UTF-8 CSV parsing, field counts, missing and whitespace-only values, observed min/max lengths, candidate-key duplicates (`shipment_id`, `order_number`, `tracking_number`), exact full-row duplicates, `carrier_code` matching its file, tracking-number prefix, status domain, expected/legitimate `delivered_at` blanks, timestamp lexical format and chronological consistency, fee decimal lexical format/sign, manifest total and per-carrier/status totals. It reports SHA-256 and verifies each hash against the optional pinned baseline. **A changed hash means changed source file bytes, not necessarily invalid data.**

`manifest.json` is metadata, not an additional CSV. `shipping_files_initial.txt` is the Informatica file list, not a fifth data file.

### 2. Run TARGET validation in SQL Server (no Python)

Open `02_validate_shipping_TARGET_SQLSERVER.sql` in the SQL editor. Connect to your local SQL Server Express instance and **run all statements** in `commerce_warehouse_dev`.

Review each result set:

1. Actual SQL Server column catalog (`NVARCHAR`, character limits, SQL nullability and catalog precision/scale).
2. Column-contract `PASS/FAIL` for the exact nine-column Bronze schema.
3. Actual SQL-enforced constraints (may be no rows, intentionally; source has none).
4. Overall row count — expected **120,000**.
5. Four carrier-count comparisons — expected **PASS** for all four.
6. Three status-count comparisons — expected **PASS** for all three.
7. Twelve carrier × status cross-tab comparisons — expected **PASS** for all twelve.
8. All nine columns' **SQL NULL vs empty-string** counts (do not conflate these).
9. `delivered_at` by status — expected **40,000 SQL NULL or empty combined**, zero missing shipment IDs.
10. Observed uniqueness of three business candidate keys — expected **120,000 distinct each**.
11. Duplicate key and exact duplicate row **examples** — expected **no results**.
12. Fourteen data-quality issue counts — expected **all zero**.
13. Optional cross-source relationship `shipping.order_number → bronze.oltp_orders.order_number`, which is a business reference, **not** a declared foreign key.
14. Recent `control.etl_run_log` audit for the shipping pipeline — latest recorded successful initial run is `run_id = 15`, `SUCCESS`, `rows_processed = 120000`, with a UUID (per the actual user-provided audit output).

**Important SQL Server caveat:** The target has nullable `NVARCHAR` columns. The original CSV `delivered_at` contains *40,000 empty strings*; Informatica may write SQL `NULL` instead of `''`. The SQL script reports both separately. Combined blank/NULL counts alone **do not prove exact text preservation**. Run Step 3 for that.

### 3A. Row-by-row SOURCE vs TARGET reconciliation (best: direct SQL Server connection)

The direct approach compares *all 9 text fields*, **case-sensitively**, for every `shipment_id`, and detects missing and extra IDs, target duplicates, source duplicates and changed values. It never changes SQL Server.

**Optional prerequisite**, only for this third step:

```powershell
python -m pip install pyodbc
```

An installed Microsoft **ODBC Driver 18 for SQL Server** is also required (or edit to use the installed driver name, such as 17). Windows Integrated Authentication is used in the example:

```powershell
python .\03_reconcile_shipping_SOURCE_TARGET.py --source-dir "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\partners\prodlike\initial" --connection-string "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes" --out ".\reports\RECONCILIATION_shipping_initial.json"
```

**Null conversion policy:** The strict default treats SQL `NULL` as **different** from CSV `''`. If source empty `delivered_at` is intentionally written as SQL NULL, rerun with `--allow-null-delivered-at`. This exception applies **only** to that field and is explicitly counted as `allowed_empty_csv_to_null_sql_conversions` (possibly 40,000). No other differences are ignored.

```powershell
python .\03_reconcile_shipping_SOURCE_TARGET.py --source-dir "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\partners\prodlike\initial" --connection-string "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes" --allow-null-delivered-at --out ".\reports\RECONCILIATION_shipping_initial.json"
```

The script fails if totals are not 120,000, if any `shipment_id` is missing, extra, duplicated, or if any untolerated column-level difference is found. JSON includes mismatch samples. This is a comparison of **parsed field values**, not byte-for-byte CSV representation (quotes, newline style, BOM and CSV escaping are not part of SQL rows).

### 3B. Alternate reconciliation without ODBC: export TARGET CSV

If pyodbc/ODBC is unavailable, open `04_export_SQL_TARGET_for_row_comparison.sql` in SSMS, run it, and export the **results grid to CSV with nine column headers in the same order**. Make sure it is real comma-delimited CSV, in UTF-8, without query messages or row-count footer. Save, e.g., `partner_shipments_target_export.csv` **outside the source file-list folder** to avoid accidental ingestion.

```powershell
python .\03_reconcile_shipping_SOURCE_TARGET.py --source-dir "D:\Data_Engineer_Work_With_VSCode\Projects\commerce-analytics-platform\data\landing\partners\prodlike\initial" --target-csv "D:\path\to\partner_shipments_target_export.csv" --out ".\reports\RECONCILIATION_shipping_initial.json"
```

**Limitation:** Generic CSV exports may serialize SQL NULL and empty strings identically, so this alternative cannot validate SQL NULL-vs-empty fidelity; prefer direct ODBC for that distinction. Values may also be reformatted by export tools; keep exact text.

## What counts as a complete PASS?

- **Source**: Python source validation PASS, expected manifest counts, no source data-quality violations, and (if used) baseline hashes match.
- **Target**: SQL schema contract PASS; total/carrier/status/cross-tab counts PASS; duplicate key/row checks clean; data-quality issue counts 0; audit record SUCCESS.
- **Reconciliation**: Exact 9-field equality for all 120,000 matching IDs, or a clearly documented intentional `delivered_at` `'' -> NULL` exception.
- **Lineage**: Optional order-number reference check is clean *if the two bronze datasets use compatible source snapshots*.

Do not infer complete correctness from `Taskflow = Success` or `COUNT(*) = 120000` alone. **Do not rerun initial Shipping mapping/taskflow**; it has already loaded, and an Insert reload could duplicate data.

## Engineering learning notes

- **Physical source:** CSV field text; no enforced `PK`, `FK`, native datatypes, `NOT NULL`, numeric precision/scale or source indexes.
- **Observed source properties:** 9 headers; all 120,000 `shipment_id`, `order_number`, `tracking_number` values unique in *this* batch; observed shipping fees use two decimal places (`DECIMAL(4,2)`-like text); timestamp strings are declared UTC **by manifest**.
- **Declared target schema:** 9 SQL Server `NVARCHAR` nullable columns, with explicit maximum character lengths. `sys.columns.precision`/`scale` values for NVARCHAR are **catalog attributes, not source numeric precision/scale**.
- **Observed business NULL:** `delivered_at` is empty for `IN_TRANSIT` and `DELAYED`, and populated for `DELIVERED` in this snapshot.
- **Business key assumptions:** Unique `order_number` is an observation here, not a guarantee for future shipments; multi-shipment orders are possible in other datasets.
- **Data equality:** Row counts and group totals are weak checks on their own. Key-based full-row reconciliation reveals wrong fee, timestamp or tracking number even if counts match.
- **Repeatability:** Baseline SHA-256 and JSON reports preserve evidence about the exact initial batch. Copy original CSVs and `manifest.json` into an immutable archive in a real production environment.
