# PKA native Windows client

The Windows work uses the shared PokeAlliance protocol implementation and an
OpenGL x64 executable built with Visual C++. Android development remains in its
existing checkout; this work is isolated on `codex/pka-windows`.

## Build

`.github/workflows/pka-windows.yml` builds the executable on a Windows runner.
The first build compiles the vcpkg dependencies. A binary cache keyed by the
dependency manifest, overlays and triplets is retained for subsequent runs.
The artifact contains binaries and build provenance, not game assets or profiles.

The existing `windows-release` CMake preset is used, with release optimization,
OpenGL and static dependencies. Local Windows builds require the Visual C++
toolchain described in `docs/building/windows-(cmake).md`.

## Local package

Run `python tools/windows/package_client.py --help` for the explicit inputs.
Supply authenticated/extracted game resources from the user's current client
copy and the downloaded build artifact. The destination must be new.

The assembler copies Git-listed runtime files, adds DAT/SPR/OTFI/OTML under
`data/things/860/` and `data/things/1511/`, and adds Pokemon/condition images at
their expected paths. It creates a hash manifest and `Iniciar.cmd`. This launcher
uses a local `profile` directory through `--user-dir`, independent of Android and
other OTClient installations. No account settings or captured sessions are copied.
The client-assets download security defaults remain unchanged.

Pokemon windows are enabled for the PKA profile on desktop, with mouse-driven
selection/skills and an order button in the Commands window. Desktop NPC greeting
uses the private NPC route when the existing right-click interaction is enabled.
The bot retains its manually triggered assisted combo and does not start a hunt.

## Validation

`tools/windows/probe.lua` is an offline integration probe for the real Windows
engine. Use a separate test user directory containing the script as
`pka_windowsrc.lua` and the private replay at `records/npc-trade.cam`.
It checks world/map loading, desktop windows, minimize, cooldown gating, private
NPC greeting and idle bot state. Outbound tested actions are intercepted.
The replay and all generated test files stay private and outside the package.

A passing offline replay does not establish current server compatibility. A
manual login and gameplay test is still required, especially after server updates.
