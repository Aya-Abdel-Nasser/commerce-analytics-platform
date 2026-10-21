#!/usr/bin/env python3
"""Full keyed MySQL CRM -> SQL Server Bronze initial-snapshot reconciliation.

Source contract: infra/sql/mysql/001_create_crm.sql
Target contract: infra/sql/sqlserver/001_warehouse_schema_snapshot.sql

This program performs SELECTs only. It does not write to either database. It
compares every source column of every row by MySQL primary key, using bounded
fetch batches. It outputs counts only, never raw field values or passwords.

Install: python -m pip install PyMySQL pyodbc
Run from the commerce-analytics-platform project root:
    python docs/validation/02_mysql_crm/05_reconcile_SOURCE_TARGET_mysql_crm.py

MySQL password: entered securely at the prompt (or environment MYSQL_PASSWORD).
Defaults: MySQL at 127.0.0.1:53306, user inf_mysql_reader;
          SQL Server .\\SQLEXPRESS via Windows integrated authentication.
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


# PRIMARY KEYs verified against live MySQL information_schema (18 Oct 2026).
# Counts are the project's fixed INITIAL SNAPSHOT baseline, not CDC targets.
TABLES: dict[str, dict[str, Any]] = {
    "crm_customers": {
        "target": "crm_customers", "keys": ("crm_customer_id",), "expected": 50_000
    },
    "loyalty_accounts": {
        "target": "crm_loyalty_accounts", "keys": ("loyalty_account_id",), "expected": 35_000
    },
    "loyalty_transactions": {
        "target": "crm_loyalty_transactions", "keys": ("loyalty_transaction_id",), "expected": 175_000
    },
    "campaigns": {
        "target": "crm_campaigns", "keys": ("campaign_id",), "expected": 120
    },
    "campaign_memberships": {
        "target": "crm_campaign_memberships", "keys": ("campaign_id", "crm_customer_id"), "expected": 360_000
    },
    "support_tickets": {
        "target": "crm_support_tickets", "keys": ("ticket_id",), "expected": 45_000
    },
}

# Explicit, deliberate cross-engine type equivalences from the two DDL files.
TYPE_EQUIVALENCES: dict[str, set[str]] = {
    "bigint": {"decimal"},        # MySQL unsigned 64-bit -> SQL DECIMAL(20,0)
    "varchar": {"nvarchar"},     # utf8mb4 text -> SQL Unicode text
    "datetime": {"datetime2"},  # microseconds retained
    "int": {"int"},
    "tinyint": {"smallint"},     # MySQL BOOLEAN is TINYINT(1)
}

IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class ReconciliationError(Exception):
    """Contract or ordering violation; cannot certify a full comparison."""


def identifier(name: str, engine: str) -> str:
    """Only metadata-derived, unambiguous identifiers are permitted in SQL."""
    if not IDENTIFIER.fullmatch(name):
        raise ReconciliationError(f"Unsupported {engine} identifier: {name!r}")
    if engine == "mysql":
        return f"`{name}`"
    return f"[{name}]"


def normalize(value: Any) -> Any:
    """Equality of values rather than equality of driver-specific Python types.

    We intentionally DO NOT trim strings, round datetimes, coerce NULL to an
    empty string, or use database collations: these could hide ingestion errors.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is not None:
            raise ReconciliationError("Unexpected timezone-aware datetime")
        return ("datetime", value.isoformat(timespec="microseconds"))
    if isinstance(value, (Decimal, bool, int)):
        return ("number", Decimal(int(value)) if isinstance(value, bool) else Decimal(value))
    if isinstance(value, str):
        return ("string", value)
    raise ReconciliationError(
        f"Unexpected driver value type: {type(value).__name__}; "
        "review the data contract before adding a conversion"
    )


def key_from_row(row: tuple[Any, ...], key_indices: tuple[int, ...]) -> tuple[int, ...]:
    pieces = [row[index] for index in key_indices]
    if any(piece is None for piece in pieces):
        raise ReconciliationError("Encountered NULL within a primary key")
    # All six source primary keys are MySQL BIGINT UNSIGNED, including composite.
    result = []
    for piece in pieces:
        numeric = Decimal(piece)
        if numeric != numeric.to_integral_value():
            raise ReconciliationError("Non-integral primary key value")
        result.append(int(numeric))
    return tuple(result)


class BoundedRows:
    """Forward-only cursor reader; at most batch_size fetched rows retained."""

    def __init__(self, cursor: Any, batch_size: int):
        self.cursor = cursor
        self.batch_size = batch_size
        self.batch: list[tuple[Any, ...]] = []
        self.position = 0
        self.previous_key: tuple[int, ...] | None = None

    def next(self, key_indices: tuple[int, ...]) -> tuple[tuple[int, ...], tuple[Any, ...]] | None:
        if self.position >= len(self.batch):
            self.batch = self.cursor.fetchmany(self.batch_size)
            self.position = 0
        if not self.batch:
            return None
        row = tuple(self.batch[self.position])
        self.position += 1
        key = key_from_row(row, key_indices)
        if self.previous_key is not None and key <= self.previous_key:
            raise ReconciliationError(
                "Duplicate or unsorted primary key encountered while streaming; "
                "comparison cannot be certified"
            )
        self.previous_key = key
        return key, row


def mysql_columns(conn: Any, table: str) -> list[tuple[str, str, Any, Any, Any]]:
    with conn.cursor() as c:
        c.execute(
            "SELECT COLUMN_NAME, DATA_TYPE, DATETIME_PRECISION, NUMERIC_PRECISION, "
            "NUMERIC_SCALE FROM information_schema.COLUMNS "
            "WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s ORDER BY ORDINAL_POSITION",
            ("commerce_crm_dev", table),
        )
        return list(c.fetchall())


def sqlserver_columns(conn: Any, table: str) -> list[tuple[str, str, Any, Any, Any]]:
    c = conn.cursor()
    try:
        c.execute(
            "SELECT COLUMN_NAME, DATA_TYPE, DATETIME_PRECISION, NUMERIC_PRECISION, "
            "NUMERIC_SCALE FROM INFORMATION_SCHEMA.COLUMNS "
            "WHERE TABLE_SCHEMA=? AND TABLE_NAME=? ORDER BY ORDINAL_POSITION",
            ("bronze", table),
        )
        return list(c.fetchall())
    finally:
        c.close()


def mysql_primary_key(conn: Any, table: str) -> tuple[str, ...]:
    with conn.cursor() as c:
        c.execute(
            "SELECT k.COLUMN_NAME FROM information_schema.TABLE_CONSTRAINTS tc "
            "JOIN information_schema.KEY_COLUMN_USAGE k "
            "ON tc.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA "
            "AND tc.TABLE_SCHEMA=k.TABLE_SCHEMA "
            "AND tc.TABLE_NAME=k.TABLE_NAME "
            "AND tc.CONSTRAINT_NAME=k.CONSTRAINT_NAME "
            "WHERE tc.TABLE_SCHEMA=%s AND tc.TABLE_NAME=%s "
            "AND tc.CONSTRAINT_TYPE='PRIMARY KEY' ORDER BY k.ORDINAL_POSITION",
            ("commerce_crm_dev", table),
        )
        return tuple(r[0] for r in c.fetchall())


def verify_contract(
    source_meta: list[tuple[str, str, Any, Any, Any]],
    target_meta: list[tuple[str, str, Any, Any, Any]],
    actual_keys: tuple[str, ...],
    expected_keys: tuple[str, ...],
) -> list[str]:
    """Abort if some source column would be silently excluded or misinterpreted."""
    if actual_keys != expected_keys:
        raise ReconciliationError(
            f"MySQL PK changed: expected {expected_keys}, observed {actual_keys}"
        )
    source_names = [str(row[0]) for row in source_meta]
    target_names = [str(row[0]) for row in target_meta]
    if not source_names or set(source_names) != set(target_names):
        raise ReconciliationError(
            f"Column-set mismatch; source-only={sorted(set(source_names)-set(target_names))}; "
            f"target-only={sorted(set(target_names)-set(source_names))}"
        )
    target_types = {str(row[0]): row for row in target_meta}
    for source in source_meta:
        col, mysql_type, mysql_dt_precision, _, _ = source
        sql = target_types[str(col)]
        sql_type = str(sql[1]).lower()
        mysql_type = str(mysql_type).lower()
        if sql_type not in TYPE_EQUIVALENCES.get(mysql_type, set()):
            raise ReconciliationError(
                f"Unsupported type mapping {col}: MySQL {mysql_type} -> SQL Server {sql_type}"
            )
        if mysql_type == "datetime":
            if int(mysql_dt_precision or 0) != 6 or int(sql[2] or 0) != 6:
                raise ReconciliationError(f"Datetime precision is not 6 in both engines: {col}")
        if mysql_type == "bigint":
            if int(sql[3] or 0) != 20 or int(sql[4] or 0) != 0:
                raise ReconciliationError(f"Expected DECIMAL(20,0) for unsigned MySQL BIGINT: {col}")
        identifier(str(col), "mysql")
        identifier(str(col), "sqlserver")
    return source_names


def append_sample(samples: list[dict[str, Any]], kind: str, key: tuple[int, ...], enabled: bool) -> None:
    if enabled and len(samples) < 5:
        # Business columns / customer names are NEVER placed in reports.
        samples.append({"issue": kind, "primary_key": list(key)})


def compare_rows(
    mysql_rows: Any,
    sqlserver_rows: Any,
    columns: list[str],
    keys: tuple[str, ...],
    batch_size: int,
    include_key_samples: bool,
    expected: int,
) -> dict[str, Any]:
    """Merge two PK-ordered streams and compare all selected columns exactly."""
    key_indices = tuple(columns.index(col) for col in keys)
    src_stream = BoundedRows(mysql_rows, batch_size)
    dst_stream = BoundedRows(sqlserver_rows, batch_size)
    src = src_stream.next(key_indices)
    dst = dst_stream.next(key_indices)

    result: dict[str, Any] = {
        "expected_source_snapshot_rows": expected,
        "source_rows": 0,
        "target_rows": 0,
        "matched_primary_keys": 0,
        "missing_in_target": 0,
        "unexpected_in_target": 0,
        "rows_with_value_mismatches": 0,
        "value_mismatches_by_column": {},
        "sample_keys": [],
    }
    mismatches: Counter[str] = Counter()
    while src is not None or dst is not None:
        if src is not None and (dst is None or src[0] < dst[0]):
            result["source_rows"] += 1
            result["missing_in_target"] += 1
            append_sample(result["sample_keys"], "missing_in_target", src[0], include_key_samples)
            src = src_stream.next(key_indices)
        elif dst is not None and (src is None or dst[0] < src[0]):
            result["target_rows"] += 1
            result["unexpected_in_target"] += 1
            append_sample(result["sample_keys"], "unexpected_in_target", dst[0], include_key_samples)
            dst = dst_stream.next(key_indices)
        else:
            assert src is not None and dst is not None
            result["source_rows"] += 1
            result["target_rows"] += 1
            result["matched_primary_keys"] += 1
            mismatch_found = False
            for i, col in enumerate(columns):
                if normalize(src[1][i]) != normalize(dst[1][i]):
                    mismatches[col] += 1
                    mismatch_found = True
            if mismatch_found:
                result["rows_with_value_mismatches"] += 1
                append_sample(result["sample_keys"], "value_mismatch", src[0], include_key_samples)
            src = src_stream.next(key_indices)
            dst = dst_stream.next(key_indices)
        inspected = result["source_rows"] + result["unexpected_in_target"]
        if inspected and inspected % 100_000 == 0:
            print(f"    {inspected:,} keys processed", flush=True)

    result["value_mismatches_by_column"] = dict(sorted(mismatches.items()))
    result["status"] = (
        "PASS"
        if result["source_rows"] == expected
        and result["target_rows"] == expected
        and result["missing_in_target"] == 0
        and result["unexpected_in_target"] == 0
        and result["rows_with_value_mismatches"] == 0
        else "FAIL"
    )
    return result


def validate_table(mysql_conn: Any, sql_conn: Any, name: str, spec: dict[str, Any], args: Any) -> dict[str, Any]:
    print(f"\n{name}: validating schema and primary keys...", flush=True)
    src_meta = mysql_columns(mysql_conn, name)
    dst_meta = sqlserver_columns(sql_conn, spec["target"])
    keys = spec["keys"]
    columns = verify_contract(src_meta, dst_meta, mysql_primary_key(mysql_conn, name), keys)
    print(f"  {len(columns)} columns; streaming source and target (no raw data export)", flush=True)

    # SELECT columns are explicitly derived from validated metadata, not user input.
    src_cols = ", ".join(identifier(c, "mysql") for c in columns)
    dst_cols = ", ".join(identifier(c, "sqlserver") for c in columns)
    src_order = ", ".join(identifier(k, "mysql") for k in keys)
    dst_order = ", ".join(identifier(k, "sqlserver") for k in keys)
    src_sql = f"SELECT {src_cols} FROM {identifier(name, 'mysql')} ORDER BY {src_order}"
    dst_sql = (
        f"SELECT {dst_cols} FROM [bronze].{identifier(spec['target'], 'sqlserver')} "
        f"ORDER BY {dst_order}"
    )

    import pymysql
    src_cursor = mysql_conn.cursor(pymysql.cursors.SSCursor)
    dst_cursor = sql_conn.cursor()
    try:
        src_cursor.execute(src_sql)
        dst_cursor.execute(dst_sql)
        result = compare_rows(
            src_cursor, dst_cursor, columns, keys, args.batch_size,
            args.include_key_samples, spec["expected"],
        )
    finally:
        # Always close both cursors, even when a comparison raises an error.
        src_cursor.close()
        dst_cursor.close()
    result.update({
        "source_table": f"commerce_crm_dev.{name}",
        "target_table": f"bronze.{spec['target']}",
        "primary_key": list(keys),
        "compared_columns": columns,
    })
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mysql-host", default="127.0.0.1")
    parser.add_argument("--mysql-port", type=int, default=53306)
    parser.add_argument("--mysql-user", default=os.getenv("MYSQL_USER", "inf_mysql_reader"))
    parser.add_argument("--sqlserver", default=r".\SQLEXPRESS")
    parser.add_argument("--database", default="commerce_warehouse_dev")
    parser.add_argument("--table", choices=tuple(TABLES), help="Optional pilot: check one table first")
    parser.add_argument("--batch-size", type=int, default=2000)
    parser.add_argument("--include-key-samples", action="store_true", help="Local-only report: up to 5 primary keys, never raw values")
    parser.add_argument("--out", default="docs/validation/reports/02_MYSQL_CRM_FULL_RECONCILIATION.json")
    args = parser.parse_args()
    if not (100 <= args.batch_size <= 20000):
        parser.error("--batch-size must be between 100 and 20000")
    return args


def main() -> int:
    args = parse_args()
    try:
        import pymysql
        import pyodbc
    except ImportError as e:
        print(f"Missing Python package: {e}. Install with: python -m pip install PyMySQL pyodbc", file=sys.stderr)
        return 2
    password = os.getenv("MYSQL_PASSWORD")
    if password is None:
        password = getpass(f"MySQL password for {args.mysql_user} (input hidden): ")

    report: dict[str, Any] = {
        "report_type": "full_keyed_source_to_target_comparison",
        "executed_at_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "MySQL CRM initial snapshot",
        "mysql_host": args.mysql_host,
        "mysql_port": args.mysql_port,
        "sqlserver_instance": args.sqlserver,
        "sqlserver_database": args.database,
        "raw_source_values_logged": False,
        "table_results": [],
        "status": "ERROR",
    }
    mysql_conn = None
    sql_conn = None
    try:
        mysql_conn = pymysql.connect(
            host=args.mysql_host, port=args.mysql_port, user=args.mysql_user,
            password=password, database="commerce_crm_dev", charset="utf8mb4",
            autocommit=True, connect_timeout=15, read_timeout=300,
        )
        # A consistent, read-only InnoDB source snapshot. Keep source static and
        # do not load/modify SQL Server Bronze during the cross-engine comparison.
        with mysql_conn.cursor() as c:
            c.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            c.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY")

        conn_string = (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={args.sqlserver};DATABASE={args.database};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;"
            "ApplicationIntent=ReadOnly;"
        )
        sql_conn = pyodbc.connect(conn_string, autocommit=True, timeout=15)
        selected = {args.table: TABLES[args.table]} if args.table else TABLES
        for name, spec in selected.items():
            try:
                result = validate_table(mysql_conn, sql_conn, name, spec, args)
            except Exception as err:
                report["table_results"].append({
                    "source_table": name, "status": "ERROR",
                    "error": f"{type(err).__name__}: {err}"
                })
                print(f"  ERROR: {type(err).__name__}: {err}", file=sys.stderr)
                break
            report["table_results"].append(result)
            print(
                f"  {result['status']}: source={result['source_rows']:,}, "
                f"target={result['target_rows']:,}, "
                f"missing={result['missing_in_target']:,}, "
                f"unexpected={result['unexpected_in_target']:,}, "
                f"value_mismatch_rows={result['rows_with_value_mismatches']:,}",
                flush=True,
            )
        report["status"] = (
            "PASS" if len(report["table_results"]) == len(selected)
            and all(r["status"] == "PASS" for r in report["table_results"])
            else "FAIL"
        )
    except Exception as err:
        # Avoid printing connection strings or credentials from driver exceptions.
        report["status"] = "ERROR"
        report["error_type"] = type(err).__name__
        print(f"Database connection or transaction failed ({type(err).__name__}). "
              "Check server/port/account and read-only permissions.", file=sys.stderr)
    finally:
        if sql_conn is not None:
            sql_conn.close()
        if mysql_conn is not None:
            try:
                mysql_conn.rollback()  # End the read-only snapshot.
            finally:
                mysql_conn.close()

    # Reports contain aggregate results only (except keys if specifically opted in).
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"\nOVERALL: {report['status']} | Report: {out}", flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
