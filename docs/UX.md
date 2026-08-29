# Operator UX

OpenPocketCine is a field monitor for DPs, camera operators, and content
creators. Glanceable on a dark set, one-handed, reliable. It is not a consumer
camera gallery.

Operator-visible layout and metrics live in [`PARITY.md`](PARITY.md). This file
is voice, first-run, help, and failure copy.

## Voice

Write for the operator, not the stack. Name the camera action. Keep it short.

Operator-facing strings never name sister apps or other camera brands
(OpenZCine, Nikon). `OperatorFacingCopyTests` enforces that on iOS; Android copy
follows the same list. Control toasts name the camera action (`Can't change
color while recording — D-Log2 can't zoom`), not opcodes.

Every assist that has a long-press sheet includes help for the control the
operator is holding (units, scale, sensitivity). Empty and error states say what
to do next.

## FTUE

First pair is the wizard in `ConnectionSetupView` (Android matches):

1. **FIRST RUN** — “Pair your camera.” Copy promises about a minute.
2. BLE scan → tap a row.
3. Approve on the Pocket if asked.
4. Join camera Wi-Fi (OS prompt — do not hide it).
5. Datalink → live picture.

Empty store: the wizard fills the viewport. After a successful pair, the camera
is saved; next launch is **Your cameras**. **Pair new camera** re-enters the
wizard. Settings does not start a new pair.

Pocket and Nano are separate bodies. If Bluetooth reached a different camera
than the one tapped, say so and tell the operator to pick the matching row.

Simulator cannot exercise BLE or camera Wi-Fi. Wizard and reconnect changes are
**physical**.

## Failure and reconnect

Session recovery holds the last frame. A black well is a teardown or present-path
bug, not “Waiting for live view” copy over a live socket. Teardown rules:
[`live-session.md`](live-session.md). Stall policy: [`feed-watchdog.md`](feed-watchdog.md).

Record confirmation is a bottom action sheet, not a centred dialog.

Link health in the top bar is delivery (FPS chip), not RSSI.

## Help surfaces

- Long-press View Assist → options + help.
- Operator Setup: seven tabs (Link, Sharing, View Assist, Controls, Display,
  Storage, System).
- TestFlight “What to Test” is operator copy (`docs/testflight-ci.md`).
- Play closed-testing notes are the same voice (`docs/android-play-ci.md`).

## When this pointer fires

First-run, wizard, saved-camera list, operator-facing strings, assist help,
empty/error states, or reconnect copy. Run `OperatorFacingCopyTests` when iOS
strings change. Prove wizard and reconnect **physical**.
