#!/usr/bin/env python3
"""Project 2 | MOCK_RETURNS_API initial JSONL snapshot validation (READ ONLY).

Standard-library only. Returns exit code 0 only when source contract, manifest,
initial snapshot baseline, semantic checks and pinned SHA-256 (if provided) pass.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re

TOP = ('_source_system', '_ingested_at_utc', '_source_endpoint', 'payload')
PAYLOAD = ('return_id', 'order_number', 'requested_at', 'reason_code',
           'return_status', 'requested_refund_egp', 'updated_at')
EXPECTED_STATUS = {'REJECTED': 5611, 'REFUNDED': 5558, 'REQUESTED': 5518, 'APPROVED': 5406}
EXPECTED_REASONS = {'WRONG_ITEM': 5579, 'CHANGED_MIND': 5552,
                    'NOT_AS_DESCRIBED': 5550, 'QUALITY_ISSUE': 5412}
EXPECTED_ROWS = 22093
BASELINE_SHA256 = '3a352fda4b17a5c62fc167a6d613b576dd2fb67d47e30850aab221191f12f0e7'


def json_type(value):
    if value is None: return 'null'
    if isinstance(value, bool): return 'boolean'
    if isinstance(value, str): return 'string'
    if isinstance(value, dict): return 'object'
    if isinstance(value, list): return 'array'
    if isinstance(value, (int, float)): return 'number'
    return type(value).__name__


def parse_utc(value):
    if not isinstance(value, str): return None
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return result if result.tzinfo is not None and result.utcoffset() == timedelta(0) else None
    except (TypeError, ValueError, OverflowError):
        return None


def validate(source, manifest_path, out, check_hash=True):
    errors = Counter()
    examples = defaultdict(list)
    def fail(code, lineno=None, note=None):
        errors[code] += 1
        if len(examples[code]) < 5:
            examples[code].append({'line': lineno, 'detail': str(note)[:250] if note is not None else ''})

    source_bytes = source.read_bytes()  # ~8 MB initial snapshot; never change source
    sha = hashlib.sha256(source_bytes).hexdigest()
    lines = source_bytes.splitlines()
    ids = set(); orders = set(); exact_lines = set()
    stats = Counter(); statuses = Counter(); reasons = Counter()
    types = defaultdict(Counter)
    min_requested = max_requested = min_updated = max_updated = None
    amounts = []
    max_chars = 0
    max_bytes = 0
    for number, raw_line in enumerate(lines, 1):
        stats['physical_lines'] += 1
        max_bytes = max(max_bytes, len(raw_line))
        if not raw_line.strip():
            fail('blank_lines', number)
            continue
        if raw_line in exact_lines:
            fail('duplicate_exact_json_lines', number)
        exact_lines.add(raw_line)
        try:
            line = raw_line.decode('utf-8-sig' if number == 1 else 'utf-8')
        except UnicodeDecodeError as exc:
            fail('invalid_utf8', number, exc); continue
        max_chars = max(max_chars, len(line))
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            fail('invalid_json', number, exc); continue
        if not isinstance(obj, dict):
            fail('not_json_object', number); continue
        stats['valid_json_objects'] += 1
        if set(obj) != set(TOP):
            fail('wrong_envelope_fields', number, sorted(obj))
        for name in TOP:
            types['$.' + name][json_type(obj.get(name))] += 1
        for name in TOP[:3]:
            if not isinstance(obj.get(name), str) or not obj[name].strip():
                fail('missing_or_nonstring_' + name, number)
        if obj.get('_source_system') != 'MOCK_RETURNS_API':
            fail('source_system_mismatch', number)
        if obj.get('_source_endpoint') != '/api/v1/returns':
            fail('endpoint_mismatch', number)
        if parse_utc(obj.get('_ingested_at_utc')) is None:
            fail('invalid_ingested_at_utc', number)
        p = obj.get('payload')
        if not isinstance(p, dict):
            fail('payload_not_object', number); continue
        if set(p) != set(PAYLOAD):
            fail('wrong_payload_fields', number, sorted(p))
        for name in PAYLOAD:
            value = p.get(name)
            types['$.payload.' + name][json_type(value)] += 1
            if not isinstance(value, str) or not value.strip():
                fail('missing_or_nonstring_payload_' + name, number)
        rid = p.get('return_id')
        order = p.get('order_number')
        if isinstance(rid, str):
            if rid in ids: fail('duplicate_return_id', number, rid)
            ids.add(rid)
            if not re.fullmatch(r'RET\d{9}', rid): fail('return_id_format', number, rid)
        if isinstance(order, str):
            if order in orders: fail('duplicate_order_number_observed', number, order)
            orders.add(order)
            if not re.fullmatch(r'ORD\d{9}', order): fail('order_number_format', number, order)
        statuses[p.get('return_status')] += 1
        reasons[p.get('reason_code')] += 1
        d1 = parse_utc(p.get('requested_at'))
        d2 = parse_utc(p.get('updated_at'))
        if d1 is None: fail('bad_requested_at_utc', number)
        else:
            min_requested = d1 if min_requested is None else min(d1, min_requested)
            max_requested = d1 if max_requested is None else max(d1, max_requested)
        if d2 is None: fail('bad_updated_at_utc', number)
        else:
            min_updated = d2 if min_updated is None else min(d2, min_updated)
            max_updated = d2 if max_updated is None else max(d2, max_updated)
        if d1 is not None and d2 is not None and d2 < d1:
            fail('updated_before_requested', number)
        refund = p.get('requested_refund_egp')
        if isinstance(refund, str) and re.fullmatch(r'\d+\.\d{2}', refund):
            try:
                amount = Decimal(refund)
                if amount <= 0: fail('nonpositive_refund', number, refund)
                amounts.append(amount)
            except InvalidOperation:
                fail('invalid_refund', number, refund)
        else:
            fail('invalid_refund_format_or_type', number, refund)
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    checks = {
        'source_file_named_in_manifest': manifest.get('data_file') == source.name,
        'manifest_rows_match': manifest.get('rows_extracted') == stats['physical_lines'],
        'manifest_expected_rows': manifest.get('rows_extracted') == EXPECTED_ROWS,
        'manifest_source_system': manifest.get('source_system') == 'MOCK_RETURNS_API',
        'manifest_endpoint': manifest.get('endpoint') == '/api/v1/returns',
        'manifest_page_size': manifest.get('page_size') == 1000,
        'manifest_pages': manifest.get('pages') == 23,
        'manifest_pages_cover_rows': isinstance(manifest.get('pages'), int) and
            isinstance(manifest.get('page_size'), int) and
            (manifest['pages'] - 1) * manifest['page_size'] < stats['physical_lines'] <= manifest['pages'] * manifest['page_size'],
        'total_expected': stats['physical_lines'] == EXPECTED_ROWS,
        'return_id_distinct_expected': len(ids) == EXPECTED_ROWS,
        'order_number_distinct_initial_snapshot': len(orders) == EXPECTED_ROWS,
        'statuses_match_source_baseline': dict(statuses) == EXPECTED_STATUS,
        'reason_codes_match_source_baseline': dict(reasons) == EXPECTED_REASONS,
        'no_record_over_precision_1000': max_chars <= 1000,
    }
    # Validate snapshot extraction metadata in every valid JSON envelope.
    # This is separate from page-count arithmetic; it does not prove API pagination was correct.
    for number, raw in enumerate(lines, 1):
        if not raw.strip(): continue
        try: obj = json.loads(raw)
        except (ValueError, UnicodeDecodeError): continue
        if not isinstance(obj, dict): continue
        if obj.get('_ingested_at_utc') != manifest.get('ingested_at_utc'):
            fail('ingested_at_does_not_match_manifest', number)
    if check_hash:
        checks['pinned_source_file_sha256_matches'] = sha == BASELINE_SHA256
    for name, passed in checks.items():
        if not passed: fail('check_failed_' + name)
    report = {
        'overall_status': 'PASS' if not errors else 'FAIL',
        'source_file': str(source), 'manifest_file': str(manifest_path),
        'file_size_bytes': len(source_bytes), 'source_file_sha256': sha,
        'source_sha256_pinned': BASELINE_SHA256,
        'rows': dict(stats), 'expected_rows': EXPECTED_ROWS,
        'max_json_line_characters': max_chars, 'max_json_line_bytes': max_bytes,
        'distinct_return_ids': len(ids), 'distinct_order_numbers': len(orders),
        'return_status_counts': dict(sorted(statuses.items())),
        'reason_code_counts': dict(sorted(reasons.items())),
        'observed_json_types': {k: dict(v) for k,v in sorted(types.items())},
        'requested_at_utc_min': min_requested.isoformat() if min_requested else None,
        'requested_at_utc_max': max_requested.isoformat() if max_requested else None,
        'updated_at_utc_min': min_updated.isoformat() if min_updated else None,
        'updated_at_utc_max': max_updated.isoformat() if max_updated else None,
        'refund_min': str(min(amounts)) if amounts else None,
        'refund_max': str(max(amounts)) if amounts else None,
        'manifest_checks': checks, 'errors': dict(errors), 'error_samples': dict(examples),
        'important_notes': [
            'Source is a local MOCK REST API extract; do not infer live API pagination from the JSONL.',
            'Only the source is validated here. SQL Server has NOT been accessed.',
            'CSV/JSONL has no declared SQL keys or column constraints; observed uniqueness is not a PK.',
            'SHA-256 is calculated on original archived UTF-8 bytes; SQL NVARCHAR stores decoded Unicode text.',
        ]
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('RETURNS SOURCE VALIDATION:', report['overall_status'])
    print('Rows:', stats['physical_lines'], '| JSON objects:', stats['valid_json_objects'])
    print('Max chars:', max_chars, '| SHA-256:', sha)
    print('Statuses:', report['return_status_counts'])
    print('Reasons:', report['reason_code_counts'])
    print('Errors:', dict(errors))
    print('Report:', out)
    return not errors


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-dir', type=Path, required=True, help='Folder containing returns_initial.jsonl and manifest.json')
    p.add_argument('--out', type=Path, default=Path('reports/SOURCE_returns_initial.json'))
    p.add_argument('--skip-pinned-hash', action='store_true', help='For modified/future snapshots; other initial-baseline checks still apply')
    args = p.parse_args()
    try:
        ok = validate(args.source_dir / 'returns_initial.jsonl', args.source_dir / 'manifest.json', args.out,
                      check_hash=not args.skip_pinned_hash)
    except (FileNotFoundError, UnicodeError, json.JSONDecodeError, OSError) as exc:
        p.exit(2, f'SOURCE VALIDATION NOT EXECUTED: {exc}\n')
    if not ok: raise SystemExit(1)

if __name__ == '__main__': main()
