# Informatica Asset Inventory — PostgreSQL OLTP Ingestion

**Platform:** Informatica Cloud Data Integration (CDI)\
**Folder:** `Default / 01_POSTGRESQL_OLTP_INGESTION`\
**Captured:** 2026-10-18 (from five user-provided Explore screenshots)\
**Evidence type:** Manual UI inventory; **not** a native importable Informatica export.\
**Observed inventory:** **23 objects: 5 Taskflows, 10 Mapping Tasks, 8 Mappings.** All displayed **Valid** in Explore.

## Inventory — exact names and displayed statuses

| # | Asset name | Type | Updated on (UI) | Status |
|---:|---|---|---|---|
| 1 | `tf_bronze_pg_orders_audit_v2` | Taskflow | 2026-10-12 12:30 PM | Valid |
| 2 | `tf_bronze_pg_products_audit` | Taskflow | 2026-10-12 12:14 PM | Valid |
| 3 | `tf_bronze_pg_customers_audit` | Taskflow | 2026-10-12 11:50 AM | Valid |
| 4 | `tf_bronze_pg_order_items_audit` | Taskflow | 2026-10-12 11:18 AM | Valid |
| 5 | `m_control_audit_finish` | Mapping | 2026-10-11 11:07 AM | Valid |
| 6 | `mt_control_audit_finish` | Mapping Task | 2026-10-11 11:07 AM | Valid |
| 7 | `m_control_audit_start` | Mapping | 2026-10-11 10:29 AM | Valid |
| 8 | `mt_control_audit_start_payments` | Mapping Task | 2026-10-11 10:29 AM | Valid |
| 9 | `mt_control_audit_start` | Mapping Task | 2026-10-11 10:29 AM | Valid |
| 10 | `mt_control_audit_start_order_items` | Mapping Task | 2026-10-11 10:29 AM | Valid |
| 11 | `mt_bronze_pg_orders_initial` | Mapping Task | 2026-10-11 7:52 AM | Valid |
| 12 | `tf_bronze_pg_payments_audit` | Taskflow | 2026-10-10 5:43 PM | Valid |
| 13 | `m_bronze_pg_orders_initial` | Mapping | 2026-10-10 1:36 PM | Valid |
| 14 | `mt_bronze_pg_products_initial` | Mapping Task | 2026-10-09 1:57 PM | Valid |
| 15 | `mt_bronze_pg_payments_initial` | Mapping Task | 2026-10-09 1:57 PM | Valid |
| 16 | `mt_bronze_pg_order_items_initial` | Mapping Task | 2026-10-09 1:56 PM | Valid |
| 17 | `m_bronze_pg_products_initial` | Mapping | 2026-10-09 1:51 PM | Valid |
| 18 | `m_bronze_pg_payments_initial` | Mapping | 2026-10-09 1:50 PM | Valid |
| 19 | `m_bronze_pg_order_items_initial` | Mapping | 2026-10-09 1:44 PM | Valid |
| 20 | `mt_bronze_pg_customers_initial` | Mapping Task | 2026-10-09 1:10 PM | Valid |
| 21 | `m_bronze_pg_customers_initial` | Mapping | 2026-10-09 1:08 PM | Valid |
| 22 | `mt_preflight_pg_to_sqlserver` | Mapping Task | 2026-10-08 4:01 AM | Valid |
| 23 | `m_preflight_pg_read` | Mapping | 2026-10-08 3:57 AM | Valid |

*Times are transcribed from the Informatica UI; its timezone was not identified. Screenshot sets had overlapping rows, which are listed only once here.*

## Expected object groupings — names only

| Pipeline | Mapping | Mapping Task | Taskflow |
|---|---|---|---|
| Orders | `m_bronze_pg_orders_initial` | `mt_bronze_pg_orders_initial` | `tf_bronze_pg_orders_audit_v2` |
| Order items | `m_bronze_pg_order_items_initial` | `mt_bronze_pg_order_items_initial` | `tf_bronze_pg_order_items_audit` |
| Customers | `m_bronze_pg_customers_initial` | `mt_bronze_pg_customers_initial` | `tf_bronze_pg_customers_audit` |
| Products | `m_bronze_pg_products_initial` | `mt_bronze_pg_products_initial` | `tf_bronze_pg_products_audit` |
| Payments | `m_bronze_pg_payments_initial` | `mt_bronze_pg_payments_initial` | `tf_bronze_pg_payments_audit` |

The groupings above are **name-based hypotheses** pending inspection of each Taskflow's actual task references. Do not describe them as verified dependency edges until checked.

## Additional assets

- Preflight: `m_preflight_pg_read`, `mt_preflight_pg_to_sqlserver`.
- Audit base mappings: `m_control_audit_start`, `m_control_audit_finish`.
- Audit mapping tasks: `mt_control_audit_start`, `mt_control_audit_start_payments`, `mt_control_audit_start_order_items`, `mt_control_audit_finish`.
- Similar audit names also appear in the MySQL CRM folder. They are separate listed objects; shared behavior/configuration has **not** been established from these screenshots.

## Verification status and limitations

- **PASS (UI inventory):** All 23 assets are listed and show `Valid` in Informatica Explore.
- **NOT VERIFIED:** Runtime success for every asset, mapping task parameterization, source-to-target field mapping, dependency graph, failure-path behavior, and repeatability.
- **NOT EXPORTED:** No native XML/ZIP asset export was provided. This inventory documents the UI state, not a re-importable backup.
- **Audit investigation pending:** Earlier `control.etl_run_log` rows for PostgreSQL order items may require historic run reconciliation; design Valid status does not close audit exceptions.

## Next documentation work

1. Capture inventories for Shipping, Returns, and Application Events folders.
2. Document taskflow decision paths, start/finish audit parameter bindings, connections without secrets, and dependency relationships using screenshots or permitted exports.
3. Link validated run IDs and read-only SQL validation evidence from `docs/validation/`.
4. Sanitize all materials before a future Git commit: no passwords, access tokens, private connection details, or personal data samples.
