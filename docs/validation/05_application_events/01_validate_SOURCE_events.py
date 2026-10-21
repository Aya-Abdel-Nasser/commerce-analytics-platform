#!/usr/bin/env python3
"""Read-only, streamed JSONL discovery for Project 2 Application Events.

Usage:
  python 01_profile_application_events.py --input-dir "D:\\...\\data\\landing\\events\\prodlike\\initial"

Reads manifest.json and all manifest-listed part-*.jsonl files. Never edits inputs.
Writes a compact JSON report alongside THIS SCRIPT unless --output-json specified.
No third-party Python dependencies.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import sys

ID = re.compile(r"^EVT(\d{12})$")
REQUIRED_DOCUMENT_FIELDS = {'_source_system', '_batch', 'payload'}
EXPECTED_PAYLOAD_FIELDS = {
    'event_id','event_name','event_time_utc','received_at_utc','session_id',
    'customer_code','anonymous_id','product_sku','order_number','channel'
}

def tname(value):
    if value is None: return 'null'
    if isinstance(value,bool): return 'boolean'
    if isinstance(value,str): return 'string'
    if isinstance(value,(int,float)): return 'number'
    if isinstance(value,dict): return 'object'
    if isinstance(value,list): return 'array'
    return type(value).__name__

def utc_time(value):
    if not isinstance(value,str): return None
    try:
        dt = datetime.fromisoformat(value.replace('Z','+00:00'))
    except (ValueError,TypeError):
        return None
    if dt.tzinfo is None or dt.utcoffset() != timedelta(0):
        return None
    return dt

def run(folder:Path, output:Path, error_examples_limit:int=15):
    manifest_file = folder/'manifest.json'
    manifest = json.loads(manifest_file.read_text(encoding='utf-8-sig'))
    expected_total = int(manifest['event_records'])
    parts=manifest['parts']
    bitset=bytearray((expected_total + 7)//8)
    per_file=[]
    types=Counter()
    source_systems=Counter()
    top_fields=defaultdict(Counter)
    payload_fields=defaultdict(Counter)
    all_rows=invalid=missing=invalid_id=duplicate_id=late=invalid_dates=0
    max_line_characters = max_line_utf8_bytes = pipe_records = 0
    examples=[]

    def record_error(filename, line_num, kind, detail=''):
        if len(examples)<error_examples_limit:
            examples.append({'file':filename,'line':line_num,'issue':kind,'detail':str(detail)[:180]})

    for part in parts:
        name=part['file']; path=folder/name
        if not path.is_file():
            per_file.append({'file':name,'expected_rows':part['rows'],'actual_rows':None,'match':False})
            record_error(name,0,'file_not_found')
            continue
        rows=bad=0
        part_max_chars=part_max_utf8_bytes=part_pipe_records=0
        # Streaming scan: processes exactly one line/event at a time.
        with path.open('r',encoding='utf-8-sig',errors='strict',newline='') as f:
            for line_number,line in enumerate(f,1):
                all_rows+=1;rows+=1
                raw_text=line.rstrip('\r\n')
                part_max_chars=max(part_max_chars,len(raw_text))
                part_max_utf8_bytes=max(part_max_utf8_bytes,len(raw_text.encode('utf-8')))
                if '|' in raw_text:
                    part_pipe_records+=1
                try:
                    obj=json.loads(line)
                except (json.JSONDecodeError, UnicodeDecodeError) as ex:
                    invalid+=1;bad+=1;record_error(name,line_number,'invalid_json',ex)
                    continue
                if not isinstance(obj,dict):
                    invalid+=1;bad+=1;record_error(name,line_number,'root_not_object')
                    continue
                if not REQUIRED_DOCUMENT_FIELDS.issubset(obj.keys()):
                    missing+=1;record_error(name,line_number,'missing_root_fields',sorted(REQUIRED_DOCUMENT_FIELDS-set(obj)))
                for k,v in obj.items():
                    top_fields[k][tname(v)]+=1
                source_systems[str(obj.get('_source_system'))]+=1
                payload=obj.get('payload')
                if not isinstance(payload,dict):
                    missing+=1;record_error(name,line_number,'payload_not_object')
                    continue
                if not EXPECTED_PAYLOAD_FIELDS.issubset(payload):
                    missing+=1;record_error(name,line_number,'missing_payload_fields',sorted(EXPECTED_PAYLOAD_FIELDS-set(payload)))
                for k,v in payload.items():
                    payload_fields[k][tname(v)]+=1
                types[str(payload.get('event_name'))]+=1
                event_id=payload.get('event_id')
                m=ID.fullmatch(event_id) if isinstance(event_id,str) else None
                if not m or not 1<=int(m.group(1))<=expected_total:
                    invalid_id+=1;record_error(name,line_number,'unexpected_event_id',event_id)
                else:
                    pos=int(m.group(1))-1
                    ix=pos//8;mask=1<<(pos%8)
                    if bitset[ix]&mask:
                        duplicate_id+=1;record_error(name,line_number,'duplicate_event_id',event_id)
                    else: bitset[ix]|=mask
                event_at=utc_time(payload.get('event_time_utc'))
                received_at=utc_time(payload.get('received_at_utc'))
                if not event_at or not received_at:
                    invalid_dates+=1;record_error(name,line_number,'invalid_or_non_UTC_timestamp')
                elif (received_at-event_at) >= timedelta(hours=24):
                    late+=1
        max_line_characters=max(max_line_characters,part_max_chars)
        max_line_utf8_bytes=max(max_line_utf8_bytes,part_max_utf8_bytes)
        pipe_records+=part_pipe_records
        per_file.append({'file':name,'expected_rows':part['rows'],'actual_rows':rows,'match':rows==part['rows'],'invalid_json_lines':bad,
                         'max_json_line_characters':part_max_chars,'max_json_line_utf8_bytes':part_max_utf8_bytes,
                         'records_containing_pipe_character':part_pipe_records})
        print(f'{name}: {rows:,} rows (manifest {part["rows"]:,})',flush=True)

    distinct_ids=sum(v.bit_count() for v in bitset)
    expected_types=manifest.get('event_types',{})
    checks={
        'all_files_present':all(x['actual_rows'] is not None for x in per_file),
        'rows_match_manifest_per_file':all(x['match'] for x in per_file),
        'rows_match_manifest_total':all_rows==expected_total,
        'event_types_match_manifest':dict(types)==expected_types,
        'late_events_match_manifest':late==manifest.get('late_arriving_event_records'),
        'all_lines_valid_json_objects':invalid==0,
        'required_fields_present':missing==0,
        'ids_unique_and_in_expected_range':duplicate_id==0 and invalid_id==0 and distinct_ids==expected_total,
        'timestamps_valid_utc':invalid_dates==0,
        'pipe_delimiter_safe_for_current_informatica_mapping':pipe_records==0,
    }
    report={
        'input_folder':str(folder.resolve()),
        'source_manifest':manifest_file.name,
        'manifest_expected_total':expected_total,
        'actual_total_lines':all_rows,
        'per_file':per_file,
        'event_type_counts':dict(sorted(types.items())),
        'source_system_counts':dict(source_systems),
        'late_arriving_24h_or_more':late,
        'invalid_json_lines':invalid,
        'invalid_utc_date_records':invalid_dates,
        'max_json_line_characters': max_line_characters,
        'max_json_line_utf8_bytes': max_line_utf8_bytes,
        'records_containing_pipe_character': pipe_records,
        'missing_required_fields_records':missing,
        'duplicate_event_ids':duplicate_id,
        'invalid_event_ids':invalid_id,
        'distinct_expected_range_event_ids':distinct_ids,
        'top_level_field_types':{k:dict(v) for k,v in sorted(top_fields.items())},
        'payload_field_types':{k:dict(v) for k,v in sorted(payload_fields.items())},
        'checks':checks,
        'all_checks_passed':all(checks.values()),
        'error_examples':examples,
        'note':'Profile is based on real files. Manifest alone does not prove their contents.'
    }
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'\nTotal rows: {all_rows:,} | expected: {expected_total:,}')
    print(f'Event IDs duplicated: {duplicate_id} | Invalid JSON lines: {invalid}')
    print(f'Late events >=24h: {late:,} | expected: {manifest.get("late_arriving_event_records"):,}')
    print('Max JSON text characters:', max_line_characters, '| Max UTF-8 bytes:',max_line_utf8_bytes)
    print('Records containing pipe delimiter:',pipe_records)
    print('RESULT:', 'PASS' if report['all_checks_passed'] else 'NEEDS REVIEW')
    print('Report:',output.resolve())
    return 0 if report['all_checks_passed'] else 1

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--input-dir',required=True,help='Directory containing manifest.json and part-*.jsonl')
    ap.add_argument('--output-json',default=None,help='Path for report; defaults to next to this script')
    args=ap.parse_args()
    folder=Path(args.input_dir)
    out=Path(args.output_json) if args.output_json else Path(__file__).with_name('application_events_profile_actual.json')
    if not folder.is_dir():
        ap.error('Input directory not found: '+str(folder))
    try:
        return run(folder,out)
    except Exception as ex:
        print(f'ERROR: {type(ex).__name__}: {ex}',file=sys.stderr)
        return 2

if __name__=='__main__':
    sys.exit(main())
