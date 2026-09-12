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
4. Join camera Wi-Fi (OS prompt — do not hide it). On 5.8 GHz the camera AP
   can take about a minute to appear; both shells keep trying (#235).
5. Datalink → live picture.

Empty store: the wizard fills the viewport. After a successful pair, the camera
is saved; next launch is **Your cameras**. **Pair new camera** re-enters the
wizard. The saved row being connected shows discovery/joining progress and
**Cancel**; camera names stay above availability and connection actions. Other
connection actions wait until the attempt finishes or is cancelled. On iOS,
**Watch a feed** is the eye button next to the Multiview grid button in the
camera-list header. Settings does not start a new pair. The wizard always offers **Share
Diagnostics** so a stuck first pair can still send a report.

Pocket and Nano are separate bodies. If Bluetooth reached a different camera
than the one tapped, say so and tell the operator to pick the matching row.

Simulator cannot exercise BLE or camera Wi-Fi. Wizard and reconnect changes are
**physical**.

## Failure and reconnect

Session recovery holds the last frame. A black well is a teardown or present-path
bug, not “Waiting for live view” copy over a live socket. Teardown rules:
[`live-session.md`](live-session.md). Stall policy: [`feed-watchdog.md`](feed-watchdog.md).

Recovery remains visible until a new source picture reaches the presentation
path. A handshake or repaint of the held image cannot dismiss it. The card names
the current step: looking for the saved camera, reconnecting, rejoining Wi-Fi,
restoring the connection, or waiting for a new picture. Retry connection and
Operator menu stay available. Automatic full-session recovery stops after at
most eight attempts or three minutes total, including radio waits and backoff.
The earlier feed-watchdog ladder has its own finite stages. A terminal state
does not keep showing an activity spinner.

Returning to the app validates the retained camera network. If the route changed
or the picture does not return, recovery runs the saved-camera connection spine
again. Brief scene changes with a healthy picture preserve the session. Movement
controls wait for the first picture and stop when the scene becomes inactive or
recovery takes ownership.

Renaming camera Wi-Fi updates the BLE name. Reconnect must join that live
name, not the previous SoftAP SSID still sitting in Keychain / Keystore
(#257). Deleting the saved row is not required.

Local VPNs and ad blockers can join camera Wi-Fi and still drop the live
UDP feed. Join Wi-Fi tells the operator to pause them or exclude this app
(`LocalVPNFilter.joinWifiPhoneStep`). After 8 s with no picture and a
tunnel still up, the waiting well uses `LocalVPNFilter.liveHint`. Do not
name AdGuard / Blokada / sister camera apps in chrome — the handbook FAQ
does.

Record confirmation is a bottom action sheet, not a centred dialog. Apple
Watch rec / shutter skips that sheet (the phone may be in a cage), same as
gamepad Cross/A.

Watch placeholders: **Open OpenPocketCine on iPhone** only when there is
no snapshot yet (not on wrist-down). **No camera connected** overlays even
a retained picture after an explicit disconnect; stale frame timecode is cleared.
**Waiting for live view** appears before the first picture. Always On keeps
rec / timecode / last frame on the dimmed face. Third-party apps cannot
match Flashlight brightness or disable the idle backlight.
`WKExtension.isFrontmostTimeoutExtended` is unsupported since watchOS 7.
Wake duration is **Settings → Display & Brightness → Wake Duration → 70
Seconds** on the watch (15 s default). After that the system Always On
dim applies; the companion does not extra-fade the picture.

Link health in the top bar is delivery (FPS chip), not RSSI.

Movable scopes and the LIGHTS / ND panels use direct touch-drag. Their corner
grips resize directly too. Scopes may sit partly under top and bottom readout /
assist bars and underneath the entire joystick/zoom/gimbal-controls cluster in
portrait or landscape. The cluster remains above scopes, and its visibility does
not change their placement boundary. Focus reset and audio meters do not fence
off a whole side of the screen.
Reserve the record/media/settings rail and portrait system button row with
8 pt/dp padding. The resize target extends only 12 pt/dp below the panel so it
can reach closer to the bottom edge. Use the visible panel body for horizontal
limits so left and right margins are equal. The visible corner fits within the
padding; its expanded touch area may extend beyond the side boundary. Fit and
clamp the body and vertical resize extent when dragging, resizing, restoring saved
positions, or changing orientation. Saved
scale remains the preferred size; a small screen can temporarily fit it smaller.
Toolbar long presses retain options access. Motion Control's editor keeps its
separate hold-to-move interaction.

## Help surfaces

- Long-press View Assist → options + help.
- Operator Setup: seven tabs (Link, Sharing, View Assist, Controls, Display,
  Storage, System). iOS Sharing: Share this feed, optional passcode, control
  requests, broadcast priority, and an explicit Show Wi-Fi code sheet. Watch a
  feed from home prompts joining the same camera Wi-Fi first: scan the host code
  with Camera, accept Join Network, then return and select the shared feed. Only
  the host opens a camera session. Discovery and streaming never use peer-to-peer. Android Sharing stays
  Coming soon. The watcher monitor keeps local assists/scopes, telemetry and REC
  tally around the picture. Request/Release control stays on the monitor; camera
  controls appear only with the host grant. Interrupted feeds hold the last frame,
  show bounded reconnect progress, and retain Leave / Choose a feed after failure.
- TestFlight / Play What to Test is this-build operator copy (`docs/tester-notes.md`).
- Connection setup (first pair): **Share Diagnostics** on the wizard so a
  tester who never reaches Operator Setup can still send a report.
- Operator Setup → System → **Share Diagnostics**. iOS screenshot for
  TestFlight copies a compact paste (`docs/diagnostics.md`).

## When this pointer fires

First-run, wizard, saved-camera list, operator-facing strings, assist help,
empty/error states, or reconnect copy. Run `OperatorFacingCopyTests` when iOS
strings change. Prove wizard and reconnect **physical**.
