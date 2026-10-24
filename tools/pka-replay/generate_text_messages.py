"""Create a private regression from the real session ending in B4 mode 52.

Keep the input CAM, generated CAM/manifest and packet bodies outside Git.
Only received messages are copied; the original session is never overwritten.
"""
import argparse
import json
from pathlib import Path
import struct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    received = [(int(t), bytes.fromhex(h)) for direction, t, h in
                (line.split() for line in args.session.read_text().splitlines())
                if direction == '<']
    final = received[-1][1]
    assert final[:3] == b'\xb4\x00\x34'
    length = struct.unpack_from('<H', final, 3)[0]
    assert len(final) == length + 5, 'Unexpected text message boundary'
    original_text_hex = final[5:].hex()

    def text(mode, value):
        data = value.encode('utf-8')
        return struct.pack('<HBH', 0xb4, mode, len(data)) + data

    # Empty strings must stop before the following opcode too.
    packet = text(0x34, '') + text(0x1f, '')
    packet += text(0x1f, 'PKA loot regression')
    packet += text(0x34, 'PKA attention regression')
    packet += struct.pack('<HBHHBB', 0x78, 4, 869, 0x5432, 0, 0)
    events = [(t // 8, data) for t, data in received]
    completion = events[-1][0] + 1000
    events.extend(((completion, packet), (completion + 600000, b'\x1e\x00')))
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'text-repro.cam').write_text(
        ''.join(f'< {t} {data.hex()}\n' for t, data in events), encoding='ascii')
    (args.output/'text-final.bin').write_bytes(final)
    (args.output/'text-batches.bin').write_bytes(packet)
    (args.output/'text-manifest.json').write_text(json.dumps({
        'receivedPackets': len(received), 'lastRealMs': received[-1][0],
        'completionMs': completion, 'originalTextHex': original_text_hex,
        'inventoryId': 869, 'inventorySubtype': 0x5432,
    }, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(received)} received messages; completion at {completion}ms.')


if __name__ == '__main__':
    main()
