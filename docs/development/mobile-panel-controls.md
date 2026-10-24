# Mobile panel controls

Android exposes two persistent buttons above the map: `Hotkeys [-]` and
`Chat [-]`. Each button hides its panel independently and changes to `[+]` to
restore it. The hotkey button controls the bottom action bar, including potion
slots and its lock handle. The chat button controls the full console panel.
The divider disappears when both panels are hidden.

Both buttons belong to the game interface outside the panels they control.
Hiding the panels preserves action assignments, chat contents, and the joystick.
The settings `mobile-hotkeys-collapsed` and `mobile-chat-collapsed` persist the
choices. Desktop behavior is unchanged. The existing mobile chat header hide
button uses the same state, avoiding a separate set of restore controls.

Validation on Android uses an offline map with packet recording disabled:
activate the actual button callbacks through all four visibility combinations,
restore both panels, check the existing chat header hide action, and verify the
saved flags and `[+]` labels. Inspect the collapsed screenshot for accessible
restore buttons. Restore the original startup script and settings after the
probe. Lua syntax and `git diff --check` must also pass.
