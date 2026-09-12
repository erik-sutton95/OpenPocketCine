---
title: Android app
description: Jetpack Compose phone shell on a cross-compiled Swift core. Play closed testing. arm64-v8a only.
---

The Android app lives in `Apps/Android/`. It is an early phone shell: pairing,
HEVC/AVC live view, GPU looks, scopes, camera writes, and media. Closed testing on
Google Play is the TestFlight analog — join from
[openpocketcine.app](https://openpocketcine.app/). iOS is the daily driver. arm64
phones, Android 10 or newer.

If pairing or live view fails: Connection setup **Share Diagnostics**, or
Operator Setup → System → **Share Diagnostics**. The report has no name,
location, or Wi-Fi password. Local VPNs and ad blockers (AdGuard, Blokada,
RethinkDNS) can block the UDP live feed after Wi-Fi joins — pause them or
exclude this app ([Troubleshooting](../guides/troubleshooting/)).

On **Your cameras**, PAIRED and NEARBY groups separate remembered cameras from
new discoveries. Select a camera to see its connection progress and **Cancel**.
**Pair new camera** opens the guided flow; select a discovered camera, then
**Continue**. Media and Settings remain available without connecting.

## Field Monitor interface

The native UI uses Sora typography, cyan controls and dark panels. Portrait
phones place exposure values in two rows above the system buttons; landscape
puts those values along the bottom of the picture. **REC SETUP** opens capture
format, color and shooting options. Drag a value drum to select a supported
camera value; lift to apply it. Hold Record to open shooting mode.

The View Assist palette collapses into the picture corner. Expand it for the
full catalog; tap a tool to toggle it or hold to open its options inspector.
Hold the zoom value for a continuous dial. Its limits and recording restrictions
remain camera-specific. Gimbal cameras expose Mode, Speed, Ramp and the existing
experimental Motion Control editor in a trailing drawer. All three waypoint rows show the
reported pan, tilt and zoom, or **Not set**. Tap outside to minimize the editor
without activating the controls behind it. Until dragged, the editor stays centered
when the screen rotates; a manually placed editor keeps its chosen position.

Operator Setup and Media use a navigation rail in landscape and scrolling tabs
in portrait. Media retains grid/list views, selection, favorites, cache state,
playback assists and the existing delivery actions.

## Moving scopes

Drag WAVE, PARADE, HISTO, VECTOR, LIGHTS, or ND directly to move it. Drag its
corner grip to resize. Scopes can sit partly under the top and bottom bars.
Scopes can reach closer to the bottom edge and sit underneath the entire joystick,
zoom, and gimbal-controls cluster in portrait or landscape. The cluster stays above
scopes. Panels can reach equally close to the left and right edges. Record,
media, and settings stay protected. Panels fit the available
space after rotation or resizing, including saved positions. Long-press a View Assist toolbar button for its settings.

## How Swift reaches Android

Business logic stays in `OpenPocketViewCore`. Android follows the OpenZCine
pattern, not Skip/SKIE:

1. Portable Swift core (no SwiftUI, UIKit, or Android imports).
2. `OpenPocketCineAndroidFacade` — session + hand-written JNI (`@_cdecl`).
3. Gradle `:app:stageSwiftCore` (`just android-core`) builds
   `aarch64-unknown-linux-android29` and stages `libOpenPocketCineAndroid.so`.
   **arm64-v8a only.** Toolchain pin: Swift **6.3.3**.
4. Kotlin `core-api` wraps JNI. Kotlin does not pack protocol bytes. Live
   handshake / first-picture / enable-once policy is `cameraSoftAPDecision` in
   the Swift facade — a handshake miss is a recoverable session error, not a
   crash.

Build recipes: [Setup](../guides/setup/). The living JNI/I/O notes:
[`ANDROID.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/ANDROID.md).

## Operator surface

Chrome, assists, capture, Operator Setup, and media are meant to match iOS.
Current zoom chips are (Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×;
Pocket 3 1×/2×/4× with 4K max 2×; Nano 1×). Pocket 3's confirmed **2.7K
limit is 3×**; its generic 4× choice still needs correction
([survey](https://openpocketcine.app/docs/protocol/pocket3/#zoom-and-med-tele)). Zoom must not drop the live
picture. FORMAT lists `camcap_video_format` pairs (2.7K / 4:3 / 1:1 / 9:16
when the body advertises them; aspect is the res byte). A tap stays on that
pair until the body reports it. Pocket 3 normal Video also has a
[FORMAT fallback](https://openpocketcine.app/docs/protocol/commands/#pocket-3-format-choices-without-a-capability-table)
when the camera supplies no capability table. Reported choices take priority;
this fallback does not apply to SlowMo or unknown shooting modes. The full
Pocket 3 format/record/reconnect matrix still needs physical Android checks.
COLOR follows the body: D-Log2 is Pocket 4 Pro
only; Pocket 4 is D-Log; Pocket 3 is D-Log M (HLG is HDR); Nano is 8-bit /
10-bit / D-Log M. Auto ISO ranges start at 50 on Pocket 3 / Pocket 4 and 100
on Pocket 4 Pro. View Assist **ND** is a small chip on the live picture
(bottom-left, above the assist bar; drag to move). Long-press to
switch Stops, ND32, or ND 0.3. It meters against middle gray and suggests
a screw-on ND to balance the frame. The app cannot set a filter. The gimbal stick and zoom chip sit together as a cluster in the
trailing-bottom of the picture, same as iOS. A gimbal-controls button sits
beside zoom (Pocket only). Its trailing drawer has inline Mode, Speed and Ramp
drums showing Follow / Tilt locked / FPV / Direction Lock, Slow / Default / Fast,
and stick ramp. The Motion Control footer opens the experimental editor for an A→B (optional C) take (set A and B, choose each
leg’s duration; long-press-drag the editor). With C set, Smoothness rounds B and shows a dashed curve.
Zero hits B exactly; higher values bypass B while preserving A/C and total
duration. There is no artificial speed cap. Moves are experimental: keep
the camera fixed, rehearse, and check framing before a take. Tilt targets stay
within −44° to +70°. A missed timed
point stops the move; professional positional/timing accuracy has not been qualified. Stick throw is analog with
an ease-in curve (small push crawls; full throw is fastest). Direction Lock keeps
the camera pointing in the same direction while the handle rotates; choose
another mode to release it. The separate joystick-hold Lock Gimbal behavior
remains under investigation and is not available in the app. Ramp smooths
joystick-input changes: Off is immediate, Soft eases more gradually than Medium.
Releasing the stick still stops immediately. A connected
game controller's left stick drives the same path. Cross/A records.
Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face
in frame or cancels. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom
(deeper is faster). D-pad up/down ISO, left/right shutter. A toast
says Gamepad connected or disconnected; unplug rests the stick.
Operator Setup → Controls → Gamepad shows Connected / Not connected.
A gimbal stop pulses only after the head moves then stalls (Haptics
setting). AirPods head tracking is iPhone-only (no headphone IMU
on Android). Stick pan stays
picture-relative. Stick triple-tap 180 inverts pan at the end of the
rotation (like Mimo). Extra-mirror live view when that 180 lands and
Selfie Flip is off; Flip on skips extra-mirror. The last picture stays
for a couple of frames before that X-flip so the feed does not swap in
place. Invert is the rotate-180 button at settle, not joystick 180.
Reconnect-at-180 seeds TT180 from settled attitude (a 0° stub does not
lock front). D-Log2 cannot zoom while rolling — the chip grays and
tap/pinch toast; idle hops to D-Log on the first step off 1× and waits
for that color SET before any zoom write (the chip stays at 1× until
D-Log lands).
Long-press View Assist options lift above the keyboard so Zebra Highlight /
Midtone stay visible (Done on the number pad), matching iOS. False color
Scale is CineStop / EL Zone / IRE / Limits. CineStop is video-level IRE
stripes over grayscale. EL Zone is 15 contiguous stops from 18% gray
(+6 white, −6 black). IRE is six video-level zones over grayscale
(crush, near-black, 18% gray, +1 stop, near clip, clip).
Long-press LUT for the same exposure compensation as iOS (−3…+3 at ½ stop,
input-referred before the cube). 50/50 log-vs-LUT is monitor-only and must
not drop the live picture (GPU split only while a cube is loaded). Next/prev
with LUT on keeps the grade on
the same GLES host (ExoPlayer writes an OES surface; LUT / PEAK / FALSE /
ZEBRA grade in `LiveFeedEffectsSession` like live — TextureView is only the
window). Auto on a clip reads `com.dji.camera.ColorGammaSxS`
from the original take like iOS — not the LRF/XRF sidecar (Rec.709 even
for log). Shot color is stored with the cached clip. A **Proxy** tag means
only the 720p sidecar is on the phone. Storage **Full Resolution Caching**
matches iOS. Pocket 3 `/v2` is storage 0; the newest catalog page lists
after a take even if enter-playback ACKs E0. Share/save is the original
camera file — LUT bake, Bake exposure, and Convert log are iOS only.
Multiview and Sharing are unavailable on Android. The
[Multiview guide](https://openpocketcine.app/docs/guides/multiview-prototype/) describes the experimental
iPhone/iPad feature and its validation limits.
Exceptions (Frame.io, MetalFX, iOS 26 Liquid Glass, …) are listed in
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md).

Motion Control durations use half-second dials up to 120 seconds. Swipe left
to increase duration and right to decrease it. Move the expanded
window by holding anywhere, or drag the minimized pill directly. Dragging
does not activate Start/Stop or expand. Start shows a cancellable three-second
countdown before preparation and approach to A. Pause holds the move; Resume
continues from the stopped position without another countdown. Stop clears the
continuation. Manual control or disconnect also cancels a paused move. Long pan returns follow
the reachable arc rather than wrapping through the gimbal stop. Selfie Flip
does not reverse stored mechanical angles; MIRROR changes the preview only.
Physical Android Motion Control and Pocket 3 qualification remain pending; the
recorded motion checks are on Pocket 4 Pro/iPhone. See
[Motion Control qualification](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/programmed-moves.md#evidence-and-qualification).

Live picture: Vulkan when the device can init it; GLES fallback. Live LUT /
PEAK / FALSE / ZEBRA grade the decoded 720p raster with a 3D cube (same lattice
as iOS), then bilinear-fit the panel (peaking is the same 3-pass as GLES). HUD liquid
floating chrome uses composited translucent tint without a live-frame backdrop copy.
Page cards are solid. Assist inspectors show the selected scope or image effect
without requiring that tool on the main picture. Image previews reuse the existing
small source sample and effect shaders, with at most one job at 5 Hz while visible.
Present path matches iOS `FeedPresentPolicy` (skip duplicate timestamps, keep
the last frame on freeze, one live-enable write at a time, latest-wins
present). Opening clips or
Operator Setup over live view keeps the video GOP and the live SurfaceView;
returning to the monitor must not leave a black well. Leaving live view,
opening clips, or rotating must drop the Vulkan swapchain with the window —
present after that is a skip, not a crash.

Wi-Fi passwords stay in Keystore, not saved-camera JSON. Pairing and live view
need a **physical** Android phone.

## What not to copy from OpenZCine Android

Nikon PTP-IP, AccessorySetupKit, OCR SSID scanner, USB-C/HDMI paths.

### D-Log M scopes

D-Log M uses a direct 0–100 preview-signal scale for waveform, parade, histogram
and zebras, without the D-Log black-point or ISO ceiling. Low/high signal warnings
do not establish where the camera sensor loses detail. EL Zone (`DLM ≈`) and the
gray guide use an estimated Pocket 3 curve; use IRE for signal measurements,
especially on other D-Log M cameras. Live-preview calibration remains pending.

ND recommendations also derive stops from that estimated curve. Treat D-Log M
ND readings as estimates, not calibrated filter or sensor-limit measurements.
LUT exposure compensation and Face Priority EV still use the previous D-Log
approximation for D-Log M; the scope fix did not calibrate those controls. This
limitation concerns exposure math, not the choice of the official D-Log M
conversion cube. See the
[D-Log M investigation](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/pocket3-dlogm-curve.md).
