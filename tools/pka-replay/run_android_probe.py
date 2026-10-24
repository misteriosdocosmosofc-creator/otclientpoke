"""Run an explicit offline Android Lua probe, preserving and restoring settings.

The hook must suppress normal login and print the supplied completion marker.
Local output includes private device data; keep it outside version control.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--package', default='com.github.otclient')
    parser.add_argument('--hook', type=Path, required=True)
    parser.add_argument('--file', type=Path, action='append', default=[])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-rc-sha256', required=True)
    parser.add_argument('--marker', default='[asset-probe] complete')
    parser.add_argument('--timeout', type=int, default=360)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    adb = [str(args.adb), '-s', args.serial]

    def run(*command):
        result = subprocess.run(adb + list(command), capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError(f'ADB command failed: {command[:2]}: {result.stderr.decode(errors="replace")}')
        return result.stdout

    def read(remote):
        return run('exec-out', 'run-as', args.package, 'cat', remote)

    def install(source, remote):
        stage = '/data/local/tmp/' + source.name
        run('push', str(source), stage)
        run('shell', 'run-as', args.package, 'cp', stage, remote)
        if hashlib.sha256(read(remote)).digest() != hashlib.sha256(source.read_bytes()).digest():
            raise RuntimeError(f'Device copy verification failed: {source.name}')

    original_rc = read('files/game_data/otclientrc.lua')
    if hashlib.sha256(original_rc).hexdigest() != args.expected_rc_sha256:
        raise RuntimeError('Unexpected startup hook; refusing to overwrite it')
    original_config = read('files/.otclient/config.otml')
    if not original_config:
        raise RuntimeError('Empty settings backup; refusing to proceed')
    rc_backup, config_backup = args.output/'original-rc.lua', args.output/'original-config.otml'
    rc_backup.write_bytes(original_rc)
    config_backup.write_bytes(original_config)
    # Preserve the live recording and logs before stopping or staging a replay.
    cam = read('files/.otclient/records/pka-session.cam')
    if len(cam) > 25 and any(line.startswith(b'< ') for line in cam.splitlines()):
        (args.output/'before-session.cam').write_bytes(cam)
    (args.output/'before-runtime.txt').write_bytes(run('logcat', '-d', '-t', '1000', '-v', 'threadtime', '-s', 'OTClientMobile'))
    stream = None
    try:
        run('shell', 'am', 'force-stop', args.package)
        for path in args.file:
            install(path, 'files/.otclient/' + ('records/' if path.suffix == '.cam' else '') + path.name)
        install(args.hook, 'files/game_data/otclientrc.lua')
        run('shell', 'am', 'start', '-n', args.package + '/com.otclient.MainActivity')
        pid = ''
        for _ in range(20):
            probe = subprocess.run(adb + ['shell', 'pidof', args.package], capture_output=True, timeout=10)
            pid = probe.stdout.decode().strip()
            if pid:
                break
            time.sleep(1)
        if not pid:
            raise RuntimeError('App did not start; startup hook will be restored')
        with (args.output/'runtime.txt').open('wb') as sink:
            stream = subprocess.Popen(adb + ['logcat', '--pid='+pid, '-v', 'threadtime'], stdout=sink, stderr=subprocess.STDOUT)
            deadline, last_notice = time.monotonic() + args.timeout, 0
            print(f'Offline probe started; PID {pid}.', flush=True)
            while time.monotonic() < deadline:
                log = (args.output/'runtime.txt').read_bytes()
                if args.marker.encode() in log:
                    for line in log.decode(errors='replace').splitlines():
                        if '[asset-probe]' in line or '[coverage-replay]' in line:
                            print(line, flush=True)
                    if args.marker.encode() + b' passed=true' not in log:
                        raise RuntimeError('Probe reported failure; runtime preserved')
                    (args.output/'screen.png').write_bytes(run('exec-out', 'screencap', '-p'))
                    print('Offline probe passed.', flush=True)
                    break
                if time.monotonic() - last_notice > 25:
                    print('Waiting for startup/probe completion...', flush=True)
                    last_notice = time.monotonic()
                time.sleep(1)
            else:
                raise RuntimeError('Probe timed out; runtime preserved')
    finally:
        if stream:
            stream.terminate()
            stream.wait(timeout=5)
        install(rc_backup, 'files/game_data/otclientrc.lua')
        run('shell', 'am', 'force-stop', args.package)
        install(config_backup, 'files/.otclient/config.otml')
        print('Original startup hook and settings restored and verified byte for byte; app closed.', flush=True)


if __name__ == '__main__':
    main()
