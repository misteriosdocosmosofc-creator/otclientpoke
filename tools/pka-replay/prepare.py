"""Prepare private DAT flags and a PC payload; never copies them into Git."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser()
parser.add_argument('--dat', type=Path, required=True)
parser.add_argument('--dat-reader', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--pc-capture', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('private_dat_reader', args.dat_reader)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
reader = module.Reader(args.dat.read_bytes())
signature = reader.u32()
count = reader.u16() + 1
reader.u16(); reader.u16(); reader.u16()
if signature != 0xBCBCF8F6:
    raise SystemExit(f'Unexpected DAT signature {signature:08x}')
with (args.output / 'item-flags.txt').open('w', encoding='ascii') as output:
    for item_id in range(100, count):
        item = module.read_item(reader, item_id)
        names = {name for _, name, _ in item['attrs']}
        flags = sum(bit for name, bit in [('stackable', 1), ('fluidContainer', 2), ('splash', 4)] if name in names)
        output.write(f'{item_id} {flags}\n')
if args.pc_capture:
    capture = args.pc_capture
    manifest = json.loads((capture / 'manifest.json').read_text(encoding='utf-8'))
    dispatch = manifest['inboundDispatches'][1]
    raw = (capture / manifest['packetFile']).read_bytes()
    position_cursor = manifest['fullMap']['cursor'] - 5
    start = dispatch['bufferOffset'] + position_cursor - dispatch['start']
    end = dispatch['bufferOffset'] + dispatch['bufferLength']
    payload = raw[start:end]
    (args.output / 'pc-fullmap-payload.bin').write_bytes(payload)
    expected = None
    for line in (capture / 'reader-events.jsonl').read_text(encoding='utf-8').splitlines():
        event = json.loads(line)
        if event['event'] == 'fullmap_exit':
            expected = event['cursorAfter'] - position_cursor
    (args.output / 'pc-expected.json').write_text(json.dumps({'position': struct.unpack_from('<HHB', payload), 'expectedEnd': expected, 'positionCursor': position_cursor}, indent=2), encoding='utf-8')
    # Adapt the actual PC login+FullMap body to the existing PacketPlayer format.
    if expected is None:
        raise SystemExit('PC capture has no FullMap return; replay would be incomplete')
    # Its first packet includes the U16 size consumed by onRecv on client 860.
    body_start = dispatch['bufferOffset'] + 12 - dispatch['start']
    body = raw[body_start:start + expected]
    packet = struct.pack('<H', len(body)) + body
    (args.output / 'pka-bootstrap.cam').write_text('< 0 ' + packet.hex() + '\n< 30000 1e00\n', encoding='ascii')
    print(json.dumps({'items': count - 100, 'payloadBytes': len(payload), 'expectedEnd': expected}))
