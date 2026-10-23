"""Compare shared C++ wire-reader boundaries with a trace of the original client."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('capture', type=Path)
parser.add_argument('replay', type=Path)
args = parser.parse_args()
manifest = json.loads((args.capture / 'manifest.json').read_text(encoding='utf-8'))
base = manifest['fullMap']['cursor'] - 5
expected = {kind: [] for kind in ('tile', 'item', 'creature')}
starts = {kind: [] for kind in expected}
for line in (args.capture / 'reader-events.jsonl').open(encoding='utf-8'):
    event = json.loads(line)
    for kind in expected:
        if event['event'] == kind + '_enter':
            starts[kind].append(event['cursorBefore'] - base - (0 if kind == 'tile' else 2))
        elif event['event'] == kind + '_exit':
            expected[kind].append((starts[kind].pop(), event['cursorAfter'] - base))
actual = {kind: [] for kind in expected}
for line in args.replay.open(encoding='utf-8'):
    event = json.loads(line)
    actual[event['kind']].append((event['start'], event['end']))
for kind in expected:
    if expected[kind] != actual[kind]:
        for index, pair in enumerate(zip(expected[kind], actual[kind])):
            if pair[0] != pair[1]:
                raise SystemExit(f'First {kind} mismatch #{index}: PC={pair[0]}, replay={pair[1]}')
        raise SystemExit(f'{kind} count mismatch: PC={len(expected[kind])}, replay={len(actual[kind])}')
print(json.dumps({'status': 'all_boundaries_match', **{kind: len(events) for kind, events in actual.items()}}))
