"""Prepare a private crowded-tile regression from received CAM messages only."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-position', type=int, nargs=3, required=True)
    parser.add_argument('--probe-tile', type=int, nargs=3, required=True)
    parser.add_argument('--probe-count', type=int, required=True)
    parser.add_argument('--speed', type=int, default=4, help='Replay speed divisor; use 1 to preserve original receive timing')
    args = parser.parse_args()
    if args.speed < 1:
        parser.error('--speed must be at least 1')
    received = [(int(t), bytes.fromhex(h)) for direction, t, h in
                (line.split() for line in args.session.read_text().splitlines())
                if direction == '<']
    if not received:
        raise ValueError('No received messages')
    args.output.mkdir(parents=True, exist_ok=False)
    completion = received[-1][0] // args.speed + 5000
    events = [(t // args.speed, body) for t, body in received]
    events.append((completion + 600000, b'\x1e\x00'))
    (args.output / 'crowded-movement.cam').write_text(
        ''.join(f'< {t} {body.hex()}\n' for t, body in events), encoding='ascii')
    (args.output / 'crowded-manifest.json').write_text(json.dumps({
        'receivedPackets': len(received), 'lastRealMs': received[-1][0],
        'completionMs': completion, 'expectedPosition': args.expected_position,
        'probeTile': args.probe_tile, 'probeCount': args.probe_count,
        'speed': args.speed,
    }, indent=2))
    print(f'Prepared {len(received)} received messages; completion at {completion}ms.')


if __name__ == '__main__':
    main()
