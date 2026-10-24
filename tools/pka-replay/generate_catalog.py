"""Build offline received-only catalog fixtures from audited metadata and a seed.

The seed is a private accepted login/world recording. No outgoing authentication
is copied. Generated inventory/outfit packets test catalog ID coverage, not
real-server behavior or every sprite's GPU rendering.
"""
import argparse
import json
from pathlib import Path
import struct

from generate_helper_cases import cases, string, u8, u16, u32, u64


def packet(payload):
    # CAM stores logical received buffers after transport framing. Only the
    # first challenge carries the initial size check; later buffers do not.
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--records', type=Path, required=True)
    parser.add_argument('--seed', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.records.read_text().splitlines()]
    args.output.mkdir(parents=True, exist_ok=True)
    seed, player_id = [], None
    for line in args.seed.read_text().splitlines():
        if line.startswith('< '):
            _, timestamp, hexdata = line.split()
            data = bytes.fromhex(hexdata)
            seed.append((int(timestamp), data))
            if len(data) > 8 and data[:2] == u16(0x0A):
                player_id = struct.unpack_from('<I', data, 2)[0]
                break
    assert player_id and len(seed) == 2, 'Expected a challenge and login/world packet seed'

    def save(name, events):
        with (args.output/name).open('w', encoding='ascii') as sink:
            for time, data in seed + events:
                sink.write(f'< {time} {data.hex()}\n')

    def item(row, mode=0):
        # Deprecated chargeable does not add a count. PKA's three real count
        # categories all use U16, as measured in DX FUN_140799cd0.
        value = u16(row['id']) + (u16(0x1234) if row['wireFlags'] & 7 else b'')
        value += u8(mode)
        if mode == 1:
            value += string(b'coverage') + string(b'description')
            if row['id'] == 0x25A0:
                value += string(b'special')
            value += u8(9) + u16(0xA1B2)
        elif mode == 3:
            value += string(b'coverage')
        return value + u8(0)

    items = [r for r in rows if r['category'] == 0]
    outfit_max = max(r['id'] for r in rows if r['category'] == 1)
    fluid = next(r for r in items if r['id'] == 869)
    ground = next(r for r in items if r['id'] == 100)
    save('fluid-width-repro.cam', [(5000, packet(u16(0x78)+u8(4)+item(fluid)+u16(0x78)+u8(5)+item(ground))), (30000, u16(0x1E))])

    events, timestamp = [], 5000
    for offset in range(0, len(items), 100):
        batch = items[offset:offset+100]
        payload = b''.join(u16(0x78)+u8(4)+item(row, (0, 1, 3)[row['id'] % 3]) for row in batch)
        events.append((timestamp, packet(payload)))
        timestamp += 100
    for offset in range(1, outfit_max+1, 20):
        payload = b''
        for look in range(offset, min(offset+20, outfit_max+1)):
            payload += u16(0x8E)+u32(player_id)+u16(look)+bytes((1, 2, 3, 4, 0))+u64(0)+u64(0)+string(b'coverage-outfit')
        events.append((timestamp, packet(payload)))
        timestamp += 100
    # Exercise the formerly broken zero-look branch with a nonempty string,
    # then restore a real final look; a later inventory sentinel checks alignment.
    payload = u16(0x8E)+u32(player_id)+u16(0)+u16(0)+string(b'invisible')
    payload += u16(0x8E)+u32(player_id)+u16(outfit_max)+bytes((1, 2, 3, 4, 0))+u64(0)+u64(0)+string(b'last')
    payload += u16(0x78)+u8(5)+item(ground)
    events.append((timestamp, packet(payload)))
    timestamp += 100
    # Keep the replay alive while a slower device drains queued callbacks.
    events.append((timestamp+600000, u16(0x1E)))
    save('catalog-coverage.cam', events)
    (args.output/'catalog-manifest.json').write_text(json.dumps(dict(items=len(items), outfits=outfit_max,
        receivedPackets=len(seed)+len(events), lastCatalogMs=timestamp-100, completionMs=timestamp+3000,
        expectedInventory4=items[-1]['id'], expectedInventory5=100, expectedOutfit=outfit_max), indent=2))
    print(f'Catalog fixture: {len(items)} item IDs, {outfit_max} outfits, ends at {timestamp} ms.')


if __name__ == '__main__':
    main()
