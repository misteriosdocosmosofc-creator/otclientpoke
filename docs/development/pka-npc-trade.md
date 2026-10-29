# PokeAlliance NPC trade

Opening an NPC shop could disconnect the Android client with protocol error 71.
The 2026-10-28 error identifies opcode `0x7A`, with 12,878 bytes still unread:
the vanilla 8.60 layout interpreted the PKA product list using smaller fields.

The original DX dispatcher routes `0x7A` to `0x140779f10` and `0x7B` to
`0x14077a450`. Their layouts for the active PKA profile are:

| Message | Fields |
| --- | --- |
| Open shop `0x7A` | U16 count; each U16 item ID, U16 subtype, string name, U32 weight, U64 buy price, U64 sell price |
| Player goods `0x7B` | Feature-selected U32/U64 money; U16 count; each U16 item ID, U32 amount |

The existing optional NPC name and modern currency header remain feature/version
controlled. The observed 8.60 PKA session carries neither. Money is U32 in that
session. A price of `UINT64_MAX` marks an unavailable buy/sell direction and is
converted to zero before the UI filters the catalog. Other prices retain their
64 bits through the C++ event; Lua uses its existing numeric representation.

`pkanpctrade.h` shares the PKA readers with the standalone regression. Shop
prices and goods amounts also use wider types in the event bridge so decoding
does not immediately truncate the values again. Other profiles retain their
existing wire layouts and 32-bit price normalization.

Transactions also need the PKA layout: U16 item ID, U16 subtype and U16 amount,
followed by two zero U8 flags for buy (`0x7A`) or one for sell (`0x7B`). The DX
writers at `0x1405a0290` and `0x140726050` confirm these fields and cleared flags.
The client retains its existing transaction quantity limits. No live purchase
or sale is performed by the regression.

## Verification

```sh
g++ -std=c++20 -Wall -Wextra -Werror tools/pka-replay/npc_trade.cpp -o /tmp/pka-npc-trade
/tmp/pka-npc-trade
```

The synthetic tests cover empty lists, U16 counts/subtypes, prices above U32,
the unavailable-price marker, goods amounts above U16, exact transaction bytes,
and rejection of every proper prefix (1,868 truncated cases).

An optional private fixture argument checks the 335 complete product records
and nine goods recovered from the actual error log, including the exact final
cursor, money and quantities. The failing parser had already consumed the first
product's prefix: that incomplete product is omitted, and the fixture uses a
reconstructed U16 count. This fixture is not the complete original packet.

`tools/pka-replay/npc_trade_android.lua` runs an explicit offline engine/UI
regression using private `npc-trade.cam` and `npc-trade-expectations.json`.
It checks all recovered fields, wide-value synthetic controls, close/reopen,
the Buy/Sell tabs and the player remaining online. Set `expectOnline` to false
to reproduce the old APK's disconnect before any shop event. Use the standard
probe runner and restore current RC/config/settings after the run. Keep CAMs,
manifests, logs, screenshots and preference backups outside version control.

An offline replay establishes parsing and UI behavior. A manual NPC interaction
on the server remains the final validation of the installed correction.
