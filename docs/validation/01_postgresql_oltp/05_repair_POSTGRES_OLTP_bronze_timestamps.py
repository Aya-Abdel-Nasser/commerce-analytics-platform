#!/usr/bin/env python3
"""Controlled one-time repair of PostgreSQL TIMESTAMPTZ -> SQL Server Bronze DATETIME2.

RUN FROM THE PROJECT ROOT, with the read-only 04_reconcile_SOURCE_TARGET_postgresql_oltp.py
in the same directory as this file:
    python docs/validation/01_postgresql_oltp/05_repair_POSTGRES_OLTP_bronze_timestamps.py --table products
    python docs/validation/01_postgresql_oltp/05_repair_POSTGRES_OLTP_bronze_timestamps.py --table products --apply --confirm APPLY_UTC_TIMESTAMPS
    python docs/validation/01_postgresql_oltp/05_repair_POSTGRES_OLTP_bronze_timestamps.py
    python docs/validation/01_postgresql_oltp/05_repair_POSTGRES_OLTP_bronze_timestamps.py --apply --confirm APPLY_UTC_TIMESTAMPS

Default mode is READ-ONLY dry-run. Apply mode:
- validates every source/target row and non-temporal field; aborts on missing/duplicate PKs
- stages exact UTC datetime values from PostgreSQL by primary key
- commits a uniquely named, persistent backup of previous Bronze datetime values FIRST
- updates ONLY columns below in a transaction, with a stale-value guard
- leaves all lineage columns, other fields, and control.etl_run_log unchanged
- emits a report and a generated rollback SQL file for each changed table

STOP ingestion/CDC and keep source and target static throughout the repair and final comparison.
Existing Informatica taskflows are NOT changed: fix their UTC handling before future reloads.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from getpass import getpass
import importlib.util
import json
import os
from pathlib import Path
import sys
from uuid import uuid4
from typing import Any

BASE_DIR = Path(__file__).resolve().parent
READONLY_SCRIPT = BASE_DIR / '04_reconcile_SOURCE_TARGET_postgresql_oltp.py'
FIX_COLUMNS = {
    'products': ('created_at', 'updated_at'),
    'customers': ('created_at', 'updated_at'),
    'orders': ('order_date', 'updated_at'),
    'payments': ('payment_date',),
}
CONFIRM = 'APPLY_UTC_TIMESTAMPS'


def load_reconciliation():
    if not READONLY_SCRIPT.is_file():
        raise RuntimeError(f'Required original read-only script not found next to this file: {READONLY_SCRIPT.name}')
    spec = importlib.util.spec_from_file_location('original_oltp_reconciliation', READONLY_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError('Cannot load original reconciliation helpers')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args():
    p = argparse.ArgumentParser(description='Preview or safely apply exact source-UTC Bronze timestamp repairs')
    p.add_argument('--table', choices=tuple(FIX_COLUMNS), help='Repair just one table; products is a good pilot')
    p.add_argument('--apply', action='store_true', help='Actually update Bronze (not read-only)')
    p.add_argument('--confirm', default='', help=f'Required with --apply: {CONFIRM}')
    p.add_argument('--env-file', default='infra/environments/dev/.env.dev')
    p.add_argument('--pg-host', default='127.0.0.1')
    p.add_argument('--pg-port', type=int)
    p.add_argument('--sqlserver', default=r'.\SQLEXPRESS')
    p.add_argument('--database', default='commerce_warehouse_dev')
    p.add_argument('--batch-size', type=int, default=1000)
    p.add_argument('--report-dir', default='docs/validation/reports')
    args = p.parse_args()
    if args.apply and args.confirm != CONFIRM:
        p.error(f'Applying changes requires --confirm {CONFIRM}')
    if not args.apply and args.confirm:
        p.error('--confirm can only be used with --apply')
    if args.batch_size < 100 or args.batch_size > 5000:
        p.error('--batch-size must be between 100 and 5000')
    return args


def qlist(r, columns, engine):
    return ', '.join(r.qi(c, engine) for c in columns)


def utc_naive(value):
    if value is None:
        return None
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise RuntimeError('Expected timezone-aware PostgreSQL TIMESTAMPTZ')
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def rollback_sql(r, spec, timestamp_cols, backup_table, count, database):
    pk = spec['pk'][0]
    target = f"[bronze].{r.qi(spec['target'], 'sqlserver')}"
    backup = f'[validation_probe].{r.qi(backup_table, "sqlserver")}'
    setters = ', '.join(f't.{r.qi(c,"sqlserver")} = b.{r.qi(c,"sqlserver")}' for c in timestamp_cols)
    return f'''-- EMERGENCY ROLLBACK. Manually review before running; stop all writers first.
-- Backup table: {backup} | expected saved keys: {count}
-- This restores ONLY the temporal columns for keys saved by this run.
USE {r.qi(database, "sqlserver")};
GO
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @expected BIGINT = {count};
IF (SELECT COUNT_BIG(*) FROM {backup}) <> @expected
    THROW 51001, 'Backup row count changed; aborting rollback', 1;
IF (SELECT COUNT_BIG(*) FROM {backup} b INNER JOIN {target} t ON t.{r.qi(pk,'sqlserver')} = b.{r.qi(pk,'sqlserver')}) <> @expected
    THROW 51002, 'Backup keys missing in target; aborting rollback', 1;
UPDATE t SET {setters}
FROM {target} AS t
JOIN {backup} AS b ON t.{r.qi(pk,'sqlserver')} = b.{r.qi(pk,'sqlserver')};
IF @@ROWCOUNT <> @expected
    THROW 51003, 'Restored row count unexpected; aborting rollback', 1;
COMMIT;
GO
'''


def scan_table(r, pg_conn, sql_reader, writer, name, batch_size, suffix, apply, result, report_dir, database):
    spec = r.TABLES[name]
    pk = spec['pk'][0]
    temporal = FIX_COLUMNS[name]
    src_metadata = r.pg_metadata(pg_conn, name)
    dst_metadata = r.sql_metadata(sql_reader, spec['target'])
    columns = r.verify_contract(src_metadata, dst_metadata, spec['pk'], r.pg_primary_key(pg_conn, name))
    actual_temporal = {str(row[0]) for row in src_metadata if str(row[1]).lower() == 'timestamp with time zone'}
    if actual_temporal != set(temporal):
        raise RuntimeError(f'Timestamp column set changed for {name}: {sorted(actual_temporal)}')
    pos = {c: i for i, c in enumerate(columns)}
    src_q = f'SELECT {qlist(r, columns,"postgres")} FROM "commerce".{r.qi(name,"postgres")} ORDER BY {r.qi(pk,"postgres")}'
    dst_q = f'SELECT {qlist(r, columns,"sqlserver")} FROM [bronze].{r.qi(spec["target"],"sqlserver")} ORDER BY {r.qi(pk,"sqlserver")}'
    pg_cur = pg_conn.cursor(name=f'utc_fix_{name}_{suffix[:8]}')
    pg_cur.itersize = batch_size
    sql_cur = sql_reader.cursor()
    stage_name = f'utc_stage_{name}_{suffix}'
    stage = f'[validation_probe].{r.qi(stage_name,"sqlserver")}'
    dest = f'[bronze].{r.qi(spec["target"],"sqlserver")}'
    rows_scanned = 0
    mismatch_count = 0
    diffs = {c: 0 for c in temporal}
    batch = []
    try:
        if apply:
            coldefs = ', '.join(f'{r.qi(col,"sqlserver")} DATETIME2(6) NULL' for col in temporal)
            writer.cursor().execute(f'CREATE TABLE {stage} ({r.qi(pk,"sqlserver")} BIGINT NOT NULL PRIMARY KEY, {coldefs})')
            insert_q = f'INSERT INTO {stage} ({qlist(r,[pk,*temporal],"sqlserver")}) VALUES ({", ".join("?" for _ in range(1+len(temporal)))})'
            insert_cur = writer.cursor()
            insert_cur.fast_executemany = True

        pg_cur.execute(src_q)
        sql_cur.execute(dst_q)
        source = r.OrderedStream(pg_cur, batch_size, (pos[pk],))
        target = r.OrderedStream(sql_cur, batch_size, (pos[pk],))
        a, b = source.next(), target.next()
        while a is not None or b is not None:
            if a is None or b is None or a[0] != b[0]:
                raise RuntimeError(f'PK mismatch or missing row in {name}: abort (no updates)')
            for col in columns:
                if col not in temporal and r.normalized(a[1][pos[col]]) != r.normalized(b[1][pos[col]]):
                    raise RuntimeError(f'Non-temporal value mismatch: {name}.{col} (aborting repair)')
            changed = False
            for col in temporal:
                if r.normalized(a[1][pos[col]]) != r.normalized(b[1][pos[col]]):
                    diffs[col] += 1
                    changed = True
            if changed:
                mismatch_count += 1
                if apply:
                    batch.append((r.as_integral_key(a[1][pos[pk]]), *[utc_naive(a[1][pos[col]]) for col in temporal]))
                    if len(batch) >= batch_size:
                        insert_cur.executemany(insert_q, batch)
                        batch.clear()
            rows_scanned += 1
            if rows_scanned % 100_000 == 0:
                print(f'  {name}: {rows_scanned:,} keys checked', flush=True)
            a, b = source.next(), target.next()
        if rows_scanned != spec['expected']:
            raise RuntimeError(f'{name}: expected {spec["expected"]:,} rows, found {rows_scanned:,}')
        if apply and batch:
            insert_cur.executemany(insert_q, batch)
            batch.clear()
    except Exception:
        if apply:
            writer.rollback()  # Rolls back stage creation and partial staged rows.
        raise
    finally:
        sql_cur.close()
        pg_cur.close()

    result.update({
        'table': name, 'bronze_table': f'bronze.{spec["target"]}',
        'rows_checked': rows_scanned, 'timestamp_mismatch_rows': mismatch_count,
        'timestamp_mismatches_by_column': diffs, 'mode': 'APPLY' if apply else 'DRY_RUN',
        'backup_table': None, 'updated_rows': 0,
    })
    print(f'  {name}: scanned={rows_scanned:,}, rows_to_fix={mismatch_count:,}, columns={diffs}', flush=True)
    if not apply:
        result['status'] = 'DRY_RUN_PASS'
        return

    if mismatch_count == 0:
        writer.cursor().execute(f'DROP TABLE {stage}')
        writer.commit()
        print(f'  {name}: already correct, no update / backup required', flush=True)
        result['status'] = 'ALREADY_CORRECT'
        return

    backup_name = f'utc_backup_{name}_{suffix}'
    backup = f'[validation_probe].{r.qi(backup_name,"sqlserver")}'
    quoted_pk = r.qi(pk,'sqlserver')
    allcols = qlist(r, [pk,*temporal], 'sqlserver')
    try:
        # Backup from TARGET and commit before changing the target. Leave it for audit/rollback.
        writer.cursor().execute(
            f'SELECT {", ".join("t."+r.qi(c,"sqlserver") for c in [pk,*temporal])} '
            f'INTO {backup} FROM {dest} t JOIN {stage} s ON t.{quoted_pk} = s.{quoted_pk}'
        )
        backup_count = writer.cursor().execute(f'SELECT COUNT_BIG(*) FROM {backup}').fetchone()[0]
        stage_count = writer.cursor().execute(f'SELECT COUNT_BIG(*) FROM {stage}').fetchone()[0]
        if int(backup_count) != mismatch_count or int(stage_count) != mismatch_count:
            raise RuntimeError('Backup/staging count mismatch, refusing to update')
        writer.commit()  # Permanent backup survives any later failure.
        result['backup_table'] = f'validation_probe.{backup_name}'
        result['status'] = 'BACKUP_COMMITTED'
        report_dir.mkdir(parents=True, exist_ok=True)
        restore = report_dir / f'UTC_REPAIR_ROLLBACK_{name}_{suffix}.sql'
        restore.write_text(rollback_sql(r, spec, temporal, backup_name, mismatch_count, database), encoding='utf-8')
        result['rollback_sql'] = str(restore)
        print(f'  {name}: committed backup {result["backup_table"]} ({backup_count:,} rows)', flush=True)

        # NULL-safe optimistic concurrency guard: current values must equal saved backup.
        dst_dates = ', '.join('t.'+r.qi(c,'sqlserver') for c in temporal)
        old_dates = ', '.join('b.'+r.qi(c,'sqlserver') for c in temporal)
        new_dates = ', '.join('s.'+r.qi(c,'sqlserver') for c in temporal)
        setters = ', '.join(f't.{r.qi(c,"sqlserver")} = s.{r.qi(c,"sqlserver")}' for c in temporal)
        update_stmt = (
            f'UPDATE t SET {setters} FROM {dest} AS t WITH (UPDLOCK, HOLDLOCK) '
            f'JOIN {stage} AS s ON t.{quoted_pk} = s.{quoted_pk} '
            f'JOIN {backup} AS b ON t.{quoted_pk} = b.{quoted_pk} '
            f'WHERE NOT EXISTS (SELECT {dst_dates} EXCEPT SELECT {old_dates}) '
            f'AND EXISTS (SELECT {dst_dates} EXCEPT SELECT {new_dates})'
        )
        cur = writer.cursor()
        cur.execute('SET XACT_ABORT ON')
        cur.execute(update_stmt)
        affected = cur.rowcount
        if affected != mismatch_count:
            raise RuntimeError(f'Concurrent change or update count unexpected: {affected} vs {mismatch_count} (rolling back)')
        writer.commit()
        result['updated_rows'] = affected
        result['status'] = 'UPDATED_NEEDS_RECONCILIATION'
        print(f'  {name}: UPDATED {affected:,} rows; backup retained', flush=True)
        # Stage has served its purpose. Preserve the permanent backup.
        writer.cursor().execute(f'DROP TABLE {stage}')
        writer.commit()
        return
    except Exception:
        writer.rollback()
        # Backup may have been committed; keep it, and stage, for incident investigation.
        raise


def main():
    args = parse_args()
    try:
        import psycopg2
        import pyodbc
        r = load_reconciliation()
    except (ImportError, RuntimeError) as e:
        print(f'Setup issue: {e}', file=sys.stderr)
        return 2
    env = r.parse_local_env(Path(args.env_file))
    pg_user = os.getenv('POSTGRES_USER') or env.get('POSTGRES_USER')
    pg_db = os.getenv('POSTGRES_DB') or env.get('POSTGRES_DB', 'commerce_oltp_dev')
    pg_port = args.pg_port or int(os.getenv('POSTGRES_HOST_PORT') or env.get('POSTGRES_HOST_PORT', '15432'))
    pg_password = os.getenv('POSTGRES_PASSWORD') or env.get('POSTGRES_PASSWORD')
    if not pg_user:
        print('POSTGRES_USER missing in local .env.dev', file=sys.stderr)
        return 2
    if pg_password is None:
        pg_password = getpass('PostgreSQL password (hidden): ')
    token = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')+'_'+uuid4().hex[:6]
    report_dir = Path(args.report_dir)
    selected = [args.table] if args.table else list(FIX_COLUMNS)
    report = {
        'run_token': token, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
        'mode': 'APPLY' if args.apply else 'DRY_RUN', 'status': 'ERROR',
        'source': f'{pg_db}.commerce', 'target_database': args.database,
        'tables': [], 'note': 'No credentials or row values included. Original Informatica pipelines unchanged.',
    }
    pg_conn = read_conn = write_conn = None
    try:
        pg_conn = psycopg2.connect(host=args.pg_host, port=pg_port, dbname=pg_db,
                                   user=pg_user, password=pg_password, connect_timeout=15,
                                   options='-c timezone=UTC')
        pg_conn.set_session(isolation_level='REPEATABLE READ', readonly=True, autocommit=False)
        conn_str = (f'DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={args.sqlserver};'
                    f'DATABASE={args.database};Trusted_Connection=yes;TrustServerCertificate=yes;')
        read_conn = pyodbc.connect(conn_str+'ApplicationIntent=ReadOnly;', autocommit=True, timeout=30)
        if args.apply:
            write_conn = pyodbc.connect(conn_str, autocommit=False, timeout=120)
            probe = write_conn.cursor().execute('SELECT SCHEMA_ID(N\'validation_probe\')').fetchone()[0]
            if probe is None:
                raise RuntimeError('validation_probe schema missing; create it before applying')
            write_conn.commit()
        for name in selected:
            print(f'\n{name}: validate full rows, keys, and timestamps (UTC)...', flush=True)
            result = {'table': name, 'status': 'PREFLIGHT_IN_PROGRESS'}
            report['tables'].append(result)
            scan_table(r, pg_conn, read_conn, write_conn, name, args.batch_size,
                       token, args.apply, result, report_dir, args.database)
        report['status'] = 'APPLIED_NEEDS_RECONCILIATION' if args.apply else 'DRY_RUN_PASS'
    except Exception as ex:
        if write_conn is not None:
            try:
                write_conn.rollback()
            except Exception:
                pass
        report['status'] = 'PARTIAL_OR_ERROR' if args.apply else 'ERROR'
        report['error_type'] = type(ex).__name__
        print(f'ERROR: {type(ex).__name__}: {ex}', file=sys.stderr)
    finally:
        if write_conn is not None:
            write_conn.close()
        if read_conn is not None:
            read_conn.close()
        if pg_conn is not None:
            try:
                pg_conn.rollback()
            finally:
                pg_conn.close()
        report['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
        report_dir.mkdir(parents=True, exist_ok=True)
        outfile = report_dir / f'UTC_TIMESTAMP_REPAIR_{token}.json'
        outfile.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
        print(f'\n{report["status"]} | Report: {outfile}', flush=True)
        if args.apply:
            print('NEXT: run the ORIGINAL 04_reconcile_SOURCE_TARGET_postgresql_oltp.py and require OVERALL PASS.', flush=True)
    return 0 if report['status'] in ('DRY_RUN_PASS', 'APPLIED_NEEDS_RECONCILIATION') else 1


if __name__ == '__main__':
    sys.exit(main())
