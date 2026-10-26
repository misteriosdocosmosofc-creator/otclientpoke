"""Extract signed displacements from the verified private PKA DAT for native QA."""
import argparse
import hashlib
import json
from pathlib import Path
from audit_assets import dat_records

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dat', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
signature, counts, records = dat_records(args.dat)
entries = []
negative = 0
for row in records:
    point = row['displacement']
    if point['x'] or point['y'] or row['id'] == (100 if row['category'] == 0 else 1):
        entries.append({'category': row['category'], 'id': row['id'], **point})
        negative += point['x'] < 0 or point['y'] < 0
result = {
    'datSignature': signature, 'datSha256': hashlib.sha256(args.dat.read_bytes()).hexdigest(),
    'highestIds': counts, 'negativeEntries': negative, 'entries': entries,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, separators=(',', ':')), encoding='utf8')
print(json.dumps({'entries': len(entries), 'negativeEntries': negative}))
