"""Serialize measured PKA wire forms for branch and truncation regression tests.

These are synthetic coverage cases, not evidence that every form occurs on the
server. Layout references: the original DX outfit/item/creature reader exports
documented in android-fast-iteration.md. Keep generated data outside Git.
"""
import argparse
from itertools import product
from pathlib import Path
import struct


def u8(value): return struct.pack('<B', value)
def u16(value): return struct.pack('<H', value)
def u32(value): return struct.pack('<I', value)
def u64(value): return struct.pack('<Q', value)
def string(value): return u16(len(value)) + value


def cases():
    for mode in (0, 2, 255):
        yield 4, 1, u8(mode)
    for count in (0, 1, 2, 65535):
        yield 4, count, u8(1) + u16(count)
    for has_look, text in product((0, 1), (b'', b'outfit-extension', bytes(range(256)))):
        yield 0, has_look, (u64(0x1020304050607080) + u64(0x8172635445362718) if has_look else b'') + string(text)
    for kind, subtype, optional, count, text in product((0x61, 0x62), range(5), (0, 1, 2), (0, 2), (b'', b'tail-extension')):
        payload = u16(220) + u8(3) + u8(4) + (u8(5) if kind == 0x61 else b'') + u8(subtype) + u8(0)
        if subtype == 0:
            payload += string(b'player') + u8(9) + u16(0xA0B0) + string(b'title') + bytes((7, 8, 9))
        payload += u8(count)
        for i in range(count):
            payload += string(b'attribute-' + str(i).encode()) + u16(0xA100+i) + u16(0xB200+i)
        if subtype in (1, 3, 4):
            payload += bytes((11, 12, 13, 14, 15, 16, optional))
            if optional:
                payload += u8(0xC3)
            if subtype in (3, 4):
                payload += u8(0xD4)
            payload += u8(0xE5)
        payload += u8(count)
        for i in range(count):
            payload += u16(0xA100+i) + u64(0x1020304050607080+i) + u16(0xB200+i) + bytes((3, 4, 5))
        payload += string(text)
        if subtype == 2:
            payload += u8(0xF6)
        yield 1, kind, payload
    for ident, mode, metadata, text in product((100, 0x25A0), (0, 1, 2, 3), (0, 1, 255), (b'', b'item-extension')):
        payload = u8(mode)
        if mode == 1:
            payload += string(text) + string(b'description')
            if ident == 0x25A0:
                payload += string(b'special-item')
            payload += u8(0xA5) + u16(0xB6C7)
        elif mode == 3:
            payload += string(text)
        yield 2, ident, payload + u8(metadata)
    for count, optional in product((0, 1, 255), (0, 1)):
        yield 3, 0, u8(count) + b''.join(u16(i+1) for i in range(count)) + u8(optional) + (u32(0x12345678) if optional else b'')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = list(cases())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('wb') as sink:
        sink.write(b'PKAC' + u32(len(rows)))
        for kind, param, payload in rows:
            sink.write(u8(kind) + u16(param) + u32(len(payload)) + payload)
    print(f'{len(rows)} synthetic helper cases written.')


if __name__ == '__main__':
    main()
