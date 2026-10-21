#!/usr/bin/env python3
"""Project 2 | Partner Shipping initial CSV source validation | READ ONLY.

Run on the machine holding the source files:
  py 01_validate_shipping_SOURCE.py --source-dir "D:\\...\\data\\landing\\partners\\prodlike\\initial" --out "shipping_source_validation.json"
No external Python packages are needed. Source files are never modified.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import csv
from datetime import datetime
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
from typing import Optional

COLUMNS = (
    'shipment_id', 'order_number', 'carrier_code', 'tracking_number',
    'shipment_status', 'shipped_at', 'delivered_at',
    'shipping_fee_egp', 'source_updated_at'
)
FILES = {
    'EGX': 'egx_shipments_initial.csv',
    'FST': 'fst_shipments_initial.csv',
    'NIL': 'nil_shipments_initial.csv',
    'DLV': 'dlv_shipments_initial.csv'
}
DATETIME_FMT = '%m/%d/%Y %H:%M:%S'
TS_COLS = ('shipped_at', 'delivered_at', 'source_updated_at')
KEY_COLS = ('shipment_id', 'order_number', 'tracking_number')
REQUIRED = tuple(x for x in COLUMNS if x != 'delivered_at')
STATUSES = {'DELIVERED', 'IN_TRANSIT', 'DELAYED'}
FEE_PATTERN = re.compile(r'^\d+\.\d{2}$')  # observed snapshot representation, NOT a declared CSV type


def check_datetime(raw: str) -> Optional[datetime]:
    if not raw:
        return None
    try:
        dt = datetime.strptime(raw, DATETIME_FMT)
        return dt if dt.strftime(DATETIME_FMT) == raw else None
    except ValueError:
        return None


def hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for buf in iter(lambda: f.read(1024 * 1024), b''):
            h.update(buf)
    return h.hexdigest()


def source_validate(folder: Path) -> dict:
    errors = Counter()
    examples = defaultdict(list)
    def flag(rule: str, location: str):
        errors[rule] += 1
        if len(examples[rule]) < 5:
            examples[rule].append(location)

    out = {
        'project': 'Commerce Analytics Engineering Platform',
        'dataset': 'Partner Shipping initial CSV',
        'mode': 'READ_ONLY',
        'source_directory': str(folder),
        'timestamp_format': 'MM/dd/yyyy HH:mm:ss',
        'file_inventory': [], 'columns': list(COLUMNS)
    }
    manifest_file = folder / 'manifest.json'
    manifest = None
    if manifest_file.is_file():
        try:
            manifest = json.loads(manifest_file.read_text(encoding='utf-8-sig'))
        except (UnicodeError, json.JSONDecodeError) as e:
            flag('invalid_manifest_json', str(e))
    else:
        flag('missing_manifest', str(manifest_file))
    out['manifest_present'] = manifest is not None
    if manifest is not None:
        if manifest.get('timestamp_format') != 'MM/dd/yyyy HH:mm:ss':
            flag('manifest_timestamp_format_mismatch', str(manifest.get('timestamp_format')))
        if manifest.get('timestamp_timezone') != 'UTC':
            flag('manifest_timezone_not_utc', str(manifest.get('timestamp_timezone')))
        out['manifest_metadata'] = {
            'timestamp_timezone': manifest.get('timestamp_timezone'),
            'timestamp_format': manifest.get('timestamp_format'),
            'shipments_written': manifest.get('shipments_written'),
            'counts_by_carrier': manifest.get('counts_by_carrier'),
            'counts_by_status': manifest.get('counts_by_status')
        }
    file_list = folder / 'shipping_files_initial.txt'
    if file_list.exists():
        names = [line.strip() for line in file_list.read_text(encoding='utf-8-sig').splitlines() if line.strip()]
        if len(names) != 4 or set(names) != set(FILES.values()) or len(names) != len(set(names)):
            flag('file_list_incorrect', str(names))
        out['file_list'] = names
    else:
        out['file_list'] = 'Not present (optional for source validation, needed in Informatica)'

    per_carrier = Counter()
    per_status = Counter()
    carrier_status = Counter()
    missing = Counter()
    whitespace_only = Counter()
    distinct = {k: set() for k in KEY_COLS}
    seen_full_rows = set()
    min_lengths = {k: None for k in COLUMNS}
    max_lengths = {k: 0 for k in COLUMNS}
    parsed_fees = []
    valid_ts_min = {k: None for k in TS_COLS}
    valid_ts_max = {k: None for k in TS_COLS}
    total = 0

    for carrier, filename in FILES.items():
        file_path = folder / filename
        if not file_path.is_file():
            flag('missing_csv_file', filename)
            continue
        info = {'file': filename, 'carrier': carrier, 'bytes': file_path.stat().st_size,
                'sha256': hash_file(file_path), 'rows': 0}
        try:
            with file_path.open('r', encoding='utf-8-sig', newline='') as f:
                reader = csv.DictReader(f, strict=True)
                if tuple(reader.fieldnames or ()) != COLUMNS:
                    flag('csv_header_mismatch', f'{filename}: {reader.fieldnames!r}')
                    out['file_inventory'].append(info)
                    continue
                for lineno, row in enumerate(reader, start=2):
                    loc = f'{filename}:row {lineno}'
                    if None in row or any(row.get(c) is None for c in COLUMNS):
                        flag('csv_malformed_row', loc)
                        continue
                    info['rows'] += 1
                    total += 1
                    for col in COLUMNS:
                        value = row[col]
                        if value == '':
                            missing[col] += 1
                        elif not value.strip():
                            whitespace_only[col] += 1
                            flag('whitespace_only_value', f'{loc} {col}')
                        max_lengths[col] = max(max_lengths[col], len(value))
                        if value:
                            ml = min_lengths[col]
                            min_lengths[col] = len(value) if ml is None else min(ml, len(value))
                    for col in REQUIRED:
                        if row[col] == '':
                            flag('missing_required_value', f'{loc} {col}')
                    if row['carrier_code'] != carrier:
                        flag('carrier_file_mismatch', loc)
                    if row['shipment_status'] not in STATUSES:
                        flag('unexpected_shipment_status', loc)
                    if row['tracking_number'] and not row['tracking_number'].startswith(carrier):
                        flag('tracking_carrier_prefix_mismatch', loc)
                    per_carrier[row['carrier_code']] += 1
                    per_status[row['shipment_status']] += 1
                    carrier_status[(row['carrier_code'],row['shipment_status'])] += 1
                    for col in KEY_COLS:
                        key = row[col]
                        if key in distinct[col]:
                            flag(f'duplicate_{col}', f'{loc}: {key}')
                        distinct[col].add(key)
                    values = tuple(row[c] for c in COLUMNS)
                    if values in seen_full_rows:
                        flag('duplicate_full_row', loc)
                    seen_full_rows.add(values)
                    parsed_dt = {}
                    for col in TS_COLS:
                        raw = row[col]
                        dt = check_datetime(raw)
                        parsed_dt[col] = dt
                        if raw and dt is None:
                            flag(f'invalid_{col}', f'{loc}: {raw}')
                        if dt is not None:
                            if valid_ts_min[col] is None or dt < valid_ts_min[col]:
                                valid_ts_min[col] = dt
                            if valid_ts_max[col] is None or dt > valid_ts_max[col]:
                                valid_ts_max[col] = dt
                    if row['shipment_status'] == 'DELIVERED' and not row['delivered_at']:
                        flag('delivered_missing_delivery_timestamp', loc)
                    if row['shipment_status'] != 'DELIVERED' and row['delivered_at']:
                        flag('not_delivered_has_delivery_timestamp', loc)
                    if parsed_dt['shipped_at'] and parsed_dt['delivered_at'] and parsed_dt['delivered_at'] < parsed_dt['shipped_at']:
                        flag('delivered_before_shipped', loc)
                    if parsed_dt['shipped_at'] and parsed_dt['source_updated_at'] and parsed_dt['source_updated_at'] < parsed_dt['shipped_at']:
                        flag('updated_before_shipped', loc)
                    fee_txt = row['shipping_fee_egp']
                    if not FEE_PATTERN.fullmatch(fee_txt):
                        flag('unexpected_fee_lexical_format', f'{loc}: {fee_txt}')
                    try:
                        fee = Decimal(fee_txt)
                        if not fee.is_finite():
                            flag('nonfinite_shipping_fee', loc)
                        else:
                            parsed_fees.append(fee)
                            if fee < 0:
                                flag('negative_shipping_fee', loc)
                    except InvalidOperation:
                        flag('invalid_shipping_fee', f'{loc}: {fee_txt}')
        except (OSError, UnicodeError, csv.Error) as e:
            flag('file_read_error', f'{filename}: {e}')
        out['file_inventory'].append(info)

    if manifest:
        if total != manifest.get('shipments_written'):
            flag('manifest_total_mismatch', f"actual={total}, manifest={manifest.get('shipments_written')}")
        for col, actual in (('counts_by_carrier', per_carrier), ('counts_by_status', per_status)):
            expected = manifest.get(col)
            if not isinstance(expected, dict) or dict(actual) != expected:
                flag('manifest_' + col + '_mismatch', f'actual={dict(actual)}, expected={expected}')
    out['total_rows'] = total
    out['rows_by_carrier'] = dict(sorted(per_carrier.items()))
    out['rows_by_status'] = dict(sorted(per_status.items()))
    out['rows_by_carrier_and_status'] = {c + '|' + st: n for (c, st), n in sorted(carrier_status.items())}
    out['observed_empty_strings'] = {c: missing[c] for c in COLUMNS}
    out['observed_whitespace_only'] = {c: whitespace_only[c] for c in COLUMNS}
    out['observed_distinct_candidate_keys'] = {c: len(distinct[c]) for c in KEY_COLS}
    out['observed_min_nonempty_lengths'] = min_lengths
    out['observed_max_lengths'] = max_lengths
    out['shipping_fee_min_max'] = {
        'min': str(min(parsed_fees)) if parsed_fees else None,
        'max': str(max(parsed_fees)) if parsed_fees else None,
        'physical_type': 'CSV text', 'observed_decimal_precision': 4,
        'observed_decimal_scale': 2, 'declared_precision_scale': None
    }
    out['timestamp_ranges'] = {c: {'min': a.strftime(DATETIME_FMT) if (a := valid_ts_min[c]) else None,
                                   'max': b.strftime(DATETIME_FMT) if (b := valid_ts_max[c]) else None} for c in TS_COLS}
    out['validation_errors'] = dict(sorted(errors.items()))
    out['error_examples'] = dict(examples)
    out['result'] = 'PASS' if not errors else 'FAIL'
    out['schema_note'] = 'CSV has no enforced PK, FK, NOT NULL, datatype, precision or scale; all observations are empirical.'
    return out


def main():
    p = argparse.ArgumentParser(description='Read-only Partner Shipping source validation')
    p.add_argument('--source-dir', type=Path, required=True, help='Folder with 4 CSV files and manifest.json')
    p.add_argument('--out', type=Path, default=Path('partner_shipping_source_validation.json'))
    p.add_argument('--baseline', type=Path, help='Optional pinned, previously inspected initial-source SHA-256 baseline')
    args = p.parse_args()
    report = source_validate(args.source_dir)
    if args.baseline:
        baseline = json.loads(args.baseline.read_text(encoding='utf-8-sig'))
        expected = baseline.get('sha256_by_file', {})
        actual = {x['file']: x['sha256'] for x in report['file_inventory']}
        mismatches = {name: {'baseline': h, 'actual': actual.get(name)}
                      for name, h in expected.items() if actual.get(name) != h}
        report['baseline_sha256_validation'] = {'result': 'PASS' if not mismatches else 'FAIL', 'mismatches': mismatches}
        if mismatches:
            report['result'] = 'FAIL'
            report['validation_errors']['source_file_hash_baseline_mismatch'] = len(mismatches)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    print('SOURCE VALIDATION:', report['result'])
    print('ROWS:', report['total_rows'])
    print('CARRIER COUNTS:', report['rows_by_carrier'])
    print('STATUS COUNTS:', report['rows_by_status'])
    print('EMPTY delivered_at:', report['observed_empty_strings']['delivered_at'])
    print('ERRORS:', report['validation_errors'])
    print('REPORT:', args.out.resolve())
    raise SystemExit(0 if report['result'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
