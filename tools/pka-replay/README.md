# PKA offline coverage

These developer tools keep DAT/SPR assets, captured credentials, CAM recordings,
screenshots, and generated fixtures outside Git. Supply private paths explicitly.
They do not contact the game server or train a parser: failures identify a
specific field layout or asset that needs evidence and a code correction.

`audit_assets.py` parses every definition in the verified PKA DAT profile and
decodes every nonempty SPR entry as 32x32 RGBA RLE. It checks complete input
consumption, run bounds, dimensions, and cross references. Blank layers and
empty SPR entries are reported separately, since they can be intentional.
This is a CPU/structure check, not a GPU rendering check.

```powershell
python tools/pka-replay/audit_assets.py --dat <private.dat> --spr <private.spr> --output <private-dir>/audit.json --records <private-dir>/things.jsonl
python tools/pka-replay/generate_helper_cases.py <private-dir>/helper-cases.bin
g++ -std=c++20 -O2 tools/pka-replay/coverage.cpp -o <private-dir>/pka-coverage
<private-dir>/pka-coverage <private-dir>/helper-cases.bin
```

The helper suite exercises nonzero/zero outfit branches, empty/nonempty strings,
unknown/known creature records, subtypes 0-4, optional prelude gates 0/1/2,
empty/nonempty attribute and record lists, special item `0x25a0`, item text
modes, and effect lists. Each valid case must stop before the next opcode;
every proper truncated prefix must reject. The serializers use measured
original-client layouts. Passing synthetic cases does not establish support for
unobserved server packet forms.

`generate_catalog.py` takes per-thing metadata from the audit and a private seed
with a challenge followed by an accepted world packet. It copies received data
only and creates a fluid-width regression and a catalog fixture containing every
item ID and outfit ID. Later CAM buffers are logical messages without a new
transport size header. `check_catalog.py` checks each generated packet against
the shared C++ replay reader. Keep the historical real-recording regressions too.

The original DX item reader `0x140799cd0` tests stackable, fluid container, and
splash flags and reads **U16 for each** (`0x14082ce40`). Its helper
`0x1407054d0` tests flag index 11 (splash). Deprecated raw DAT attribute 8 does
not add a count. Retaining it in a synthetic wire-flags table would create
invalid fixtures. It is deliberately excluded from `prepare.py` and the audit's
`wireFlags`. The standard non-PKA item count behavior remains unchanged.

`run_android_probe.py` accepts an explicit serial, expected original startup-hook
SHA-256, Lua hook, files, and a fresh private output directory. It preserves the
live recording before stopping the app, verifies staged files by hash, streams
logs, and restores the original startup hook/config byte for byte in `finally`.
It closes the app after the probe. Do not run it during a live session without
preserving the evidence first. USB loss can interrupt cleanup; use its saved
`original-rc.lua` and `original-config.otml` to recover before a normal login.

Use `audit_android.lua` with `coverage-expectations.json` to compare all native
ThingTypes, sprite-reference dimensions, and item wire flags. Use
`fluid_android.lua` with `fluid-width-repro.cam` to check U16 subtype `0x1234`
and the following inventory sentinel. Use `catalog_android.lua`, staging
`audit_android.lua`, expectations, catalog manifest and CAM, to perform the
metadata audit followed by catalog parsing. Also stage the historical
`movement-repro.cam`: after the catalog sentinels, it checks the real movement
recording's final position (3324,2058,7). Pass
`--marker '[coverage-replay] complete'` for either replay hook.

When a prior live log snapshot is already preserved, `--before-log <path>` uses
that file instead of making another pre-start logcat request. Its timestamp can
differ from the probe; the probe's own runtime is still streamed separately.
`--before-cam <path>` likewise reuses a preserved live recording when only
offline probes have run since that capture. Staging/restoration uses one TAR
transfer and remote SHA-256 verification. `--wait-device-seconds` can wait for a
USB reconnection before staging anything.

The native catalog hook counts distinct item/outfit change events and waits for
both complete ID coverage and final sentinels, rather than assuming the device
drains every callback at the fixture's nominal timestamp. Per-object tracing is
reduced temporarily; the original diagnostics setting is restored with the
original config. A delayed keepalive prevents EOF while the device drains work.

These engine probes establish metadata and parser coverage; they do not render
every phase/pattern of every definition on the GPU. Real connection, movement,
visual checks, and minimap interaction remain separate validation steps. Keep
temporary hooks out of the normal game startup.

`generate_transforms.py --session <private.cam> --output <private-dir>` retains
all received messages from the long session ending in the measured 16-byte
`0x6b` creature transform. It accelerates timestamps eightfold, then appends
empty, one-record and three-record batches, non-batch modes 2/255, and an
inventory sentinel. A missing mapped thing in the batch checks that later
records still get consumed. Stage its CAM and manifest with
`transform_android.lua` and use the `[coverage-replay] complete` marker.
The hook checks the final real creature's position/direction and the batch's
local-player direction and sentinel, while remaining online. It restores normal
startup/settings through the same probe runner. Timings are accelerated, so this
is a state/parser regression, not a real-time stability or FPS benchmark.

Original DX `0x140778540..0x140778a1f` reads a U8 mode before the mapped
thing/replacement pair. Mode 1 adds a U16 count and repeats the pair; all other
modes read one pair. Omitting the mode shifted the position and thing ID,
leaving four bytes misread as opcode `0x2b` in the captured failure. The fix is
gated to PKA; standard tile transforms retain their original layout. Shared
helper cases include mode/count boundaries and truncated headers. The C++
replay supports transform replacements containing an item or short creature
record `0x63`; use the native probe for complete session/state coverage.

The updated DX mode-map initializer `0x14076aa80` adds wire 31 -> Loot (29)
and wire 52 -> Attention (52) to its 840-860 profile. Its text reader
`0x140785ed0` takes the ordinary U16-length string path for both. The real
mode-52 failure is a complete 117-byte packet, not an extra framing field.
`generate_text_messages.py --session <private.cam> --output <private-dir>`
copies the received session with timestamps accelerated eightfold and appends
empty/nonempty messages of both modes followed by an inventory sentinel.
It stores the original text as hex because captured text can contain Latin-1
bytes. Stage its CAM/manifest with `text_messages_android.lua`; the native
hook checks the exact original bytes, both empty strings, both message modes,
the following inventory item/subtype, and that the player remains online.

Run `lua tools/pka-replay/test_joystick.lua` from the repository root with
Lua 5.1, LuaJIT, or LuaJIT's `src/host/minilua`. The fixture loads the production
walking module and checks that PKA joystick input observes prediction, pending
confirmation, locks, collision and server-walk handling, without queuing a step
after release. Non-PKA joystick behavior is checked separately. This test uses
mock player state; transient movement stalls still require real-device checks.
