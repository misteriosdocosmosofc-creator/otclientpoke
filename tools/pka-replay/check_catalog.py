"""Check every synthetic catalog packet with the production shared wire reader."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', type=Path, required=True)
    parser.add_argument('--cam', type=Path, required=True)
    parser.add_argument('--flags', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    packets, counts = 0, Counter()
    report = dict(status='passed')
    # The first two received buffers are the private, previously tested seed.
    lines = [line.split() for line in args.cam.read_text().splitlines() if line.startswith('< ')][2:]
    with tempfile.TemporaryDirectory(prefix='pka-catalog-') as temporary:
        payload = Path(temporary)/'packet.bin'
        trace = Path(temporary)/'unused.jsonl'
        for _, timestamp, hexdata in lines:
            data = bytes.fromhex(hexdata)
            payload.write_bytes(data)
            result = subprocess.run([str(args.replay), str(payload), str(args.flags), '32', '20', str(trace), '--packet'], capture_output=True, text=True, timeout=20)
            if result.returncode:
                report.update(status='failed', timestampMs=int(timestamp), packetBytes=len(data), error=result.stderr.strip())
                break
            for opcode in re.findall(r'tail opcode=(0x[0-9a-f]+)', result.stdout):
                counts[opcode] += 1
            packets += 1
    report.update(packets=packets, opcodeCounts=dict(counts))
    args.output.write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report))
    raise SystemExit(0 if report['status'] == 'passed' else 1)


if __name__ == '__main__':
    main()
