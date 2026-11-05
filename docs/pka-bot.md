# PokeAlliance bot profile

The PKA profile bypasses the generic executor before reading the saved legacy
enabled flag. It exposes a dedicated mobile window and a compact pause panel.
Other server profiles retain the old bot. Existing `/bot/*/storage` files are
not migrated or deleted.

## Removed from PKA execution

The whole legacy package loader is bypassed, including Tibia spell healers,
mana/rune/food macros, AttackBot, generic TargetBot, equipment and quiver
managers, PvP push/anti-RS/war helpers, depot/bank/imbuing/supplies workflows,
BotServer/websockets, alarms, analyzer and private scripts. This is a runtime
removal from this profile, not deletion of user data or other server support.
The old executor, route libraries and UI infrastructure remain reusable.

## Implemented

- Character/world-specific JSON settings under `pka-bot-v1-json`; Pokemon profiles.
- Skills discovered from `game_pokemon.getState()`, explicit selection and
  reorder, remaining cooldowns, user-confirmed stun annotations.
- User-triggered, one-pass combo via existing `castMove`; no retries. Each
  step rechecks online/protocol, Pokemon identity and cooldown. Pause, logout,
  terminate and closing the UI cancel pending actions. No automatic resume.
- Configurable inter-command delay (100–5000 ms). The 500 ms initial value
  is a user-adjustable pacing default, not a measured server exhaustion.
- Event-driven route recording, combat/order/cover markers, remove-last;
  capped at 512 points and 20 rendered entries.
- Separate pending settings for cleansing potion, revive and capture.
- Four tabs, scrolling body, bounded viewport and compact pause panel.

## Intentionally unavailable until verified

Autonomous hunt, path execution/lure, enemy classification, stun coverage and
successful application, automatic cleansing/revive, retreat/cover validation,
shiny recognition, corpse matching and capture. The UI labels these limits.
Sending a skill does not prove damage or control. Manual combo does not use
the potion/revive IDs and does not establish that a combat group is safe.

## Arcanine research (2026-10-31)

Reference: https://pokealliancewiki.com/en/pokedex/arcanine/

Slots listed there: M1 Bite, M2 Ember, M3 Fireball, M4 Fire Fang,
M5 ExtremeSpeed, M6 Flare Blitz, M7 Burn Up, M8 Hellfire Storm, M9 War Dog.
The page describes M7 as area stun (six seconds) and M9 as a buff. These are
reference descriptions, not an observed runtime confirmation. Arcanine is
distinct from Shiny Arcanine; do not apply the latter's moves to this profile.
Previously captured roster cooldowns for normal Arcanine match the page's
first eight slots; names and active cooldowns must still come from the server.

## Performance and verification

No 10 ms legacy executor loop runs under PKA. The view timer runs at 500 ms
only while a bot window is visible; it scans the small active moves list,
updates changed labels, and rebuilds only when the Pokemon/moves list changes.
No map/spectator scans, network requests, audio, telemetry or file writes occur
on this timer. Saving happens on explicit view transitions/logout. Recording
uses position events. A combo has at most one scheduled action.

`tools/pka-replay/pka_bot_android.lua` exercises the actual engine offline with
intercepted Pokemon actions and an existing private replay. Its assertions
cover legacy isolation, empty-selection rejection, cooldown, pause and Pokemon
switch cancellation, route marks, tabs, compact view and timer shutdown.
Replay fixtures and device backups are private and must not be committed.
Timing results from host tests cannot establish real Android FPS gains.
