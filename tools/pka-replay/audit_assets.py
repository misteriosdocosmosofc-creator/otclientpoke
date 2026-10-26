"""Audit the verified legacy PKA DAT/SPR pair without changing the assets.

This checks file structure and decodes every nonempty RLE stream. It does not
infer packet layouts from asset IDs, and it does not prove GPU rendering.
Outputs (including optional per-thing metadata) belong outside the repository.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
import mmap
from pathlib import Path
import struct


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, count):
        if count < 0 or self.pos + count > len(self.data):
            raise ValueError(f'truncated DAT at {self.pos}, need {count}')
        start = self.pos
        self.pos += count
        return self.data[start:self.pos]

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack('<H', self.take(2))[0]

    def string(self):
        self.take(self.u16())


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def dat_records(path):
    reader = Reader(path.read_bytes())
    signature, *counts = struct.unpack('<I4H', reader.take(12))
    if signature != 0xBCBCF8F6:
        raise ValueError(f'unverified DAT signature {signature:08x}')
    records = []
    for category, highest in enumerate(counts):
        for ident in range(100 if category == 0 else 1, highest + 1):
            start, attrs = reader.pos, []
            displacement = {'x': 0, 'y': 0}
            for _ in range(255):
                raw = reader.u8()
                if raw == 255:
                    break
                attrs.append(raw)
                if category == 1 and raw == 0x2A:
                    reader.take(16)
                    continue
                if category == 2 and raw == 0x2B:
                    reader.take(5)
                    continue
                # Custom chargeable slot precedes the modern shifted flags.
                attr = (254 if raw == 8 else 34 if raw == 254 else
                        251 if raw == 35 else raw - 1 if raw > 8 else raw)
                if attr in (0, 8, 9, 25, 28, 29, 32, 251):
                    reader.take(2)
                elif attr == 24:
                    x, y = struct.unpack('<hh', reader.take(4))
                    displacement = {'x': x, 'y': y}
                elif attr == 21:
                    reader.take(4)
                elif attr == 33:
                    reader.take(6)
                    reader.string()
                    reader.take(4)
                # The engine retains otherwise unhandled attributes as flags
                # with no payload. Report their raw values instead of guessing.
            else:
                raise ValueError(f'missing attribute terminator category={category} id={ident}')
            width, height = reader.u8(), reader.u8()
            if width > 1 or height > 1:
                reader.u8()
            dims = [width, height] + [reader.u8() for _ in range(5)]
            count = math.prod(dims)
            if count > 65536:
                raise ValueError(f'sprite composition exceeds PKA limit: {ident}: {dims}')
            sprites = list(struct.unpack(f'<{count}I', reader.take(count * 4)))
            # The original wire reader tests stackable/fluid/splash, not the
            # deprecated raw-8 chargeable flag. Each PKA subtype is U16.
            flags = ((1 if 5 in attrs else 0) | (2 if 11 in attrs else 0) |
                     (4 if 12 in attrs else 0))
            records.append(dict(category=category, id=ident, start=start, end=reader.pos,
                                attrs=attrs, dimensions=dims, sprites=sprites, wireFlags=flags,
                                displacement=displacement))
    if reader.pos != len(reader.data):
        raise ValueError(f'DAT trailing bytes: {len(reader.data) - reader.pos}')
    return signature, counts, records


def decode_rle(data, start, length, channels=4):
    """Validate full input consumption and every run; return decoded RGBA pixels."""
    end, cursor, written = start + length, start, 0
    pixels = bytearray(32 * 32 * 4)
    while cursor < end:
        if cursor + 4 > end:
            raise ValueError('partial RLE run header')
        transparent, colored = struct.unpack_from('<HH', data, cursor)
        cursor += 4
        if written + transparent + colored > 1024:
            raise ValueError('RLE writes beyond 32x32 pixels')
        written += transparent
        if cursor + colored * channels > end:
            raise ValueError('partial RLE color payload')
        if channels == 4:
            pixels[written * 4:(written + colored) * 4] = data[cursor:cursor + colored * 4]
        else:
            for i in range(colored):
                pixels[(written + i) * 4:(written + i + 1) * 4] = data[cursor + i * 3:cursor + i * 3 + 3] + b'\xff'
        written += colored
        cursor += colored * channels
    return pixels


def audit(dat, spr, records_path=None):
    signature, counts, records = dat_records(dat)
    print(f'DAT: all {len(records)} definitions parsed to exact EOF.', flush=True)
    refs, categories = set(), []
    for category, name in enumerate(('items', 'outfits', 'effects', 'missiles')):
        rows = [row for row in records if row['category'] == category]
        refs.update(s for row in rows for s in row['sprites'] if s)
        attrs = Counter(a for row in rows for a in set(row['attrs']))
        categories.append(dict(name=name, count=len(rows), highestId=counts[category],
                               spriteReferences=sum(len(row['sprites']) for row in rows),
                               zeroDimensions=[row['id'] for row in rows if 0 in row['dimensions']],
                               allZeroSprites=[row['id'] for row in rows if not any(row['sprites'])],
                               maxComposition=max((len(row['sprites']) for row in rows), default=0),
                               attributes={f'0x{a:02x}': n for a, n in sorted(attrs.items())}))
    if records_path:
        with records_path.open('w', encoding='utf8') as sink:
            for row in records:
                sink.write(json.dumps(row, separators=(',', ':')) + '\n')
    with spr.open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
        spr_signature, count = struct.unpack_from('<II', data)
        if spr_signature != 0x5D97AB7B:
            raise ValueError(f'unverified SPR signature {spr_signature:08x}')
        table_end = 8 + count * 4
        if table_end > len(data):
            raise ValueError('truncated SPR offset table')
        offsets = struct.unpack_from(f'<{count}I', data, 8)
        nonempty = decoded = 0
        bad, transparent, referenced_holes = [], [], []
        for ident, offset in enumerate(offsets, 1):
            if not offset:
                if ident in refs:
                    referenced_holes.append(ident)
                continue
            nonempty += 1
            try:
                if offset < table_end or offset + 5 > len(data):
                    raise ValueError('sprite offset outside data region')
                length = struct.unpack_from('<H', data, offset + 3)[0]
                if offset + 5 + length > len(data):
                    raise ValueError('sprite payload outside SPR')
                pixels = decode_rle(data, offset + 5, length)
                decoded += 1
                if not any(pixels[3::4]):
                    transparent.append(ident)
            except ValueError as error:
                bad.append(dict(id=ident, reason=str(error)))
            if nonempty % 100000 == 0:
                print(f'SPR: decoded {nonempty} nonempty entries...', flush=True)
        sprite_result = dict(signature=f'0x{spr_signature:08x}', entries=count, nonempty=nonempty,
                             decodedRGBA=decoded, invalid=bad, fullyTransparent=transparent,
                             distinctReferenced=len(refs), referencesBeyondSPR=sorted(s for s in refs if s > count),
                             referencedEmptyEntries=referenced_holes)
    if records_path:
        records_path.with_name('item-flags.txt').write_text(''.join(
            f"{row['id']} {row['wireFlags']}\n" for row in records if row['category'] == 0), encoding='ascii')
        records_path.with_name('coverage-expectations.json').write_text(json.dumps(dict(
            highestIds=counts, itemFlags={str(row['id']): row['wireFlags'] for row in records
                if row['category'] == 0 and row['wireFlags']})), encoding='utf8')
    return dict(dat=dict(bytes=dat.stat().st_size, sha256=sha256(dat), signature=f'0x{signature:08x}',
                         exactEOF=True, categories=categories),
                spr=dict(bytes=spr.stat().st_size, sha256=sha256(spr), **sprite_result),
                limitations=['Structural and CPU decoding audit; not a GPU rendering test.',
                             'A zero sprite reference/offset can be an intentional empty layer.',
                             'Asset enumeration does not establish optional wire packet layouts.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dat', type=Path, required=True)
    parser.add_argument('--spr', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--records', type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.records:
        args.records.parent.mkdir(parents=True, exist_ok=True)
    report = audit(args.dat, args.spr, args.records)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf8')
    invalid = report['spr']['invalid'] or report['spr']['referencesBeyondSPR']
    print(json.dumps(dict(status='failed' if invalid else 'passed',
                          definitions=sum(row['count'] for row in report['dat']['categories']),
                          decodedSprites=report['spr']['decodedRGBA'],
                          invalidSprites=len(report['spr']['invalid']),
                          referencedEmptyEntries=len(report['spr']['referencedEmptyEntries']))))
    raise SystemExit(1 if invalid else 0)


if __name__ == '__main__':
    main()
