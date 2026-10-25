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
