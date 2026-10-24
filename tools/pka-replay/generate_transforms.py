"""Retain a private received session, accelerate its timing, then check batches.

The input must end in the measured 16-byte single creature transform that
exposed the missing mode byte. No outgoing authentication is copied.
"""
import argparse
import json
from pathlib import Path
import struct

from generate_helper_cases import u8, u16, u32


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    received = [(int(t), bytes.fromhex(h)) for direction, t, h in
                (line.split() for line in args.session.read_text().splitlines())
                if direction == '<']
    last = received[-1][1]
    assert len(last) == 16 and last[:3] == b'\x6b\x00\x00' and last[9:11] == b'\x63\x00', 'Unexpected failure layout'
    position = struct.unpack_from('<HHB', last, 3)
    creature_id, direction = struct.unpack_from('<IB', last, 11)
    assert received[1][1][:2] == u16(0x0a)
    player_id = struct.unpack_from('<I', received[1][1], 2)[0]
    args.output.mkdir(parents=True, exist_ok=True)
    events = [(timestamp // 8, data) for timestamp, data in received]
    end = events[-1][0] + 1000

    def turn(value):
        return u16(0xffff) + u32(player_id) + u16(0x63) + u32(player_id) + u8(value)

    # A missing mapped thing must not prevent the remaining batch from being read.
    missing = struct.pack('<HHBB', 65000, 65000, 7, 0) + u16(100) + bytes((0, 0))
    batch = u16(0x6b) + u8(1) + u16(0)
    batch += u16(0x6b) + u8(1) + u16(1) + turn(0)
    batch += u16(0x6b) + u8(1) + u16(3) + missing + turn(1) + turn(3)
    # Non-batch mode values also take the single-record branch in DX.
    for mode in (2, 255):
        batch += u16(0x6b) + u8(mode) + turn(3)
    batch += u16(0x78) + u8(4) + u16(869) + u16(0x4321) + bytes((0, 0))
    events.extend(((end, batch), (end + 600000, u16(0x1e))))
    (args.output/'transform-repro.cam').write_text(''.join(f'< {t} {data.hex()}\n' for t, data in events), encoding='ascii')
    (args.output/'transform-batches.bin').write_bytes(batch)
    (args.output/'transform-final.bin').write_bytes(last)
    manifest = dict(receivedPackets=len(received), lastRealMs=received[-1][0],
                    completionMs=end, creatureId=creature_id, direction=direction,
                    position=list(position), playerDirection=3,
                    inventoryId=869, inventorySubtype=0x4321)
    (args.output/'transform-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
    print(json.dumps(manifest))


if __name__ == '__main__':
    main()
