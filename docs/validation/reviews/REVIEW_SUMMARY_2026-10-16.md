# Commerce Analytics Platform — source validation review (2026-10-16)

Reviewed the **uploaded ZIP** in isolation. No network access to the user's local Docker databases, SQL Server or Informatica tenant was available. These are source-file verification results, NOT a live target/audit sign-off.

## Source checks executed in the review environment

| Source | Actual physical file rows | Source checker | Outcome |
| --- | ---: | --- | --- |
| PostgreSQL OLTP — 5 generated input CSV files | 968,000 | CSV file row count vs manifest only | Counts match |
| MySQL CRM — 6 generated input CSV files | 665,120 | CSV file row count vs manifest only | Counts match |
| Partner Shipping — 4 CSV files | 120,000 | `01_validate_shipping_SOURCE.py` with baseline | PASS |
| Returns mock API — one JSONL snapshot | 22,093 | `01_validate_returns_SOURCE.py` | PASS |
| Application Events — 9 JSONL files | 1,630,000 | `01_validate_SOURCE_events.py` | PASS |
| **Total physical source rows** | **3,405,213** | | |

Events: zero invalid JSON lines, duplicate IDs or pipe delimiters; 11,897 late events >=24 h; manifest totals match. Shipping: 40,000 empty `delivered_at` fields, permitted by the documented source contract.

The uploaded historical `docs/validation/reports/05_EVENTS_RECONCILIATION.json` **reports** PASS for 1,630,000 SQL target comparisons. This was NOT independently reproduced against live SQL Server during this review.

## Blockers before dbt modeling

1. Run `docs/validation/00_project_wide/01_ALL_FIVE_TARGETS_AND_AUDIT.sql` in SSMS and save all result sets. This query checks real SQL Server counts and audit statuses.
2. Run `commerce_audit_diagnostics_readonly.sql` (included) in SSMS, examine run_id 8/9 and other state inconsistencies. Capture corresponding Informatica Monitor screenshots/details. The archive has read-only audit queries, not the operational table DDL or Informatica Taskflow/mapping exports that would reveal root cause.
3. Run shipping/returns/events target validations and current direct ODBC reconciliations; preserve all new dated reports.
4. Run PostgreSQL/MySQL source and target SQL checks from the respective folders. Full keyed exact source-to-target row comparisons are not implemented for these 11 tables; decide scope and implement before claiming full row equality.
5. Complete `docs/validation/00_project_wide/VALIDATION_SIGNOFF_TEMPLATE.md` only after reconciling evidence.

## Documentation/security maintenance

- `README_START_HERE.md` says Events reconciliation not yet run, but the archive includes a historical PASS JSON report: reconcile chronology and attach evidence.
- `.gitignore` does not explicitly ignore `.venv-dbt/`, used in the current setup. Add it.
- Uploaded ZIP contains `infra/environments/dev/.env.dev` with credential-valued keys. Do not publish/distribute that file; rotate credentials if real/reused/exposed. `.gitignore` already includes `.env.*` but does not sanitize manually created ZIPs.
- API returns are mocked/simulated by the project, so source validation does not independently attest an external real API.
- No dbt project or SQL Server database contents were included in the ZIP. Environment uses `dbt Core 1.12.6` + `dbt-sqlserver 1.12.1` per user's locally verified output; not part of the archive.
