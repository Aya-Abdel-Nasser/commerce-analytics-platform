#!/usr/bin/env python3
"""Read-only, full keyed PostgreSQL OLTP -> SQL Server Bronze reconciliation.

Run from the commerce-analytics-platform repository root:
    python docs/validation/01_postgresql_oltp/04_reconcile_SOURCE_TARGET_postgresql_oltp.py --table products
    python docs/validation/01_postgresql_oltp/04_reconcile_SOURCE_TARGET_postgresql_oltp.py

Install once: python -m pip install "psycopg2-binary>=2.9,<3" pyodbc

Source: PostgreSQL commerce_oltp_dev, schema commerce; connection settings are read
from the local infra/environments/dev/.env.dev (NOT copied into the report).
Target: SQL Server .\\SQLEXPRESS, commerce_warehouse_dev, schema bronze.

Reads every PostgreSQL column of every row, matches records by the source PK,
and compares them with corresponding SQL Server values. '_ingested_at_utc'
is a warehouse-added lineage column, so it is excluded from value equality.
TIMESTAMPTZ is converted to UTC before comparison with SQL Server DATETIME2;
this assumes the target preserves UTC wall-clock timestamps. Differences FAIL.

The script executes SELECTs only against permanent database tables; source
transaction is REPEATABLE READ, READ ONLY. Do not modify either dataset while
this cross-database validation runs. No raw values, names or passwords are
written to the report.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
from decimal import Decimal
from getpass import getpass
import json
import os
from pathlib import Path
import re
import sys
from typing import Any


# Actual PostgreSQL source primary keys, verified from source constraints.
TABLES: dict[str, dict[str, Any]] = {
    "customers": {"target": "oltp_customers", "pk": ("customer_id",), "expected": 50_000},
    "order_items": {"target": "oltp_order_items", "pk": ("order_item_id",), "expected": 500_000},
    "orders": {"target": "oltp_orders", "pk": ("order_id",), "expected": 200_000},
    "payments": {"target": "oltp_payments", "pk": ("payment_id",), "expected": 215_000},
    "products": {"target": "oltp_products", "pk": ("product_id",), "expected": 3_000},
}
EXTRA_TARGET_COLUMNS = {"_ingested_at_utc"}
TYPE_MAP = {
    "bigint": {"bigint"},
    "integer": {"bigint", "int"},
    "numeric": {"decimal", "numeric"},
    "character varying": {"nvarchar"},
    "timestamp with time zone": {"datetime2"},
}
IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class ReconciliationError(RuntimeError):
    pass


def qi(name: str, engine: str) -> str:
    if not IDENTIFIER.fullmatch(name):
        raise ReconciliationError(f"Unsupported {engine} identifier")
    return f'"{name}"' if engine == "postgres" else f"[{name}]"


def parse_local_env(path: Path) -> dict[str, str]:
    """Read only supported local env keys; never display or report secrets."""
    result: dict[str, str] = {}
    if not path.is_file():
        return result
    allowed = {"POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_HOST_PORT"}
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k in allowed:
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
                v = v[1:-1]
            result[k] = v
    return result


def normalized(value: Any) -> tuple[str, Any] | None:
    """Compare content, not driver-specific object types or timezone repr."""
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is not None:
            value = value.astimezone(timezone.utc).replace(tzinfo=None)
        return "utc_datetime", value.isoformat(timespec="microseconds")
    if isinstance(value, (int, Decimal, bool)):
        return "number", Decimal(int(value)) if isinstance(value, bool) else Decimal(value)
    if isinstance(value, str):
        return "text", value
    raise ReconciliationError(f"Unexpected datatype from driver: {type(value).__name__}")


def as_integral_key(value: Any) -> int:
    if value is None:
        raise ReconciliationError("NULL primary key encountered")
    try:
        number = Decimal(value)
    except Exception as exc:
        raise ReconciliationError("Non-numeric primary key encountered") from exc
    if not number.is_finite() or number != number.to_integral_value():
        raise ReconciliationError("Invalid non-integral primary key encountered")
    return int(number)


class OrderedStream:
    """Bounded fetch and strict increasing-PK validation."""

    def __init__(self, cursor: Any, batch_size: int, pk_positions: tuple[int, ...]):
        self.cursor = cursor
        self.batch_size = batch_size
        self.pk_positions = pk_positions
        self.buffer: list[Any] = []
        self.position = 0
        self.previous_key: tuple[int, ...] | None = None

    def next(self) -> tuple[tuple[int, ...], tuple[Any, ...]] | None:
        if self.position >= len(self.buffer):
            self.buffer = self.cursor.fetchmany(self.batch_size)
            self.position = 0
        if not self.buffer:
            return None
        row = tuple(self.buffer[self.position])
        self.position += 1
        key = tuple(as_integral_key(row[index]) for index in self.pk_positions)
        if self.previous_key is not None and key <= self.previous_key:
            raise ReconciliationError("Duplicate/unsorted primary key in stream")
        self.previous_key = key
        return key, row


def pg_metadata(conn: Any, table: str) -> list[tuple[Any, ...]]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name, data_type, datetime_precision, numeric_precision, "
            "numeric_scale FROM information_schema.columns "
            "WHERE table_schema=%s AND table_name=%s ORDER BY ordinal_position",
            ("commerce", table),
        )
        return list(cur.fetchall())


def sql_metadata(conn: Any, table: str) -> list[tuple[Any, ...]]:
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT COLUMN_NAME, DATA_TYPE, DATETIME_PRECISION, NUMERIC_PRECISION, "
            "NUMERIC_SCALE FROM INFORMATION_SCHEMA.COLUMNS "
            "WHERE TABLE_SCHEMA=? AND TABLE_NAME=? ORDER BY ORDINAL_POSITION",
            ("bronze", table),
        )
        return list(cur.fetchall())
    finally:
        cur.close()


def pg_primary_key(conn: Any, table: str) -> tuple[str, ...]:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT k.column_name FROM information_schema.table_constraints tc "
            "JOIN information_schema.key_column_usage k "
            "ON tc.constraint_catalog=k.constraint_catalog "
            "AND tc.constraint_schema=k.constraint_schema "
            "AND tc.constraint_name=k.constraint_name "
            "AND tc.table_schema=k.table_schema AND tc.table_name=k.table_name "
            "WHERE tc.table_schema=%s AND tc.table_name=%s "
            "AND tc.constraint_type='PRIMARY KEY' ORDER BY k.ordinal_position",
            ("commerce", table),
        )
        return tuple(str(r[0]) for r in cur.fetchall())


def verify_contract(pg_meta: list[tuple[Any, ...]], sql_meta: list[tuple[Any, ...]],
                    pk: tuple[str, ...], source_pk: tuple[str, ...]) -> list[str]:
    if source_pk != pk:
        raise ReconciliationError(f"Source primary key changed: expected {pk}, actual {source_pk}")
    src_cols = [str(row[0]) for row in pg_meta]
    dst_cols = [str(row[0]) for row in sql_meta]
    if not src_cols:
        raise ReconciliationError("No source columns found")
    if set(dst_cols) != set(src_cols) | EXTRA_TARGET_COLUMNS:
        raise ReconciliationError(
            f"Schema mismatch: source_only={sorted(set(src_cols)-set(dst_cols))}; "
            f"unexpected_target={sorted(set(dst_cols)-set(src_cols)-EXTRA_TARGET_COLUMNS)}; "
            f"missing_lineage={sorted(EXTRA_TARGET_COLUMNS-set(dst_cols))}"
        )
    dst_map = {str(r[0]): r for r in sql_meta}
    for src in pg_meta:
        name, pg_type, dt_precision, number_precision, number_scale = src
        name, pg_type = str(name), str(pg_type).lower()
        dest = dst_map[name]
        sql_type = str(dest[1]).lower()
        if sql_type not in TYPE_MAP.get(pg_type, set()):
            raise ReconciliationError(f"Unexpected type for {name}: {pg_type} -> {sql_type}")
        if pg_type == "timestamp with time zone":
            if int(dt_precision or 0) != 6 or int(dest[2] or 0) not in (6, 7):
                raise ReconciliationError(f"Timestamp precision contract changed for {name}")
        if pg_type == "numeric":
            if number_precision is None or number_scale is None:
                raise ReconciliationError(f"Unexpected unconstrained NUMERIC source: {name}")
            if dest[3] is None or dest[4] is None:
                raise ReconciliationError(f"Invalid target DECIMAL precision for {name}")
            if int(dest[3]) < int(number_precision) or int(dest[4]) != int(number_scale):
                raise ReconciliationError(f"Target decimal precision/scale risks loss for {name}")
        qi(name, "postgres")
        qi(name, "sqlserver")
    for key in pk:
        if key not in src_cols:
            raise ReconciliationError(f"Primary key column missing from metadata: {key}")
    return src_cols


def compare_streams(src_cursor: Any, dst_cursor: Any, cols: list[str], pk: tuple[str, ...],
                    batch_size: int, expected: int) -> dict[str, Any]:
    positions = tuple(cols.index(c) for c in pk)
    src = OrderedStream(src_cursor, batch_size, positions)
    dst = OrderedStream(dst_cursor, batch_size, positions)
    a, b = src.next(), dst.next()
    totals: dict[str, Any] = {
        "expected_rows": expected,
        "source_rows": 0,
        "target_rows": 0,
        "matched_primary_keys": 0,
        "missing_in_target": 0,
        "unexpected_in_target": 0,
        "rows_with_value_mismatches": 0,
        "value_mismatches_by_column": {},
    }
    mismatches: Counter[str] = Counter()
    last_progress = 0
    while a is not None or b is not None:
        if a is not None and (b is None or a[0] < b[0]):
            totals["source_rows"] += 1
            totals["missing_in_target"] += 1
            a = src.next()
        elif b is not None and (a is None or b[0] < a[0]):
            totals["target_rows"] += 1
            totals["unexpected_in_target"] += 1
            b = dst.next()
        else:
            assert a is not None and b is not None
            totals["source_rows"] += 1
            totals["target_rows"] += 1
            totals["matched_primary_keys"] += 1
            any_difference = False
            for i, col in enumerate(cols):
                if normalized(a[1][i]) != normalized(b[1][i]):
                    mismatches[col] += 1
                    any_difference = True
            if any_difference:
                totals["rows_with_value_mismatches"] += 1
            a, b = src.next(), dst.next()
        inspected = totals["source_rows"] + totals["unexpected_in_target"]
        if inspected // 100_000 > last_progress:
            last_progress = inspected // 100_000
            print(f"    {inspected:,} keys processed", flush=True)
    totals["value_mismatches_by_column"] = dict(sorted(mismatches.items()))
    totals["status"] = (
        "PASS" if totals["source_rows"] == expected and totals["target_rows"] == expected
        and totals["missing_in_target"] == 0 and totals["unexpected_in_target"] == 0
        and totals["rows_with_value_mismatches"] == 0 else "FAIL"
    )
    return totals


def check_table(pg_conn: Any, sql_conn: Any, name: str, spec: dict[str, Any], batch_size: int) -> dict[str, Any]:
    print(f"\n{name}: validating schema and primary keys...", flush=True)
    source_meta = pg_metadata(pg_conn, name)
    target_meta = sql_metadata(sql_conn, str(spec["target"]))
    cols = verify_contract(source_meta, target_meta, spec["pk"], pg_primary_key(pg_conn, name))
    print(f"  {len(cols)} source columns; streaming PostgreSQL/SQL Server", flush=True)
    pg_list = ", ".join(qi(c, "postgres") for c in cols)
    sql_list = ", ".join(qi(c, "sqlserver") for c in cols)
    pg_order = ", ".join(qi(c, "postgres") for c in spec["pk"])
    sql_order = ", ".join(qi(c, "sqlserver") for c in spec["pk"])
    pg_sql = f"SELECT {pg_list} FROM {qi('commerce', 'postgres')}.{qi(name, 'postgres')} ORDER BY {pg_order}"
    dest_sql = (
        f"SELECT {sql_list} FROM [bronze].{qi(spec['target'], 'sqlserver')} "
        f"ORDER BY {sql_order}"
    )
    pg_cur = pg_conn.cursor(name=f"rec_{name}")  # PostgreSQL server-side named cursor
    pg_cur.itersize = batch_size
    sql_cur = sql_conn.cursor()
    try:
        pg_cur.execute(pg_sql)
        sql_cur.execute(dest_sql)
        result = compare_streams(pg_cur, sql_cur, cols, spec["pk"], batch_size, spec["expected"])
    finally:
        pg_cur.close()
        sql_cur.close()
    result.update({
        "source_table": f"commerce.{name}",
        "target_table": f"bronze.{spec['target']}",
        "primary_key": list(spec["pk"]),
        "compared_source_columns": cols,
        "excluded_lineage_columns": sorted(EXTRA_TARGET_COLUMNS),
    })
    return result


def args_parser() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Full keyed PostgreSQL OLTP -> SQL Server Bronze comparison")
    p.add_argument("--table", choices=tuple(TABLES), help="Pilot: check one table first")
    p.add_argument("--env-file", default="infra/environments/dev/.env.dev")
    p.add_argument("--pg-host", default="127.0.0.1")
    p.add_argument("--pg-port", type=int, help="Overrides POSTGRES_HOST_PORT")
    p.add_argument("--pg-database", help="Overrides POSTGRES_DB")
    p.add_argument("--pg-user", help="Overrides POSTGRES_USER")
    p.add_argument("--sqlserver", default=r".\SQLEXPRESS")
    p.add_argument("--database", default="commerce_warehouse_dev")
    p.add_argument("--batch-size", type=int, default=2000)
    p.add_argument("--out", default="docs/validation/reports/01_POSTGRES_OLTP_FULL_RECONCILIATION.json")
    args = p.parse_args()
    if not 100 <= args.batch_size <= 20000:
        p.error("--batch-size must be between 100 and 20000")
    return args


def main() -> int:
    args = args_parser()
    try:
        import psycopg2
        import pyodbc
    except ImportError:
        print('Install missing packages: python -m pip install "psycopg2-binary>=2.9,<3" pyodbc', file=sys.stderr)
        return 2
    config = parse_local_env(Path(args.env_file))
    pg_user = args.pg_user or os.getenv("POSTGRES_USER") or config.get("POSTGRES_USER")
    pg_database = args.pg_database or os.getenv("POSTGRES_DB") or config.get("POSTGRES_DB", "commerce_oltp_dev")
    pg_port = args.pg_port or int(os.getenv("POSTGRES_HOST_PORT") or config.get("POSTGRES_HOST_PORT", "15432"))
    password = os.getenv("POSTGRES_PASSWORD") or config.get("POSTGRES_PASSWORD")
    if not pg_user:
        print("POSTGRES_USER not set; specify --pg-user or configure the local .env.dev", file=sys.stderr)
        return 2
    if password is None:
        password = getpass(f"PostgreSQL password for {pg_user} (hidden): ")

    selected = {args.table: TABLES[args.table]} if args.table else TABLES
    report: dict[str, Any] = {
        "report_type": "full_keyed_source_to_target_comparison",
        "executed_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "PostgreSQL OLTP initial snapshot",
        "pg_host": args.pg_host,
        "pg_port": pg_port,
        "pg_database": pg_database,
        "sqlserver_database": args.database,
        "source_timezone": "UTC",
        "sqlserver_datetime2_timezone_assumption": "UTC wall-clock",
        "raw_customer_values_logged": False,
        "table_results": [],
        "status": "ERROR",
    }
    pg_conn = None
    sql_conn = None
    try:
        pg_conn = psycopg2.connect(
            host=args.pg_host, port=pg_port, dbname=pg_database,
            user=pg_user, password=password, connect_timeout=15,
            options="-c timezone=UTC",
        )
        pg_conn.set_session(isolation_level="REPEATABLE READ", readonly=True, autocommit=False)
        sql_conn = pyodbc.connect(
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={args.sqlserver};DATABASE={args.database};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly;",
            autocommit=True, timeout=15,
        )
        for table, spec in selected.items():
            try:
                result = check_table(pg_conn, sql_conn, table, spec, args.batch_size)
                report["table_results"].append(result)
                print(
                    f"  {result['status']}: source={result['source_rows']:,}, "
                    f"target={result['target_rows']:,}, "
                    f"missing={result['missing_in_target']:,}, "
                    f"unexpected={result['unexpected_in_target']:,}, "
                    f"value_mismatch_rows={result['rows_with_value_mismatches']:,}",
                    flush=True,
                )
            except Exception as err:
                # No row values / credentials printed. Error type + table name only.
                report["table_results"].append({
                    "source_table": f"commerce.{table}", "status": "ERROR",
                    "error_type": type(err).__name__,
                })
                print(f"  ERROR in {table}: {type(err).__name__}; see schema and connectivity", file=sys.stderr)
                break
        report["status"] = (
            "PASS" if len(report["table_results"]) == len(selected)
            and all(r["status"] == "PASS" for r in report["table_results"])
            else "FAIL"
        )
    except Exception as err:
        report["status"] = "ERROR"
        report["error_type"] = type(err).__name__
        print(f"Database connection failed ({type(err).__name__}); check local env and ports.", file=sys.stderr)
    finally:
        if sql_conn is not None:
            sql_conn.close()
        if pg_conn is not None:
            try:
                pg_conn.rollback()  # End source read-only snapshot.
            finally:
                pg_conn.close()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nOVERALL: {report['status']} | Report: {out}", flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
