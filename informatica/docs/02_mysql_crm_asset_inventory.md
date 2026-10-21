# Informatica CDI — MySQL CRM Asset Inventory

**Project:** Commerce Analytics Platform\
**Informatica location:** `Default / 02_MYSQL_CRM_INGESTION`\
**Inventory captured:** 2026-10-18\
**Evidence:** Five initial user screenshots showing all `22` assets, plus a later refreshed Explore screenshot on 2026-10-18 confirming the CRM Customers Mapping and Mapping Task now show `Valid`.\
**Purpose:** As-built **inventory**, not an export and not an importable backup. The list alone does not prove the internal transformation logic, connectivity, or current runtime readiness.

## 1. Inventory summary

| Asset type | Total | Valid | Invalid |
|---|---:|---:|---:|
| Taskflow | 6 | 6 | 0 |
| Mapping Task | 8 | 8 | 0 |
| Mapping | 8 | 8 | 0 |
| **Total** | **22** | **22** | **0** |

**Status history:** An earlier Explore capture displayed `m_bronze_mysql_crm_customers` as **Invalid** (Oct 16, 2026, 12:57 PM). A refreshed Explore screenshot on 2026-10-18 shows it as **Valid**, updated Oct 17, 2026, 5:50 PM; `mt_bronze_mysql_crm_customers` also displays **Valid**, updated at the same time. This documents current *design validity*, not a new runtime test. The specific cause of the earlier Invalid state is not independently established.

## 2. Full asset inventory

The timestamps are copied as displayed in Informatica Explore, rather than normalized to UTC.

| # | Asset name | Asset type | Updated on (UI) | Status (UI) |
|---:|---|---|---|---|
| 1 | `tf_bronze_mysql_crm_customers_audit` | Taskflow | Oct 16, 2026, 12:59 PM | Valid |
| 2 | `m_bronze_mysql_crm_customers` | Mapping | Oct 17, 2026, 5:50 PM | Valid |
| 3 | `tf_bronze_mysql_crm_support_tickets_audit` | Taskflow | Oct 14, 2026, 8:39 AM | Valid |
| 4 | `tf_bronze_mysql_crm_campaign_memberships_audit` | Taskflow | Oct 14, 2026, 8:33 AM | Valid |
| 5 | `tf_bronze_mysql_crm_campaigns_audit` | Taskflow | Oct 14, 2026, 8:21 AM | Valid |
| 6 | `tf_bronze_mysql_crm_loyalty_transactions_audit` | Taskflow | Oct 14, 2026, 8:14 AM | Valid |
| 7 | `tf_bronze_mysql_crm_loyalty_accounts_audit` | Taskflow | Oct 14, 2026, 8:07 AM | Valid |
| 8 | `mt_bronze_mysql_crm_support_tickets` | Mapping Task | Oct 14, 2026, 7:50 AM | Valid |
| 9 | `mt_bronze_mysql_crm_campaign_memberships` | Mapping Task | Oct 14, 2026, 7:49 AM | Valid |
| 10 | `mt_bronze_mysql_crm_campaigns` | Mapping Task | Oct 14, 2026, 7:48 AM | Valid |
| 11 | `mt_bronze_mysql_crm_loyalty_transactions` | Mapping Task | Oct 14, 2026, 7:47 AM | Valid |
| 12 | `mt_bronze_mysql_crm_loyalty_accounts` | Mapping Task | Oct 14, 2026, 7:46 AM | Valid |
| 13 | `m_bronze_mysql_crm_support_tickets` | Mapping | Oct 14, 2026, 7:41 AM | Valid |
| 14 | `m_bronze_mysql_crm_campaign_memberships` | Mapping | Oct 14, 2026, 7:38 AM | Valid |
| 15 | `m_bronze_mysql_crm_campaigns` | Mapping | Oct 14, 2026, 7:36 AM | Valid |
| 16 | `m_bronze_mysql_crm_loyalty_transactions` | Mapping | Oct 14, 2026, 7:32 AM | Valid |
| 17 | `m_bronze_mysql_crm_loyalty_accounts` | Mapping | Oct 14, 2026, 7:27 AM | Valid |
| 18 | `mt_bronze_mysql_crm_customers` | Mapping Task | Oct 17, 2026, 5:50 PM | Valid |
| 19 | `mt_control_audit_start` | Mapping Task | Oct 13, 2026, 11:27 AM | Valid |
| 20 | `mt_control_audit_finish` | Mapping Task | Oct 13, 2026, 10:57 AM | Valid |
| 21 | `m_control_audit_finish` | Mapping | Oct 13, 2026, 10:26 AM | Valid |
| 22 | `m_control_audit_start` | Mapping | Oct 13, 2026, 10:26 AM | Valid |

## 3. Expected target coverage

These target names and initial-load row expectations come from the project's documented warehouse inventory; the Explore screenshots alone cannot verify runtime source-to-target wiring.

| Business object | Mapping | Mapping Task | Taskflow | Expected initial rows |
|---|---|---|---|---:|
| CRM customers | `m_bronze_mysql_crm_customers` | `mt_bronze_mysql_crm_customers` | `tf_bronze_mysql_crm_customers_audit` | 50,000 |
| Loyalty accounts | `m_bronze_mysql_crm_loyalty_accounts` | `mt_bronze_mysql_crm_loyalty_accounts` | `tf_bronze_mysql_crm_loyalty_accounts_audit` | 35,000 |
| Loyalty transactions | `m_bronze_mysql_crm_loyalty_transactions` | `mt_bronze_mysql_crm_loyalty_transactions` | `tf_bronze_mysql_crm_loyalty_transactions_audit` | 175,000 |
| Campaigns | `m_bronze_mysql_crm_campaigns` | `mt_bronze_mysql_crm_campaigns` | `tf_bronze_mysql_crm_campaigns_audit` | 120 |
| Campaign memberships | `m_bronze_mysql_crm_campaign_memberships` | `mt_bronze_mysql_crm_campaign_memberships` | `tf_bronze_mysql_crm_campaign_memberships_audit` | 360,000 |
| Support tickets | `m_bronze_mysql_crm_support_tickets` | `mt_bronze_mysql_crm_support_tickets` | `tf_bronze_mysql_crm_support_tickets_audit` | 45,000 |
| **Total** | | | | **665,120** |

The naming convention strongly suggests `Taskflow → Mapping Task → Mapping`, with shared audit tasks. **Confirm actual dependencies in the Taskflow and Mapping Task designers before declaring lineage verified.**

## 4. Audit assets

| Function | Mapping | Mapping Task | Target / role |
|---|---|---|---|
| Start audit | `m_control_audit_start` | `mt_control_audit_start` | Start a `control.etl_run_log` execution entry (subject to designer confirmation). |
| Finish audit | `m_control_audit_finish` | `mt_control_audit_finish` | Finalize audit execution status and row count (subject to designer confirmation). |

**Previously observed execution evidence, separate from this UI asset inventory:** the CRM Customers taskflow succeeded on 2026-10-16; `control.etl_run_log` `run_id=19` recorded `SUCCESS` and 50,000 processed rows. An isolated audit-finish test recorded an intentional `FAILED` status in `run_id=18`. Historical `run_id=3,8,9` remain subject to reconciliation. Those runtime observations predate the refreshed status screenshot and **do not** establish that the updated design has been re-executed successfully or that its failure path has been tested.

## 5. Open checks and decisions

| ID | Check / action | State |
|---|---|---|
| CRM-01 | Check the current Explore design validation status for `m_bronze_mysql_crm_customers`. Prior `Invalid` observation retained as status history; precise original cause not established. | **CLOSED — Valid in refreshed UI** |
| CRM-02 | Confirm actual Taskflow → Mapping Task → Mapping dependencies and source/target connections for all six CRM loads. | OPEN |
| CRM-03 | Capture the success and custom-error branches for CRM Customers, including the audit finish inputs; integrated failure path remains unverified. | OPEN |
| CRM-04 | Reconcile historical audit runs `3`, `8`, `9` based on actual run/subtask evidence; do not blindly update statuses. | OPEN |
| CRM-05 | Complete source-to-target data validation for the six CRM targets (counts alone are not exact row equality). | OPEN |
| CRM-06 | Determine whether tenant permissions/subscription allow official asset export; otherwise retain this as design-only documentation. | BLOCKED / NOT CONFIRMED |

## 6. Safe documentation practice

- Do not click **Run**, **Publish**, or **Save** simply to document the current design-validation status.
- Do not expose connection passwords, tokens, Secure Agent secrets, or credential-valued configuration in screenshots or repository files.
- If the tenant permits official export later, store the export separately, review it for secrets, and document version/creation date.
- Keep the as-built inventory separate from actual validated deployable assets and from current run evidence.

**Inventory verdict:** `COMPLETE_AS_LIST (22/22)`; `UI_DESIGN_STATUS_VALID (22/22)`; `DEPENDENCY_AND_RUNTIME_VERIFICATION_PENDING`; `DEPLOYABLE_EXPORT_NOT_AVAILABLE_IN_UI`.
