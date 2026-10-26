# PKA signed displacement and the invisible dismounted player

After ordering the Pokemon on the local character, the server accepted the
dismount, but both the character and its health/name display disappeared. Other
creatures and the map remained visible.

A read-only query of the live client established that local player
`0x10002756` was online, had 66% health, remained in its tile and in the creature
registry, and was still the camera target. Its position matched the camera,
`isRemoved=false`, `isInvisible=false`, and `canBeSeen=true`. Its outfit was 3860,
with a native displacement of `(65520,65520)`. The signed value of each DAT word
is `-16`. All 288 sprite references for this outfit matched the authenticated
private DAT definition exactly.

The legacy DAT reader already supports signed coordinates for
`GameNegativeOffset`, but this PKA asset profile did not enable that global
feature. Reading `0xFFF0` as an unsigned U16 moved both the outfit texture and
its health/name display far off screen. The existing sprite-reference audit
did not verify this attribute's signed meaning.

`ThingType::unserialize` now uses signed displacement when `pkaDatFormat` is true,
as well as when the existing feature requests it. That format is selected by the
known DAT signature `BCBCF8F6`, before host/RSA selection. No network opcode,
mount command, real-player outfit, movement rule, or global feature is changed.
Other DAT profiles retain their previous feature-controlled behavior.

`audit_assets.dat_records` now retains signed displacement metadata.
`generate_displacements.py --dat <private.dat> --output <private-dir>/displacements.json`
exports 2,981 displaced/control definitions from the verified asset pair,
including all 1,744 entries with a negative coordinate. Keep the private DAT
and generated metadata outside Git.

`displacement_android.lua` checks those coordinates in the native Android loader
while the global negative-offset feature is disabled. Stage it with the explicit
private `dismount-bootstrap.cam` and generated manifest. In an offline replay,
it changes the seed player's appearance to the exact observed outfit 3860 and
checks health, tile membership, registry/camera state and the shortcut icons.
Inspect the resulting character, health/name display and action buttons in its
screenshot. This is an offline appearance/asset regression; manually mounting
and dismounting on the server remains a separate check.

Normal logs also contained unrelated missing-creature movement warnings and
unsupported incoming forms. The live state query ruled out loss of this local
player as the cause of the observed invisibility. Those warnings have not been
silenced or treated as evidence of full protocol support.
