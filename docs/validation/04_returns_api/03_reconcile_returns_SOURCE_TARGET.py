#!/usr/bin/env python3
"""Project 2 | exact text reconciliation, original JSONL vs SQL bronze.returns_raw.

READ ONLY: does not load, update or delete data.
Standard library only with --target-csv; optional pyodbc for direct SQL Server.
Compares ALL 22,093 JSON objects' exact text with a multiset (order-independent).
This is Unicode text preservation, NOT UTF-8 byte equality with NVARCHAR(MAX).
"""
import argparse
from collections import Counter, defaultdict
import csv
from difflib import SequenceMatcher
import hashlib
import json
from pathlib import Path
import sys

EXPECTED_ROWS = 22093


def parse_row(text, counts, origin):
    try:
        obj = json.loads(text)
        if not isinstance(obj, dict) or not isinstance(obj.get('payload'), dict):
            counts[origin + '_missing_json_object_payload'] += 1
            return None, None
        rid = obj['payload']['return_id']
        if not isinstance(rid, str):
            counts[origin + '_nonstring_return_id'] += 1
            return None, None
        return rid, obj
    except (ValueError, TypeError, KeyError):
        counts[origin + '_invalid_json_or_missing_return_id'] += 1
        return None, None


def rows_from_source(path):
    # newline characters delimit JSONL records; not part of raw_json content.
    with path.open('r', encoding='utf-8-sig', newline='') as stream:
        for line in stream:
            yield line.rstrip('\r\n')


def rows_from_target_csv(path):
    with path.open('r', encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames or 'raw_json' not in reader.fieldnames:
            raise ValueError('Target CSV must include a column header named raw_json.')
        for row in reader:
            if row.get(None):
                raise ValueError('Malformed CSV row: extra columns. Re-export as RFC4180 CSV.')
            yield row['raw_json']


def rows_from_database(connection_string):
    try:
        import pyodbc  # Optional; not required for source/target-csv path
    except ImportError as exc:
        raise RuntimeError('Install pyodbc (python -m pip install pyodbc) or use --target-csv') from exc
    conn = pyodbc.connect(connection_string, autocommit=True, timeout=30)
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT raw_json FROM bronze.returns_raw')
        for row in cursor:
            yield row[0]
    finally:
        conn.close()


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def summarize(source_path, target_rows, out_path, expected_rows):
    issues = Counter()
    source_counter = Counter()
    target_counter = Counter()
    src_ids = defaultdict(list)
    tgt_ids = defaultdict(list)
    source_len = target_len = 0
    for line in rows_from_source(source_path):
        source_len += 1
        if line is None:
            issues['source_null_line'] += 1
            continue
        source_counter[line] += 1
        rid, _ = parse_row(line, issues, 'source')
        if rid is not None: src_ids[rid].append(line)
    for line in target_rows:
        target_len += 1
        if not isinstance(line, str):
            issues['target_null_or_nonstring_raw_json'] += 1
            continue
        target_counter[line] += 1
        rid, _ = parse_row(line, issues, 'target')
        if rid is not None: tgt_ids[rid].append(line)
    if source_len != expected_rows: issues['source_row_count_mismatch'] += 1
    if target_len != expected_rows: issues['target_row_count_mismatch'] += 1

    # Multiset ensures all raw JSON text occurrences are preserved; order can differ.
    missing_raw = source_counter - target_counter
    extra_raw = target_counter - source_counter
    missing_id = sorted(src_ids.keys() - tgt_ids.keys())
    extra_id = sorted(tgt_ids.keys() - src_ids.keys())
    dup_src = sorted(k for k,v in src_ids.items() if len(v) > 1)
    dup_tgt = sorted(k for k,v in tgt_ids.items() if len(v) > 1)
    changed = []
    semantic_only_changes = 0
    for rid in (src_ids.keys() & tgt_ids.keys()):
        if len(src_ids[rid]) == 1 and len(tgt_ids[rid]) == 1:
            a, b = src_ids[rid][0], tgt_ids[rid][0]
            if a != b:
                try:
                    semantically_equal = json.loads(a) == json.loads(b)
                except ValueError:
                    semantically_equal = False
                if semantically_equal: semantic_only_changes += 1
                if len(changed) < 15:
                    matcher = SequenceMatcher(a=a, b=b, autojunk=False)
                    differences = [x for x in matcher.get_opcodes() if x[0] != 'equal']
                    first_diff = differences[0][1:5] if differences else None
                    changed.append({
                        'return_id': rid, 'exact_text_equal': False,
                        'parsed_json_equal': semantically_equal,
                        'source_length': len(a), 'target_length': len(b),
                        'source_utf8_text_sha256': digest(a),
                        'target_utf8_text_sha256': digest(b),
                        'first_text_change_positions_source_start_end_target_start_end': first_diff
                    })
    missing_raw_count = sum(missing_raw.values())
    extra_raw_count = sum(extra_raw.values())
    if missing_raw_count: issues['raw_text_missing_from_target'] = missing_raw_count
    if extra_raw_count: issues['unexpected_raw_text_in_target'] = extra_raw_count
    if missing_id: issues['source_return_ids_missing_in_target'] = len(missing_id)
    if extra_id: issues['target_return_ids_not_in_source'] = len(extra_id)
    if dup_src: issues['duplicate_source_return_ids'] = len(dup_src)
    if dup_tgt: issues['duplicate_target_return_ids'] = len(dup_tgt)
    report = {
        'overall_status': 'PASS' if not issues else 'FAIL',
        'comparison_level': 'EXACT Unicode JSON text multiset (row order independent)',
        'expected_rows': expected_rows,
        'source_rows': source_len, 'target_rows': target_len,
        'source_distinct_raw_texts': len(source_counter),
        'target_distinct_raw_texts': len(target_counter),
        'raw_text_missing_occurrences': missing_raw_count,
        'raw_text_unexpected_occurrences': extra_raw_count,
        'source_return_ids_missing_from_target': len(missing_id),
        'target_return_ids_missing_from_source': len(extra_id),
        'duplicate_source_return_ids': len(dup_src),
        'duplicate_target_return_ids': len(dup_tgt),
        'json_semantically_equal_but_raw_text_differs_ids': semantic_only_changes,
        'all_return_ids_compared': len(src_ids.keys() & tgt_ids.keys()),
        'issues': dict(sorted(issues.items())),
        'examples': {
            'missing_id_samples': missing_id[:15],
            'unexpected_id_samples': extra_id[:15],
            'duplicate_source_id_samples': dup_src[:15],
            'duplicate_target_id_samples': dup_tgt[:15],
            'changed_row_samples': changed,
            'missing_raw_text_sha256_samples': [digest(x) for x in list(missing_raw)[:10]],
            'extra_raw_text_sha256_samples': [digest(x) for x in list(extra_raw)[:10]],
        },
        'notes': [
            'PASS proves a full multiset match of source JSON line TEXT and SQL raw_json TEXT, not source file byte identity.',
            'SQL NVARCHAR(MAX) stores Unicode, while original archived JSONL is UTF-8; source file SHA-256 independently covers original bytes.',
            'source_file_name/source_line_number are nullable pipeline lineage and not part of JSONL source; check them with target SQL script.',
            'A PASS from a CSV target export assumes the export faithfully preserves SQL raw_json text; direct pyodbc is stronger.',
        ]
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('RETURNS SOURCE-to-TARGET RECONCILIATION:', report['overall_status'])
    print('Source rows:', source_len, '| Target rows:', target_len)
    print('Missing raw text:', missing_raw_count, '| Unexpected raw text:', extra_raw_count)
    print('Issues:', dict(issues))
    print('Report:', out_path)
    return not issues


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-file', type=Path, required=True)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument('--connection-string', help='pyodbc ODBC Driver + read-only SQL access')
    g.add_argument('--target-csv', type=Path, help='SSMS exported CSV with raw_json column')
    p.add_argument('--out', type=Path, default=Path('reports/RECONCILIATION_returns_initial.json'))
    p.add_argument('--expected-rows', type=int, default=EXPECTED_ROWS)
    args = p.parse_args()
    try:
        rows = rows_from_database(args.connection_string) if args.connection_string else rows_from_target_csv(args.target_csv)
        ok = summarize(args.source_file, rows, args.out, args.expected_rows)
    except (OSError, ValueError, RuntimeError) as exc:
        p.exit(2, f'RECONCILIATION COULD NOT RUN: {exc}\n')
    if not ok: raise SystemExit(1)

if __name__ == '__main__': main()
