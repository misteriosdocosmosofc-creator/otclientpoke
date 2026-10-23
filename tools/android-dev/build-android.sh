#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/android-env.sh"
cd "$OTC_ANDROID_REPO"

luajit_commit=d0e88930ddde28ff662503f9f20facf34f7265aa
luajit_stamp="$OTC_ANDROID_CACHE_ROOT/luajit-${OTCLIENT_ANDROID_ABIS}.stamp"
if [[ ! -d luajit-src/.git ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/LuaJIT/LuaJIT.git luajit-src
fi
if [[ ! -f "$luajit_stamp" || "$(cat "$luajit_stamp")" != "$luajit_commit" ]] || \
   [[ build_luajit_android.sh -nt "$luajit_stamp" ]]; then
  git -C luajit-src fetch --depth 1 origin "$luajit_commit"
  git -C luajit-src checkout --detach "$luajit_commit"
  bash build_luajit_android.sh
  printf '%s\n' "$luajit_commit" > "$luajit_stamp"
fi

# Keep data.zip unchanged when its input contents have not changed.
python3 - <<'PY'
import hashlib
import os
from pathlib import Path
import zipfile

files = []
for root in ('data', 'mods', 'modules'):
    files.extend(path for path in Path(root).rglob('*') if path.is_file())
files.extend(Path(name) for name in ('init.lua', 'otclientrc.lua', 'cacert.pem', 'config.ini') if Path(name).is_file())
digest = hashlib.sha256()
for path in sorted(files):
    digest.update(path.as_posix().encode() + b'\0')
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
signature = digest.hexdigest()
stamp = Path(os.environ['OTC_ANDROID_CACHE_ROOT']) / 'assets.sha256'
output = Path('android/app/src/main/assets/data.zip')
if output.is_file() and stamp.is_file() and stamp.read_text().strip() == signature:
    print('data.zip: unchanged')
else:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, path.as_posix())
    stamp.write_text(signature + '\n')
    print(f'data.zip: updated ({output.stat().st_size} bytes)')
PY

cd android
# Do not run clean: the persistent .cxx and build directories enable incremental builds.
bash gradlew :app:assembleDebug --build-cache --console=plain "$@"
ccache --show-stats
printf '\nAPK: %s/android/app/build/outputs/apk/debug/app-debug.apk\n' "$OTC_ANDROID_REPO"
