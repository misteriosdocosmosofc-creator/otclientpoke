# Android performance

The low graphics profile can sustain roughly 60 FPS while still presenting long
frames. Measure frame intervals on the game's SurfaceView, rather than the Java
activity's `gfxinfo` or only the on-screen FPS counter.

The following changes reduce work without changing movement or packet layouts:

- Android's event/map preparation loop targets 120 updates per second instead
  of the desktop 500. Rendering retains its configured FPS limit. This leaves
  two processing opportunities per 60 Hz display frame and reduces competition
  for the phone's CPU. Desktop and WebAssembly retain their existing limits.
- Disabling audio pauses the OpenAL playback device through
  [`ALC_SOFT_pause_device`](https://openal-soft.org/openal-extensions/SOFT_pause_device.txt),
  where supported. Stopping sources alone leaves the output mixer running.
  Enabling audio resumes the same device and context. Device changes reapply
  the muted state, and unsupported implementations retain the existing behavior.
  Pending loads and stopped sources can drain; idle muted polling then stops.
- Normal proxy sends no longer enqueue log messages for each packet at the
  protocol/manager layers. Socket/queue tracing requires the existing compile
  time `PROXY_DEBUG` switch. Session events and error reporting remain available.

These changes do not remove assets, shrink the aware map range, discard effects
from network parsing, alter walk timing, or modify proxy selection.

For validation, replay the same private crowded-map fixture with diagnostics
disabled before and after installation. Check online status and final local
player tile membership, audio off/on/off transitions, frame interval histograms,
CPU time (including the OpenAL mixer), and memory. Preserve live logs/settings
before restarting. Restore settings and startup hooks byte for byte afterwards;
keep recordings and user data outside version control. Offline results do not
establish live network latency or guarantee that every scene will be smooth.
