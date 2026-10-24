"""Check native PKA movement traces against a private received-only CAM.

For a fixture where map strips follow the local player, verify the mapped ID
before every move followed by a map strip, not just final player membership.
All input/output artifacts must stay private.
"""
import argparse
import json
import re
from pathlib import Path


def analyze(cam, runtime):
    packets = [bytes.fromhex(body) for direction, _, body in
               (line.split() for line in cam.read_text().splitlines()) if direction == '<']
    log = runtime.read_text(errors='replace')
    local_id = next((int(value) for value in re.findall(r'\[pka-membership\].*? id=(\d+)', log) if int(value)), None)
    if local_id is None:
        raise ValueError('No native local-player trace found; use protocol-diagnostics movement')
    pending = None
    camera_moves, wrong_camera, wrong_position = 0, [], []
    moves, matched = 0, 0
    for line in log.splitlines():
        if '[pka-membership-move]' in line:
            moves += 1
            pending = line
        elif pending and '[pka-opcode-step]' in line and 'opcode=0x006D ' in line:
            number = int(re.search(r'packet=(\d+)', pending)[1])
            offset = int(re.search(r'bodyOffset=(\d+)', line)[1])
            packet = packets[number-1]
            body = packet[offset:offset+15]
            if len(body) != 15 or body[:2] != b'\x6d\x00':
                raise ValueError(f'Trace/CAM mismatch at packet {number}, body offset {offset}')
            mapped_id = int(re.search(r'mappedId=(\d+)', pending)[1])
            position = list(map(int, re.search(r'source=([\d,]+)', pending)[1].split(',')))
            source = [int.from_bytes(body[2:4], 'little'), int.from_bytes(body[4:6], 'little'), body[6]]
            if mapped_id and source[0] != 65535 and source != position:
                wrong_position.append(dict(packet=number, offset=offset, mappedId=mapped_id, wireSource=source, objectPosition=position))
            if int.from_bytes(packet[offset+15:offset+17], 'little') in range(0x65, 0x69):
                camera_moves += 1
                if mapped_id != local_id:
                    wrong_camera.append(dict(packet=number, offset=offset, mappedId=mapped_id))
            matched += 1
            pending = None
    expected_moves = len(re.findall(r'\[pka-opcode-step\].* opcode=0x006D ', log))
    result = dict(localId=local_id, movementRecords=moves, matchedMovements=matched, parsedMovements=expected_moves,
                  cameraMovements=camera_moves, wrongCameraMappings=wrong_camera,
                  objectPositionMismatches=wrong_position,
                  forcedUpdates=log.count('Forced player position update'),
                  missingMoveTargets=log.count('ProtocolGame::parseCreatureMove: no creature found to move'),
                  parseExceptions=log.lower().count('parse exception'),
                  finalProbePassed='[coverage-replay] complete passed=true' in log)
    result['passed'] = bool(matched and matched == moves == expected_moves and camera_moves and not wrong_camera and
                            not wrong_position and not result['forcedUpdates'] and not result['parseExceptions'] and
                            result['finalProbePassed'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cam', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.cam, args.runtime)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({key: (len(value) if isinstance(value, list) else value) for key,value in result.items()}, indent=2))
    raise SystemExit(0 if result['passed'] else 1)


if __name__ == '__main__':
    main()
