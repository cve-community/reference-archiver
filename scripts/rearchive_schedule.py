#!/usr/bin/env python3
"""Re-archive ledger (v2/schedule.json) operations. Stdlib only.

The PRD (2.4) asks for snapshots 0, 3, 10, 30 and 90 days after a CVE record
is published. Intervals are therefore measured from `date_published`; an
interval whose date had already passed when the first snapshot was taken is
skipped, because the 0-day snapshot is the only one still possible. A CVE
archived long after publication gets exactly one snapshot. When several
intervals are overdue at once, one catch-up snapshot covers all of them.

Entries without `date_published` fall back to `first_archived` as the anchor
(the pre-2026-10-27 behaviour); the rearchive workflow back-fills the field.

    rearchive_schedule.py due      --schedule S --max N            -> JSON on stdout
    rearchive_schedule.py mark     --schedule S --cves JSON --out O
    rearchive_schedule.py register --schedule S --cves JSON --dates TSV --out O
"""
import argparse
import json
import sys
from datetime import datetime, timedelta, timezone

INTERVALS = [3, 10, 30, 90]


def parse_ts(value):
    text = value.strip().replace('Z', '+00:00')
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        parsed = datetime.fromisoformat(text[:19] + '+00:00')
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def owed_intervals(entry):
    """[(interval, due_date)] still owed, overdue or not, oldest first."""
    first_archived = parse_ts(entry['first_archived'])
    anchor = parse_ts(entry['date_published']) if entry.get('date_published') else first_archived
    anchor = min(anchor, first_archived)
    completed = set(entry.get('completed_intervals', []))
    owed = []
    for interval in INTERVALS:
        due = anchor + timedelta(days=interval)
        if interval in completed or due < first_archived:
            continue
        owed.append((interval, due))
    return owed


def overdue_intervals(entry, now):
    return [(i, due) for i, due in owed_intervals(entry) if now >= due]


def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except FileNotFoundError:
        return {'entries': []}


def save(schedule, path, now):
    schedule['entries'] = sorted(schedule.get('entries', []), key=lambda e: e['cve_id'])
    schedule['last_updated'] = now.strftime('%Y%m%d-%H%M%S')
    with open(path, 'w') as fh:
        json.dump(schedule, fh, indent=2)


def cmd_due(args, now):
    schedule = load(args.schedule)
    entries = schedule.get('entries', [])
    details = []
    for entry in entries:
        overdue = overdue_intervals(entry, now)
        if overdue:
            details.append({
                'cve_id': entry['cve_id'],
                'intervals': [i for i, _ in overdue],
                'due_since': overdue[0][1].strftime('%Y-%m-%dT%H:%M:%SZ'),
            })
    details.sort(key=lambda d: d['cve_id'])
    selected = details[:args.max]
    nothing_left = sum(1 for e in entries if not owed_intervals(e))
    json.dump({
        'total_entries': len(entries),
        'total_due': len(details),
        'nothing_left': nothing_left,
        'missing_date_published': sum(1 for e in entries if not e.get('date_published')),
        'due': [d['cve_id'] for d in selected],
        'details': selected,
    }, sys.stdout)
    sys.stdout.write('\n')


def cmd_mark(args, now):
    schedule = load(args.schedule)
    by_id = {e['cve_id']: e for e in schedule.get('entries', [])}
    marked = 0
    for cve_id in json.loads(args.cves):
        entry = by_id.get(cve_id)
        if not entry:
            continue
        completed = set(entry.get('completed_intervals', []))
        for interval, _ in overdue_intervals(entry, now):
            completed.add(interval)
        entry['completed_intervals'] = sorted(completed)
        entry['last_rearchived'] = now.strftime('%Y%m%d-%H%M%S')
        marked += 1
    save(schedule, args.out, now)
    entries = schedule['entries']
    done = sum(1 for e in entries if not owed_intervals(e))
    print(f"Schedule: marked {marked} CVEs; {len(entries)} entries, {done} with nothing left to re-archive",
          file=sys.stderr)


def cmd_register(args, now):
    schedule = load(args.schedule)
    existing = {e['cve_id'] for e in schedule.get('entries', [])}
    dates = {}
    if args.dates:
        with open(args.dates) as fh:
            for line in fh:
                parts = line.rstrip('\n').split('\t')
                if len(parts) == 2 and parts[1]:
                    dates[parts[0]] = parts[1]
    added = 0
    for cve_id in json.loads(args.cves):
        if cve_id in existing:
            continue
        entry = {
            'cve_id': cve_id,
            'first_archived': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'completed_intervals': [0],
            'last_rearchived': now.strftime('%Y%m%d-%H%M%S'),
        }
        if cve_id in dates:
            entry['date_published'] = dates[cve_id]
        schedule.setdefault('entries', []).append(entry)
        existing.add(cve_id)
        added += 1
    save(schedule, args.out, now)
    print(f"Schedule: added {added} new CVEs ({len(schedule['entries'])} total)", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--now', help='override current time (ISO 8601), for tests')
    sub = parser.add_subparsers(dest='command', required=True)

    p_due = sub.add_parser('due')
    p_due.add_argument('--schedule', required=True)
    p_due.add_argument('--max', type=int, required=True)

    p_mark = sub.add_parser('mark')
    p_mark.add_argument('--schedule', required=True)
    p_mark.add_argument('--cves', required=True, help='JSON array of CVE IDs')
    p_mark.add_argument('--out', required=True)

    p_reg = sub.add_parser('register')
    p_reg.add_argument('--schedule', required=True)
    p_reg.add_argument('--cves', required=True, help='JSON array of CVE IDs')
    p_reg.add_argument('--dates', help='TSV of "<CVE-ID>\\t<datePublished>"')
    p_reg.add_argument('--out', required=True)

    args = parser.parse_args()
    now = parse_ts(args.now) if args.now else datetime.now(timezone.utc)
    {'due': cmd_due, 'mark': cmd_mark, 'register': cmd_register}[args.command](args, now)


if __name__ == '__main__':
    main()
