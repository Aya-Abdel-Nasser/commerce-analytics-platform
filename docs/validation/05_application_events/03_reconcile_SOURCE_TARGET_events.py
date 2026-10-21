#!/usr/bin/env python3
r"""Read-only exact Unicode text multiset reconciliation for large JSONL feeds.

Example (PowerShell, one line):
  python .\05_application_events\03_reconcile_SOURCE_TARGET_events.py --source-dir "D:\\...\\events\\prodlike\\initial" --connection-string 'DRIVER={ODBC Driver 18 for SQL Server};SERVER=.\\SQLEXPRESS;DATABASE=commerce_warehouse_dev;Trusted_Connection=yes;TrustServerCertificate=yes;ApplicationIntent=ReadOnly' --out .\reports\EVENTS_reconciliation.json

Every UTF-8 JSONL line (excluding its newline separator and optional BOM) must
match one SQL Server raw_json Unicode value exactly, including whitespace and
object property order. Input row order is irrelevant; duplicate occurrence counts
are checked. Data are streamed into temporary on-disk hash partitions, so memory
use is bounded by the largest partition, not the 1,630,000-row dataset.

No changes to original source files or SQL Server. Requires free temporary disk
space ~2x the UTF-8 data volume (plus overhead), and may take several minutes.
"""
from __future__ import annotations
import argparse
from collections import Counter
import csv
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import tempfile

BUCKETS = 256
PREFIX = struct.Struct('>I')


def read_manifest(folder: Path):
    path = folder / 'manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8-sig'))
    parts = manifest.get('parts')
    if not isinstance(parts, list) or not parts:
        raise ValueError('manifest.json must have a nonempty "parts" list')
    names = [p['file'] for p in parts]
    if len(set(names)) != len(names) or any(Path(name).name != name for name in names):
        raise ValueError('Invalid or duplicate file name in manifest')
    return manifest, parts


def iter_source(folder: Path, parts, per_file):
    for part in parts:
        name = part['file']
        path = folder / name
        count = 0
        # Each file may have an optional UTF-8 BOM. Decode rather than compare
        # original file bytes: target is NVARCHAR Unicode, not a UTF-8 file.
        with path.open('r', encoding='utf-8-sig', newline='') as handle:
            for number, line in enumerate(handle, 1):
                count += 1
                text = line.rstrip('\r\n')
                if not text or not (text.startswith('{') and text.endswith('}')):
                    raise ValueError(f'Unexpected blank/non-object line at {name}:{number}')
                yield text
        per_file.append({'file': name, 'actual_rows': count,
                         'manifest_rows': int(part['rows']),
                         'pass': count == int(part['rows'])})
        print(f'  SOURCE {name}: {count:,}', flush=True)


def iter_target_odbc(conn_str):
    try:
        import pyodbc
    except ImportError as exc:
        raise RuntimeError('Install pyodbc: python -m pip install pyodbc') from exc
    conn = pyodbc.connect(conn_str, autocommit=True, timeout=60)
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT raw_json FROM bronze.app_events_raw')
        while True:
            rows = cursor.fetchmany(2000)
            if not rows:
                break
            for row in rows:
                yield row[0]
    finally:
        conn.close()


def iter_target_csv(path):
    with path.open('r', encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or 'raw_json' not in reader.fieldnames:
            raise ValueError('CSV must have header raw_json')
        for row in reader:
            if None in row:
                raise ValueError('Malformed CSV line (extra fields)')
            yield row['raw_json']


class PartitionWriter:
    def __init__(self, parent: Path, side: str):
        self.parent = parent
        self.side = side
        self.handles = {}
        self.total_bytes = 0
        self.total_rows = 0

    def write(self, text):
        if not isinstance(text, str):
            raise ValueError(f'{self.side} raw_json is NULL or not a string')
        payload = text.encode('utf-8', errors='strict')
        digest = hashlib.sha256(payload).digest()
        bucket = digest[0]
        if bucket not in self.handles:
            self.handles[bucket] = (self.parent / f'{self.side}_{bucket:02x}.bin').open('wb')
        self.handles[bucket].write(PREFIX.pack(len(payload)))
        self.handles[bucket].write(payload)
        self.total_bytes += len(payload) + PREFIX.size
        self.total_rows += 1

    def close(self):
        for handle in self.handles.values():
            handle.close()
        self.handles.clear()


def count_partition(path):
    counter = Counter()
    if not path.exists():
        return counter
    with path.open('rb') as f:
        while header := f.read(PREFIX.size):
            if len(header) != PREFIX.size:
                raise RuntimeError('Corrupt temporary partition header')
            length = PREFIX.unpack(header)[0]
            data = f.read(length)
            if len(data) != length:
                raise RuntimeError('Corrupt temporary partition payload')
            counter[data] += 1
    return counter


def reconcile(args):
    folder = args.source_dir
    manifest, parts = read_manifest(folder)
    expected = int(manifest['event_records'])
    report_path = args.out
    per_file = []
    missing_count = extra_count = 0
    missing_sample = []
    extra_sample = []
    source_rows = target_rows = 0
    issues = {}

    with tempfile.TemporaryDirectory(prefix='p2_events_reconcile_', dir=args.temp_dir) as tmp:
        temp = Path(tmp)
        source_writer = PartitionWriter(temp, 'source')
        target_writer = PartitionWriter(temp, 'target')
        try:
            print('Streaming SOURCE JSONL to temporary partitions...', flush=True)
            for raw in iter_source(folder, parts, per_file):
                source_writer.write(raw)
                if source_writer.total_rows % 200000 == 0:
                    print(f'  Source read: {source_writer.total_rows:,}', flush=True)
            print('Streaming SQL Server TARGET to temporary partitions...', flush=True)
            target_rows_stream = iter_target_odbc(args.connection_string) if args.connection_string else iter_target_csv(args.target_csv)
            for raw in target_rows_stream:
                target_writer.write(raw)
                if target_writer.total_rows % 200000 == 0:
                    print(f'  Target read: {target_writer.total_rows:,}', flush=True)
        finally:
            source_writer.close()
            target_writer.close()
        source_rows, target_rows = source_writer.total_rows, target_writer.total_rows
        print('Comparing 256 partitions with exact UTF-8 Unicode text bytes...', flush=True)
        for i in range(BUCKETS):
            src = count_partition(temp / f'source_{i:02x}.bin')
            tgt = count_partition(temp / f'target_{i:02x}.bin')
            missing = src - tgt
            extra = tgt - src
            missing_count += sum(missing.values())
            extra_count += sum(extra.values())
            for counter, samples in ((missing, missing_sample), (extra, extra_sample)):
                for item, count in counter.items():
                    if len(samples) >= 10:
                        break
                    samples.append({'sha256_utf8_text': hashlib.sha256(item).hexdigest(),
                                    'occurrences': count, 'characters': len(item.decode('utf-8'))})
            # source/tgt counters get garbage-collected per partition; bounded memory.
    if source_rows != expected: issues['source_total_vs_manifest'] = {'expected': expected, 'actual': source_rows}
    if target_rows != expected: issues['target_total_vs_manifest'] = {'expected': expected, 'actual': target_rows}
    if any(not p['pass'] for p in per_file): issues['source_part_counts'] = 'At least one part differs from manifest'
    if missing_count: issues['missing_exact_raw_json_occurrences'] = missing_count
    if extra_count: issues['unexpected_exact_raw_json_occurrences'] = extra_count
    report = {
        'result': 'PASS' if not issues else 'FAIL', 'comparison': 'EXACT Unicode raw JSON line text multiset, including duplicates; order independent',
        'source_root': str(folder.resolve()), 'target': 'bronze.app_events_raw',
        'manifest_expected_rows': expected, 'source_rows': source_rows, 'target_rows': target_rows,
        'per_source_file': per_file,
        'missing_exact_text_occurrences': missing_count,
        'unexpected_exact_text_occurrences': extra_count,
        'issues': issues,
        'samples_missing_sha256': missing_sample,
        'samples_extra_sha256': extra_sample,
        'note': 'Compares JSON Unicode TEXT, not original JSONL file bytes, file/line lineage or row order. Direct ODBC is preferred over CSV export.'
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print('APPLICATION EVENTS SOURCE-to-TARGET RECONCILIATION:', report['result'])
    print(f'Source rows: {source_rows:,} | Target rows: {target_rows:,}')
    print('Missing:', missing_count, '| Unexpected:', extra_count)
    print('Report:', report_path)
    return 0 if not issues else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--connection-string', help='Read-only SQL connection string (requires pyodbc)')
    group.add_argument('--target-csv', type=Path, help='Alternate export (must preserve full raw_json text)')
    parser.add_argument('--out', type=Path, default=Path('reports/RECONCILIATION_events.json'))
    parser.add_argument('--temp-dir', type=Path, help='Temp disk directory, at least ~2x data volume free')
    args = parser.parse_args()
    if args.temp_dir and not args.temp_dir.is_dir():
        parser.error('--temp-dir must already exist')
    try:
        return reconcile(args)
    except (OSError, ValueError, RuntimeError) as exc:
        print(f'RECONCILIATION COULD NOT RUN: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
