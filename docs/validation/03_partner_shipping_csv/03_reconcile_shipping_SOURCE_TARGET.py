#!/usr/bin/env python3
"""Project 2 | Exact nine-column, shipment_id-keyed reconciliation | READ ONLY.

Supported target inputs:
 A) Direct SQL Server connection (requires pip install pyodbc + SQL Server ODBC driver).
 B) CSV export of the SQL Server table with the NINE columns in source order.

Typical direct SQL Server usage (PowerShell, single line):
 py 03_reconcile_shipping_SOURCE_TARGET.py --source-dir "D:\\...\\initial" --connection-string "DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes" --out shipping_reconciliation.json

Alternative:
 py 03_reconcile_shipping_SOURCE_TARGET.py --source-dir "D:\\...\\initial" --target-csv "D:\\...\\partner_shipments_target_export.csv"

Strict by default: SQL NULL != CSV empty string. Add --allow-null-delivered-at
ONLY if the mapping intentionally converts CSV '' -> SQL NULL for delivered_at.
That exception is counted, visible, and does not suppress other mismatches.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import csv
import json
from pathlib import Path
from typing import Iterator

COLUMNS = (
    'shipment_id', 'order_number', 'carrier_code', 'tracking_number',
    'shipment_status', 'shipped_at', 'delivered_at', 'shipping_fee_egp', 'source_updated_at'
)
FILES = (
    'egx_shipments_initial.csv', 'fst_shipments_initial.csv',
    'nil_shipments_initial.csv', 'dlv_shipments_initial.csv'
)


def read_csv(path: Path) -> Iterator[dict]:
    with path.open('r', encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream, strict=True)
        if tuple(reader.fieldnames or ()) != COLUMNS:
            raise ValueError(f'Incorrect header in {path}: {reader.fieldnames!r}')
        for index, row in enumerate(reader, start=2):
            if None in row or any(row[c] is None for c in COLUMNS):
                raise ValueError(f'Malformed CSV row in {path}:{index}')
            yield row


def read_sql(connection_string: str) -> Iterator[dict]:
    try:
        import pyodbc
    except ImportError as err:
        raise RuntimeError('pyodbc not installed; run: py -m pip install pyodbc OR use --target-csv') from err
    conn = pyodbc.connect(connection_string, timeout=30)
    try:
        cursor = conn.cursor()
        # Explicit projection ensures the exact source field order. No modifications to DB.
        query = '''SELECT shipment_id, order_number, carrier_code, tracking_number,
                          shipment_status, shipped_at, delivered_at,
                          shipping_fee_egp, source_updated_at
                   FROM bronze.partner_shipments'''
        cursor.execute(query)
        while True:
            batch = cursor.fetchmany(5000)
            if not batch:
                break
            for values in batch:
                yield dict(zip(COLUMNS, values))  # SQL NULL remains Python None
    finally:
        conn.close()


def reconcile(source_dir: Path, target_rows: Iterator[dict], allow_null_delivered_at: bool) -> dict:
    source = {}
    duplicate_source = Counter()
    src_by_carrier = Counter()
    src_by_status = Counter()
    for filename in FILES:
        for row in read_csv(source_dir / filename):
            key = row['shipment_id']
            if key in source:
                duplicate_source[key] += 1
            else:
                source[key] = row
            src_by_carrier[row['carrier_code']] += 1
            src_by_status[row['shipment_status']] += 1
    duplicate_target = Counter()
    target_seen = set()
    matched_keys = set()
    extra = Counter()
    target_by_carrier = Counter()
    target_by_status = Counter()
    mismatch_columns = Counter()
    samples = []
    mismatch_rows = 0
    target_count = 0
    allowed_null_conversion = 0
    for target in target_rows:
        target_count += 1
        key = target['shipment_id']
        if key in target_seen:
            duplicate_target[str(key)] += 1
            continue
        target_seen.add(key)
        target_by_carrier[str(target['carrier_code'])] += 1
        target_by_status[str(target['shipment_status'])] += 1
        if key not in source:
            extra[str(key)] += 1
            continue
        matched_keys.add(key)
        src = source[key]
        differences = {}
        for field in COLUMNS:
            s_value, t_value = src[field], target[field]
            if s_value == t_value:
                continue
            if field == 'delivered_at' and s_value == '' and t_value is None and allow_null_delivered_at:
                allowed_null_conversion += 1
                continue
            mismatch_columns[field] += 1
            differences[field] = {'source': s_value, 'target': t_value}
        if differences:
            mismatch_rows += 1
            if len(samples) < 10:
                samples.append({'shipment_id': key, 'differences': differences})
    missing = set(source) - matched_keys
    valid = (not duplicate_source and not duplicate_target and not extra and not missing and not mismatch_rows
             and target_count == len(source) and len(source) == 120000)
    return {
        'result': 'PASS' if valid else 'FAIL',
        'comparison': 'Exact column-by-column (case-sensitive, whitespace-sensitive, text representation sensitive)',
        'allow_null_delivered_at': allow_null_delivered_at,
        'allowed_empty_csv_to_null_sql_conversions': allowed_null_conversion,
        'source_rows': sum(src_by_carrier.values()),
        'source_distinct_shipment_ids': len(source),
        'target_rows': target_count,
        'matched_shipment_ids': len(matched_keys),
        'missing_in_target_count': len(missing),
        'missing_in_target_examples': sorted(missing)[:10],
        'extra_in_target_count': sum(extra.values()),
        'extra_in_target_examples': list(extra)[:10],
        'duplicate_source_id_count': sum(duplicate_source.values()),
        'duplicate_source_id_examples': list(duplicate_source)[:10],
        'duplicate_target_id_count': sum(duplicate_target.values()),
        'duplicate_target_id_examples': list(duplicate_target)[:10],
        'mismatched_rows': mismatch_rows,
        'mismatched_fields_by_column': dict(mismatch_columns),
        'mismatch_examples': samples,
        'source_carrier_counts': dict(sorted(src_by_carrier.items())),
        'target_carrier_counts': dict(sorted(target_by_carrier.items())),
        'source_status_counts': dict(sorted(src_by_status.items())),
        'target_status_counts': dict(sorted(target_by_status.items())),
        'note': 'CSV export mode cannot reliably distinguish SQL NULL from an empty string. Use direct SQL mode for NULL-sensitive exact reconciliation.'
    }


def main():
    p = argparse.ArgumentParser(description='Read-only source to target nine-column reconciliation')
    p.add_argument('--source-dir', type=Path, required=True)
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument('--target-csv', type=Path)
    group.add_argument('--connection-string')
    p.add_argument('--allow-null-delivered-at', action='store_true')
    p.add_argument('--out', type=Path, default=Path('shipping_reconciliation.json'))
    args = p.parse_args()
    target_rows = read_csv(args.target_csv) if args.target_csv else read_sql(args.connection_string)
    result = reconcile(args.source_dir, target_rows, args.allow_null_delivered_at)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False, default=str), encoding='utf-8')
    print('SOURCE-TARGET RECONCILIATION:', result['result'])
    print('SOURCE:', result['source_rows'], 'TARGET:', result['target_rows'],
          'MATCHED IDs:', result['matched_shipment_ids'])
    print('MISSING:', result['missing_in_target_count'], 'EXTRA:', result['extra_in_target_count'],
          'MISMATCHED ROWS:', result['mismatched_rows'])
    print('TOLERATED empty-CSV -> NULL-SQL:', result['allowed_empty_csv_to_null_sql_conversions'])
    print('REPORT:', args.out.resolve())
    raise SystemExit(0 if result['result'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
