"""Run an explicit offline Android Lua probe, preserving and restoring settings.

The hook must suppress normal login and print the supplied completion marker.
Local output includes private device data; keep it outside version control.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tarfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', type=Path, required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--package', default='com.github.otclient')
    parser.add_argument('--hook', type=Path, required=True)
    parser.add_argument('--file', type=Path, action='append', default=[])
    parser.add_argument('--before-log', type=Path, help='Use an already preserved log snapshot instead of querying logcat before startup')
    parser.add_argument('--before-cam', type=Path, help='Use an already preserved live CAM instead of transferring it again before an offline probe')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-rc-sha256', required=True)
    parser.add_argument('--marker', default='[asset-probe] complete')
    parser.add_argument('--timeout', type=int, default=360)
    parser.add_argument('--wait-device-seconds', type=int, default=0)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    adb = [str(args.adb), '-s', args.serial]
    if args.wait_device_seconds:
        deadline = time.monotonic() + args.wait_device_seconds
        print('Waiting for the USB device before staging any test hook...', flush=True)
        while True:
            try:
                state = subprocess.run(adb + ['get-state'], capture_output=True, timeout=5)
                if state.returncode == 0 and state.stdout.strip() == b'device':
                    break
            except subprocess.TimeoutExpired:
                pass
            if time.monotonic() >= deadline:
                raise RuntimeError('Device did not reconnect; no test hook staged')
            time.sleep(2)

    def run(*command):
        result = subprocess.run(adb + list(command), capture_output=True, timeout=30)
        if result.returncode:
            raise RuntimeError(f'ADB command failed: {command[:2]}: {result.stderr.decode(errors="replace")}')
        return result.stdout

    def read(remote):
        return run('exec-out', 'run-as', args.package, 'cat', remote)

    def install_many(files, name):
        # Batch a probe into one transfer and verify remote hashes, avoiding
        # repeated full-file round trips over an unreliable USB connection.
        archive = args.output / (name + '.tar')
        expected = {}
        with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as sink:
            for source, remote in files:
                if not remote.startswith('files/') or '..' in remote.split('/'):
                    raise ValueError('Unsafe private staging path')
                sink.add(source, arcname=remote[len('files/'):], recursive=False)
                expected[remote] = hashlib.sha256(source.read_bytes()).hexdigest()
        stage = '/data/local/tmp/pka-' + name + '.tar'
        run('push', str(archive), stage)
        run('shell', 'run-as', args.package, 'tar', '-xf', stage, '-C', 'files')
        hashes = run('exec-out', 'run-as', args.package, 'sha256sum', *expected).decode().splitlines()
        actual = dict((line.split(None, 1)[1].strip(), line.split(None, 1)[0]) for line in hashes)
        if actual != expected:
            raise RuntimeError('Device probe batch hash verification failed')

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
    cam = args.before_cam.read_bytes() if args.before_cam else read('files/.otclient/records/pka-session.cam')
    if len(cam) > 25 and any(line.startswith(b'< ') for line in cam.splitlines()):
        (args.output/'before-session.cam').write_bytes(cam)
    (args.output/'before-runtime.txt').write_bytes(args.before_log.read_bytes() if args.before_log else
        run('logcat', '-d', '-t', '1000', '-v', 'threadtime', '-s', 'OTClientMobile'))
    stream = None
    try:
        run('shell', 'am', 'force-stop', args.package)
        staged = [(path, 'files/.otclient/' + ('records/' if path.suffix == '.cam' else '') + path.name) for path in args.file]
        staged.append((args.hook, 'files/game_data/otclientrc.lua'))
        install_many(staged, 'probe')
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
        run('shell', 'am', 'force-stop', args.package)
        install_many([(rc_backup, 'files/game_data/otclientrc.lua'),
                      (config_backup, 'files/.otclient/config.otml')], 'restore')
        print('Original startup hook and settings restored and verified byte for byte; app closed.', flush=True)


if __name__ == '__main__':
    main()
