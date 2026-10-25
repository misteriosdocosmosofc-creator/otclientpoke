# Android performance

The low graphics profile can sustain roughly 60 FPS while still presenting long
frames. Measure frame intervals on the game's SurfaceView, rather than the Java
activity's `gfxinfo` or only the on-screen FPS counter.

The following changes reduce work without changing movement or packet layouts:

- Android debug APKs compile C++ with `-O2` by default. They keep debug symbols,
  assertions, persistent signing, and `run-as` access. The prior debug commands
  had no optimization option (the compiler's unoptimized default). Use
  `-Potclient.android.optimizeDebug=false` only when an unoptimized build is
  specifically needed for debugging. CMake/ccache outputs are retained.
- Disabling audio pauses the OpenAL playback device through
  [`ALC_SOFT_pause_device`](https://openal-soft.org/openal-extensions/SOFT_pause_device.txt),
  where supported. Stopping sources alone leaves the output mixer running.
  Enabling audio resumes the same device and context. Device changes reapply
  the muted state, and unsupported implementations retain the existing behavior.
  Pending loads and stopped sources can drain; idle muted polling then stops.
- Normal proxy sends no longer enqueue log messages for each packet at the
  protocol/manager layers. Socket/queue tracing requires the existing compile
  time `PROXY_DEBUG` switch. Session events and error reporting remain available.
- Detailed PKA movement messages require the `movement` diagnostics level;
  map/outfit traces also respect their diagnostics levels. Reading the appended
  movement U16 remains unconditional for the PKA wire profile.

These changes do not remove assets, shrink the aware map range, discard effects
from network parsing, alter walk timing, or modify proxy selection.

A 120 Hz Android event/map preparation limit was also evaluated. Repeated
crowded-map replays did not establish an improvement in frame delivery or event
latency, so that experiment was reverted. The existing processing rate remains.

For validation, replay the same private crowded-map fixture with diagnostics
disabled before and after installation. Check online status and final local
player tile membership, audio off/on/off transitions, frame interval histograms,
CPU time (including the OpenAL mixer), and memory. Preserve live logs/settings
before restarting. Restore settings and startup hooks byte for byte afterwards;
keep recordings and user data outside version control. Offline results do not
establish live network latency or guarantee that every scene will be smooth.

## Device comparison, 2026-10-24

The final optimized build was compared with the previous unoptimized native
build on the same Android phone, using the same 1,957 received packets at 4x
speed, existing Lua fixes, 60 FPS limit, and low graphics settings. Expensive PSS
collection ran after the callback timing window. Each presentation window was
about 35 seconds with the game in the foreground.

| Measurement | Previous native build | Optimized native build |
| --- | ---: | ---: |
| Mean interval for a scheduled 100 ms callback | 130.09 ms | 102.81 ms |
| Maximum callback interval | 855 ms | 121 ms |
| Callback intervals over 150 ms | 39 | 0 |
| Display presentation intervals in histogram bins at least 50 ms | 105 | 34 |
| Display presentation intervals in histogram bins above 100 ms | 18 | 0 |
| Detailed movement log lines in the replay | 1,553 | 0 |

Both runs remained online with the local player on the expected final tile and
no parse exception, code 71, forced player position update, or Lua exception.
The muted mixer stopped running in the optimized build, resumed when audio was
enabled, and stopped again when disabled. The wheel module's startup work went
from 43.74 seconds to 4.19 seconds in these runs.

PSS including graphics was about 771 MiB before and 786 MiB after; this test did
not show a RAM reduction. The demonstrated gains are reduced processing and
fewer long presentation intervals. SurfaceFlinger histogram bins are grouped
measurements, and scene/device conditions can change live results. Its per-layer
summary covered only a small subset of each window, so the full display window
was used instead of presenting that partial FPS value as a whole-run average.
