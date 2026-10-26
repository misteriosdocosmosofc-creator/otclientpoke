# Pokemon touch controls

The PokeAlliance mobile profile loads `game_pokemon` after the game interface.
It provides floating, draggable and minimizable windows for the player's roster,
selected Pokemon moves, own-summon conditions and flight height. Window offsets
and minimized state use `pka-window-<id>` settings. A one-time deferred placement
preserves parent-relative offsets after the game root moves below the top menu.
Default positions use the settled map rectangle and leave the joystick and
Hotkeys/Chat controls accessible. Existing saved positions take precedence.

The mobile attack/use/follow slots expose Comando/Pokes/Voo for this profile.
Look remains available. Comando arms the standard item-target cursor with the
original virtual order item `3453`; the user then touches the map or character.
No existing keyboard combinations are reassigned automatically.

## Measured protocol

The layouts were recovered from the original updated DX client. Field names
remain neutral where gameplay meaning has not been established.

| Incoming opcode | Original reader | Wire body |
| --- | --- | --- |
| `005D` | `140770ec0` | U8 mode, U16 count; repeated name/string, variant/U8, item/U16, HP-percent/U8, opaque/U32, identity/string, cooldown list |
| `0602` | `1407715a0` | U8 slot, U8 opaque state, U8 HP-percent, cooldown list |
| `011A` | `140772880` | U8 mode; mode 1 adds U16 item, name/string, identity/string |
| `005C` | `140771780` | U8 mode; mode 1 adds Pokemon/string, U8 count; each move has name/string, icon-item/U32, total/U32, key/string, remaining/U16 |
| `0603` | `140771b90` | key/string, remaining/U16 |
| `060A` | `14077d000` | U8 mode, U32 creature, U64 mask, U32 duration, U32 total |
| `060E` | `14076e124` dispatcher | U8 flying flag |

Cooldown lists have a U8 count and repeated key/string, remaining/U16, total/U16.
Move/roster cooldowns use seconds. Condition durations use milliseconds. The
condition mask is read as two U32 halves to preserve bits above Lua's exact
integer range. Conditions are restricted to creature type 3 (own summon), as
in the original. Stunned is bit 37; labels/icons come from its static catalog.

Auxiliary readers keep following UI messages reachable without guessing field
meanings. `0055` (`140779120` -> `140778f40`) consumes U32 creature, U16, U64,
U16 and three U8 fields. `0056` (`1407791a0`) starts with U32 creature and U8
field: fields 1/9 carry a string, field 6 a U16, fields 2-5/7-8 a U8, and field
10 a U8 count of string/U16/U16 records. Unknown fields reject.
`0114` (`140794a70`) carries U8 count and repeated U16/U16/U16/U8/string/U16/U8;
`0115` (`140794ef0`) carries U32/U16/U16/U8/U8/U8/U8. No creature-property UI
semantics are inferred from these consumed fields. Other opcodes keep their
existing handling. The Lua entry point checks that the module parser exists.

## Deliberate outgoing actions

| Action | Wire command |
| --- | --- |
| Touch roster slot 1-6 | U16 `060A`, U8 `03`, U8 slot |
| Use item on own Pokemon | U16 `005A`, U8 `01`, U16 item |
| Auto Revive, one touch | U16 `005A`, U8 `02`, U16 item, U8 `A7` |
| Flight up/down | U16 `060F`, U8 `00`/`01` |
| Touch a ready move | ordinary Say with the server's move key, e.g. `m1` |

Auto Revive is available only for original-client item IDs 3077, 3156 and 39748.
The item assignment dialog offers **Usar no Pokemon** for multi-use items and
**Auto Revive (1 toque)** for those revives. These item actions do not inherit
Tibia rune cooldowns from overlapping item IDs. Single and multi-action settings
retain their named use types. Holding a hotkey does not repeat these actions.
Flight commands observe the original 200 ms input gate. No action creates an
automatic revive/heal loop. The pink potion's gameplay name remains unconfirmed;
the generic option operates on the multi-use item selected by the user.

## Images and distribution

The authenticated original images stay outside Git: 900 PNGs, including 870
catalogued portrait mappings and available condition images. Their standard
runtime paths are `data/images/pokemons/` and `data/images/conditions/`.
Missing original condition images use the neutral condition icon. No keys,
captures, account settings, private images or APKs belong in source commits.

For a self-contained private Android build, stage the verified image overlay in
those same `data/images/` directories in the persistent Codespace before running
the ordinary incremental build helper. It includes them in the APK's data.zip;
it does not change DAT/SPR installation paths or hash enforcement. Verify the
private image manifest against both data.zip and the installed runtime.
An update installation preserves the existing game_data directory; therefore
changed Lua/OTUI/HTML must also be synchronized and hash-checked there. Fresh
installs extract the bundled data.zip. Keep current player settings intact.

## Validation and remaining live checks

`test_pokemon_protocol.lua` exercises 23 valid payloads, exact next-opcode
boundaries, rejection of all 311 proper truncated prefixes, invalid property
fields and five exact command encodings. It requires full Lua/LuaJIT; the local
minimal bootstrap interpreter has no string library. It ran inside the Android
client's Lua runtime.

`pokemon_actions_android.lua` is an offline native UI probe. Stage an explicit
private `pokemon-actions.cam` containing a real bootstrap and synthetic UI/auxiliary
records. It checks a following roster sentinel, window recreation/settings,
exclusive dialog options, single/multi-action JSON persistence, actual action-bar
dispatch with intercepted sends, held-key suppression, flight timing, profile
isolation and the settled dialog footer. Use `run_android_probe.py` and restore
`/settings/clientoptions.json` and any other settings files as well as RC/config;
the standard runner restores only its documented RC/config files. Inspect its
screenshot after the layout has settled.

The earlier state/action probe checked six real roster entries plus synthetic
move/cooldown/fly/stun records, drag/minimize behavior, exact command bytes and
order-cursor arming/cancellation. Synthetic icons/stun are not live-server proof.
Two historical long live recordings were searched without a matching `005C`
mode-1 move record. Real skill icons, cooldown behavior, conditions, contextual
order, flight, revive and the selected pink potion still require manual play.
Some unrelated incoming opcodes remain unsupported; offline passes do not
establish complete protocol coverage or prolonged real-session stability.

Preserve 60 FPS, O2 native optimization, the existing movement/A3/0088 fixes,
collapsed mobile panels and current preferences. Continuous packet/video capture
stays off. Do not automate login or send real game commands during these probes.
