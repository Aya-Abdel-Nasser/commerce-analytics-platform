# Project 2 — Bronze Ingestion Validation Sign-off

**Environment:** SQL Server Express `commerce_warehouse_dev`, Informatica CDI, local initial snapshots

**Execution date:** `________`   **Reviewer:** `________`   **Evidence folder:** `docs/validation/reports/`

| Source | Expected rows | Source validation | Target validation | Exact row reconciliation | Audit | Evidence / run ID |
|---|---:|---|---|---|---|---|
| PostgreSQL OLTP | 968,000 | NOT RUN (this signoff) | NOT RUN (this signoff) | NOT IMPLEMENTED | Ingestion confirmed | __________ |
| MySQL CRM | 665,120 | NOT RUN (this signoff) | NOT RUN (this signoff) | NOT IMPLEMENTED | Ingestion confirmed | __________ |
| Shipping CSV | 120,000 | Previous source scan PASS | Previous counts/distributions PASS | NOT RUN | SUCCESS, 15 | __________ |
| Returns API | 22,093 | PASS | PASS | **PASS** (22,093 exact JSON texts) | SUCCESS, 16 | __________ |
| Application Events | 1,630,000 | NOT RUN | NOT RUN | NOT RUN | Taskflow 3/3 SUCCESS | __________ |
| **Expected aggregate** | **3,405,213** | | | | | |

**Audit follow-up:** historical CRM attempts `run_id` 8 and 9 showed `RUNNING` with NULL `end_time` in earlier history; assess separately before formal platform handover. Do not update historical records without verifying original run outcomes.

**Closeout criteria:** Confirm all 14 target tables present and expected row counts, source snapshots profiled, data-quality checks clean, relevant latest audits successful, exact Returns/Shipping/Events source→target reports saved; document whether full-row PG/MySQL comparison is required or explicitly deferred with owner and due date.

**Open defects:** __________________

**Result:** `[ ] PASS` `[ ] FAIL` `[ ] PARTIAL / PENDING`
