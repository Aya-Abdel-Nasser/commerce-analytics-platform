
"""Load generated customer-domain CSVs into the isolated CI warehouse."""

import csv
import os
from datetime import datetime, timezone
from pathlib import Path

import pymssql

ROOT = Path(__file__).resolve().parents[2]

OLTP_DIR = ROOT / "data/generated/oltp/prodlike/initial"
CRM_DIR = ROOT / "data/generated/crm/prodlike/initial"

INGESTED_AT = datetime(2026, 10, 8, tzinfo=timezone.utc).replace(tzinfo=None)
BATCH_SIZE = 1000

TABLES = [
    (
        "oltp_customers",
        OLTP_DIR / "customers.csv",
        [
            "customer_id", "customer_code", "full_name", "email",
            "city", "created_at", "updated_at", "_ingested_at_utc",
        ],
        50_000,
    ),
    (
        "crm_customers",
        CRM_DIR / "crm_customers.csv",
        [
            "crm_customer_id", "external_customer_code", "signup_at",
            "customer_segment", "marketing_opt_in",
            "preferred_channel", "updated_at",
        ],
        50_000,
    ),
    (
        "crm_loyalty_accounts",
        CRM_DIR / "loyalty_accounts.csv",
        [
            "loyalty_account_id", "crm_customer_id", "loyalty_tier",
            "points_balance", "enrolled_at", "updated_at",
        ],
        35_000,
    ),
    (
        "crm_loyalty_transactions",
        CRM_DIR / "loyalty_transactions.csv",
        [
            "loyalty_transaction_id", "loyalty_account_id",
            "transaction_type", "points_delta",
            "reference_order_number", "occurred_at",
        ],
        175_000,
    ),
]

DATETIME_COLUMNS = {
    "created_at", "updated_at", "signup_at",
    "enrolled_at", "occurred_at",
}

INTEGER_COLUMNS = {
    "customer_id", "crm_customer_id",
    "loyalty_account_id", "loyalty_transaction_id",
    "marketing_opt_in", "points_balance", "points_delta",
}


def convert_value(column, value):
    if value is None or value == "":
        return None

    if column in INTEGER_COLUMNS:
        return int(value)

    if column in DATETIME_COLUMNS:
        parsed = datetime.fromisoformat(value)

        if parsed.tzinfo is not None:
            parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)

        return parsed

    return value


def load_table(cursor, name, csv_path, columns, expected_rows):
    if not csv_path.is_file():
        raise FileNotFoundError(f"Missing CI input: {csv_path}")

    insert_columns = ", ".join(f"[{column}]" for column in columns)
    placeholders = ", ".join(["%s"] * len(columns))

    statement = (
        f"INSERT INTO [bronze].[{name}] "
        f"({insert_columns}) VALUES ({placeholders})"
    )

    loaded = 0
    batch = []

    with csv_path.open("r", encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)

        required_columns = set(columns) - {"_ingested_at_utc"}

        if not required_columns.issubset(set(reader.fieldnames or [])):
            raise ValueError(f"Unexpected CSV columns in {csv_path}")

        for record in reader:
            row = []

            for column in columns:
                if column == "_ingested_at_utc":
                    row.append(INGESTED_AT)
                else:
                    row.append(convert_value(column, record[column]))

            batch.append(tuple(row))

            if len(batch) >= BATCH_SIZE:
                cursor.executemany(statement, batch)
                loaded += len(batch)
                batch.clear()

        if batch:
            cursor.executemany(statement, batch)
            loaded += len(batch)

    if loaded != expected_rows:
        raise ValueError(
            f"{name}: expected {expected_rows}, loaded {loaded}"
        )

    cursor.execute(
        f"SELECT COUNT_BIG(*) FROM [bronze].[{name}]"
    )
    database_count = cursor.fetchone()[0]

    if database_count != expected_rows:
        raise ValueError(
            f"{name}: database count mismatch: {database_count}"
        )

    print(f"PASS: {name} — {loaded:,} rows", flush=True)


def main():
    password = os.environ.get("MSSQL_SA_PASSWORD")

    if not password:
        raise RuntimeError("MSSQL_SA_PASSWORD is missing")

    connection = pymssql.connect(
        server="127.0.0.1",
        port=1433,
        user="sa",
        password=password,
        database="commerce_warehouse_ci",
        autocommit=False,
        login_timeout=30,
        timeout=120,
    )

    try:
        with connection.cursor() as cursor:
            for table in TABLES:
                load_table(cursor, *table)
                connection.commit()

        print("CI CUSTOMER BRONZE LOAD: PASS", flush=True)

    except Exception:
        connection.rollback()
        raise

    finally:
        connection.close()


if __name__ == "__main__":
    main()
