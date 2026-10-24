# PKA attack sequence compatibility

The PokeAlliance profile uses client assets 860 and wire protocol 854. The
ordinary 860 feature defaults enable `GameAttackSeq`, which adds a U32 sequence
to attack/follow requests and expects one after clear-target opcode `0xA3`.

The Android session on 2026-10-24 failed repeatedly while reading `0xA3`:
`InputMessage eof reached`, no unread bytes, read position 10, followed by
`processConnectionError code=71`. The standalone command had no sequence field.
The live message size was 10 bytes including its headers. A reconstructed
headerless replay reports a 2-byte message and the same read position and error.
These are different total message representations of the missing-field failure.

`g_game.chooseRsa` now disables `GameAttackSeq` specifically for the PKA 860/854
profile, keeping receive and send behavior on the same feature contract. When
switching away from PKA without changing client assets, it restores the ordinary
860 feature default. The decision also runs for explicitly configured custom RSA
keys. Other client/protocol combinations retain their feature defaults.

The updated Windows DX dispatcher also gates its U32 read for `0xA3` on feature
bit 32. Static analysis confirms that the sequence is optional in that client;
it does not establish the runtime value of its feature bitmap.

## Validation

Run `tools/pka-replay/test_attack_sequence.lua` with Lua from the repository root.
It executes the actual profile-selection source with dependencies stubbed and
checks PKA selection, host switching, custom RSA, and unrelated versions.

For the Android regression, use an existing offline map prefix followed by a
standalone `A3 00`, then `A3 00 1E 00` (clear target followed by ping), with a
later keepalive. Select the profile through `chooseRsa`, as normal login does.
The negative control must reproduce the EOF/code 71 and disconnect with the old
feature default. The corrected profile must disable the sequence feature and
remain online through both commands without a parse exception or code 71.

The command payload is reconstructed from the observed exception, not a new
capture of the failing live session. Keep the fixture and user data private,
restore startup/configuration after testing, and keep normal packet recording
disabled. Passing this regression addresses this particular `0xA3` failure;
it does not establish compatibility with every server message or identify the
user action that triggered the server command.
