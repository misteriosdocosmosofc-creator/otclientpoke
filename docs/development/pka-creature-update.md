# PKA creature update at opcode 0x88

The real Android log from 2026-10-24 contains three protocol-error disconnects
at 21:34:15, 21:34:23 and 21:37:12. All fail in opcode `0x88` with
`InputMessage eof reached`; the previous opcode is `0x60a` or `0x8c`.
These are separate from the previously corrected `0xa3` attack-sequence issue.

Standard OTC calls `parseBrowseForgeHistory` for `0x88`. Its variable-length
history records interpret the PKA creature fields as counts and string lengths,
so a complete packet can fail while substantial unread data remains.

The updated original DX dispatch table at `0x14076e384` selects
`0x14076d9f9`, which calls `0x140794450..0x140794534`. That handler reads:

| Field | Wire type |
| --- | --- |
| Creature ID | U32 |
| First value | U32 |
| Second value | U32 |
| Flag | U8 |

The two values are stored as floats in the creature and the flag is tested for
nonzero. Their gameplay meaning is not established here. The unread tail of the
third real exception includes a complete later `0x88` with values 10, 300, 0,
followed immediately by animated text (`0x84`). No fresh CAM was being recorded,
so the complete original failing messages cannot be recovered from these logs.

`PkaProtocol::readAuxiliary` consumes exactly the measured 13-byte body before
the vanilla switch. The caller already gates this helper to PKA. Other profiles
retain their existing forge handler. The custom visual behavior is not implemented
by this fix; consuming its fields prevents a parser disconnect without guessing
their semantics. Truncated fields still throw normally; this does not suppress
malformed-packet handling or discard the remainder of a message.

`generate_helper_cases.py` and `coverage.cpp` exercise this shared production
reader with the observed values, zero/maximum integers and zero/nonzero flags.
Each case must stop before a following opcode, and every proper truncated prefix
must reject. Generated fixtures and real logs remain outside Git.

## Validation on 2026-10-24

- The shared C++ helper suite passed 200 cases and rejected all 9,564 truncated
  prefixes in the persistent Codespace. The existing attack-sequence profile
  test also passed.
- On the optimized Android APK before this change, a reconstructed message
  starting with the observed `0x88` form reproduced the parser exception and
  code 71. A corrected observer hook confirmed this without a hook exception.
- Native APK `582693247` passed the same 96-byte message containing four
  updates, including zero/maximum fields and nonzero flags. Its subsequent
  health, auxiliary and ping opcodes were observed in the expected order while
  the replay remained online.
- A separate native replay passed a 202-byte crop from the last real exception's
  unread dump. This preserves six complete `0x88` updates plus intervening health
  and animated-text records byte for byte. The crop omits the incomplete leading
  record and later tile operations; it is not the complete original packet or a
  replay of the complete failing live session.
- Both corrected native probes had zero parser exceptions, code 71 events and
  Lua exceptions. They asserted the 60 FPS limit and disabled audio. Compile
  commands retained `-O2`; the incremental Codespace build took 3m 43s.
- APK signature and installed APK hash were verified. Config, startup hook and
  saved historical CAM were restored byte for byte; current Lua modules match
  the checkout. Diagnostics/recording remain off. The normal client was reopened
  for manual login. Live gameplay after this fix still needs the user's check.

The earlier inventory `ui.amulet` exception occurs after disconnect and remains
a separate issue. This change does not establish complete PKA protocol support
or explain the preceding relay EOF connection error (code 2).
