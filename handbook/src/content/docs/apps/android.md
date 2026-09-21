---
title: Android app
description: Jetpack Compose phone shell on a cross-compiled Swift core. Google Play public beta. arm64-v8a only.
---

The Android app lives in `Apps/Android/`. It is an early phone shell: pairing,
HEVC/AVC live view, GPU looks, scopes, camera writes, and media. The public beta on
Google Play is open — [join the Android beta](https://play.google.com/store/apps/details?id=com.opencapture.openpocketcine&hl=en-US&ah=mXzHtdYCMQTB83vt0jIRLnOOZaA). iOS is the daily driver. arm64
phones, Android 10 or newer.

If pairing or live view fails, tap **Report a problem** on the pairing screen or
in **Operator Setup → System**. It works before your first successful pairing;
technical details and a reply email are optional. For a local diagnostic export,
use pairing's overflow menu → **Share Diagnostics** or System → **Diagnostic
options → Save diagnostic report**. Local VPNs and ad blockers (AdGuard, Blokada,
RethinkDNS) can block the UDP live feed after Wi-Fi joins — pause them or
exclude this app ([Troubleshooting](../../guides/troubleshooting/)).

On **Your cameras**, PAIRED and NEARBY groups separate remembered cameras from
new discoveries. Select a camera to see its connection progress and **Cancel**.
**Pair new camera** opens the guided flow; select a discovered camera, then
**Continue**. Media and Settings remain available without connecting.

## Field Monitor interface

The camera battery gauge shows the percentage reported by your Osmo, or a dash
when unavailable. Top capture settings, STBY and timecode align in one row;
Lock matches the Settings and Media button size.
The live signal indicator uses the Link Health colors from Settings: red for
Poor (0–1 bars), orange for Watch (2–3), and green for Stable (4).

The native UI uses Sora typography, cyan controls and dark panels.
Camera readouts have a layered dark glow for contrast over bright footage.
Outer monitor controls sit close to the screen edges while retaining cutout clearance.
In portrait, STBY, timecode and REC SETUP share a row below storage and battery indicators.
Live view and photo/video playback hide both Android system bars; swipe from an
edge for temporary access. Playback has a visible Back/Close control to return to Media.
Other pages hide the status bar but keep Home, Back and Recents available when your
phone uses button navigation; gesture navigation follows your phone settings.
Controls leave room for the navigation bar and camera cutout. Portrait
phones place exposure values in two rows above the system buttons; landscape
puts those values along the bottom of the picture. **REC SETUP** opens capture
format, color and shooting options from the top of the monitor. Portrait keeps
Format / Color / Mode tabs on the details drawer; landscape has no extra
category row. Landscape shows the shooting mode immediately after the color profile in the top row,
including narrow phones. Photo shows its mode in the top row. ISO,
shutter, white balance, focus and audio stay along the bottom and remain
visible while a top picker is open. Auto exposure keeps EV as the value and
shows the camera-chosen shutter under it (`EV 1/200s`). Tap a value for the full details drawer;
hold or drag for a compact dial. Lift to apply the selected value. Camera controls hold your selection while the
camera confirms it, so an older status update does not briefly move the dial back.
A rejected or unconfirmed change returns to the reported camera value after settling.
Use the top shooting-mode control in landscape or REC SETUP → Mode in portrait.
Record and the Photo shutter have no shooting-mode long-press shortcut.
In **Photo**, the capture control becomes a shutter and takes a photo immediately,
without recording confirmation. Photo and camera-reported Live Photo hide video color-profile, frame-rate,
codec/bit-depth, timecode, recording-duration and audio controls. White balance,
ISO, EV, shutter speed, focus, zoom and photographic assists remain available.
Video-only panels close when the camera changes to a still-photo mode, and
returning to Video restores the relevant controls without resetting assist
preferences. Pocket 4 Pro Slow Motion labels 200 fps as **200p**, including the
3× lens's reported options; available rates follow the current camera capability
list rather than a fixed wide-lens maximum. **Low-Light / SuperNight** retains start/stop recording.
Changing modes clears stale format choices. A pending recording confirmation is
dismissed if the mode, recording state, connection, or interface lock changes.
Shooting-mode access in both orientations and Video/Photo switching have been
checked on a Galaxy S25 with Pocket 4 Pro. The full specialty-mode matrix remains
outside that check.
In portrait, Settings and Media remain usable
with a picker open; returning to the monitor restores that picker. Camera values use two
complete rows in portrait and one row in landscape. Assist palettes stay below Settings,
Media and assist inspectors. In an inspector, scroll the preview and options together;
LUT exposure and split comparison remain pinned below the scrolling catalog.

The View Assist palette collapses into the lower-left control area. Expand it for the
full catalog; tap a tool to toggle it or hold to open its options inspector.
Playback uses that same live-view slot.
Video playback places its filename, metadata and source label above Favorite,
Info, Share and Delete (when available). The timeline sits above Back 15 seconds,
Play/Pause and Forward 15 seconds; landscape places the other playback options
in that same row. Side arrows change clips. Photo review keeps Share/Delete at
the top and Favorite at the bottom, matching iOS.
On Pocket 4 Pro, tap zoom to alternate 1× and 3×; double tap for 6× and 12×
when digital zoom is available. Other cameras retain their supported zoom stops.
Hold the zoom value for a continuous dial. Its limits and recording restrictions
remain camera-specific. Gimbal cameras expose Mode, Speed, Ramp and the existing
experimental Motion Control editor in a wider trailing drawer. Mode, Speed and
Ramp each have a tab with their own dial; the Motion Control action stays visible. All three waypoint rows show the
reported pan, tilt and zoom, or **Not set**. Tap outside to minimize the editor
without activating the controls behind it. Until dragged, the editor stays centered
when the screen rotates; a manually placed editor keeps its chosen position.

Operator Setup → Display includes **HDR display** (off by default). It uses this
phone's HDR panel so live view, scopes, settings, media, playback and on-screen
type stay readable in sun. It does not change the camera's HDR/HLG color mode
or the file on the card. WAVE and HISTO still measure the decoded picture. Turn
it off indoors; extra brightness uses more power.

Operator Setup and Media use a navigation rail in landscape and scrolling tabs
in portrait. Settings groups use compact information buttons beside their labels;
Controls groups touch safety, gimbal options, and the on-screen joystick separately.
Use Android’s system Back button or back gesture to return from
Settings, Media library and pairing. These pages omit the large in-app Back button.
Photo/video playback hides system navigation and provides its own Back/Close control. Back dismisses the
current overlay or selection before leaving its page. Contextual Close and
Cancel actions remain available. The bottom of the Media sidebar
holds one row with Grid and List buttons and Small/Medium/Large sizes; in portrait,
these controls stay at the bottom of the page. Filter uses the same chip as Sort.
The filter card stays fully on screen, including next to a display cutout and
above the navigation bar. Set a start and end date with the calendar, and filter
by log/colour profile when that profile is known for a clip. Pull down on the library to refresh.
Hold a clip to begin selecting, then drag across clips to select a range. In
selection mode, swipe up or down to scroll without changing the selection, or
drag sideways to select a range. Hold a clip to sweep in any direction, including
near the top or bottom of the gallery to autoscroll; lift your finger to stop.
Selection circles appear only while selecting.

Media retains favorites, cache state,
playback assists and the existing delivery actions.

View Assist favorites match the live system-button size and remember which
tools you actually use (saved on the phone). Collapsed, landscape keeps two
favorites and portrait keeps one, under the arrow. The expanded catalog
uses those same cells. Tap the arrow to open or close, or press and drag it
so the expanding edge stays under your finger; a flick finishes the motion.
In portrait, drag upward to expand and downward to collapse. Pausing holds the
edge steady; changing direction moves it back with your finger. Locking the
monitor cancels a drag and collapses the palette.
The landscape expand
arrow accepts taps farther to its right, with the toolbar anchored in place.

## Moving scopes

Newly enabled windowed scopes start in the center, ready for you to place them.
The false-color reference key also starts centered and can be dragged.
Portrait and landscape keep separate scope positions. Existing saved positions
remain the landscape positions. AUDIO starts on the left at vertical center and
can also be dragged. Hold AUDIO for Vertical / Horizontal bars and optional
left/right dBFS readings; these affect the meter display, not camera recording.

Drag WAVE, PARADE, HISTO, VECTOR, LIGHTS, or ND directly to move it. Drag its
corner grip to resize. Scopes can sit partly under the top and bottom bars.
Scopes can reach closer to the bottom edge and sit underneath the entire joystick,
zoom, and gimbal-controls cluster in portrait or landscape. The cluster stays above
scopes. Panels can reach equally close to the left and right edges. Record,
media, and settings stay protected. Panels fit the available
space after rotation or resizing, including saved positions. Long-press a View Assist toolbar button for its settings.

Connection recovery now protects the first picture after replacing a connection
and detects when arriving traffic cannot produce a usable picture. A dropped
reference frame keeps recovery active until a new keyframe arrives. These
changes have automated regressions; sustained phone-and-camera qualification
is pending. If picture stops, share diagnostics with the action and time.

A Pocket 4 Pro test held 25 fps for five minutes, but later exposed slow startup
and short freezes after incomplete video data. Startup now waits for the camera's
command window; known dropped-reference recovery can act sooner while keeping
the last image visible. Validation of these follow-up fixes is still in progress;
the earlier clean segment does not establish uninterrupted reliability.

Returning from Media now starts live view once and waits for a fresh picture.
An older live-picture deadline no longer treats intentional browsing as a failed
feed. If live view cannot return, bounded connection recovery takes over. Please
test repeated browsing, playback and return with a connected camera; physical
qualification of this follow-up is still pending.

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

Build recipes: [Setup](../../guides/setup/). The living JNI/I/O notes:
[`ANDROID.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/ANDROID.md).

## Operator surface

Chrome, assists, capture, Operator Setup, and media are meant to match iOS.
Current zoom chips are (Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×;
Pocket 3 1×/2×/4× with 4K max 2×; Nano 1×). Pocket 3's ceiling is
per-FORMAT, not one generic 4×: **1080 4×, 2.7K 3×, 2160 1:1 3×, 4K 2×,
3K 1:1 2×**
([survey](https://openpocketcine.app/docs/protocol/pocket3/#zoom-and-med-tele)). Zoom must not drop the live
picture. FORMAT lists `camcap_video_format` pairs (2.7K / 4:3 / 1:1 / 9:16
when the body advertises them; aspect is the res byte). A tap stays on that
pair until the body reports it. Pocket 3 normal Video also has a
[FORMAT fallback](https://openpocketcine.app/docs/protocol/commands/#pocket-3-format-choices-without-a-capability-table)
when the camera supplies no capability table (16:9 and 1:1; 9:16 stays
body Lock Portrait unless already reported). Reported choices take priority;
separate Pocket 3 Slow Motion and Low-Light fallbacks use the accepted pairs in
the survey. Unknown modes have no fallback. The full
Pocket 3 format/record/reconnect matrix still needs physical Android checks.
COLOR follows the body: D-Log2 is Pocket 4 Pro
only; Pocket 4 is D-Log; Pocket 3 is D-Log M (HLG is HDR); Nano is 8-bit /
10-bit / D-Log M. Auto ISO ranges start at 50 on Pocket 3 / Pocket 4 and 100
on Pocket 4 Pro. View Assist **ND** is a small chip on the live picture
(centered until placed; drag to move). Long-press to
switch Stops, ND32, or ND 0.3. It meters against middle gray and suggests
a screw-on ND to balance the frame. The app cannot set a filter. The gimbal stick and zoom chip sit together as a cluster in the
trailing-bottom of the picture, same as iOS. A gimbal-controls button sits
beside zoom (Pocket only). Its trailing drawer has Mode, Speed and Ramp
tabs, each with its own dial, showing Follow / Tilt locked / FPV / Direction Lock, Slow / Default / Fast,
and stick ramp. The Motion Control footer opens the experimental editor for an A→B (optional C) take (set A and B, choose each
leg’s duration; drag the editor directly). With C set, Smoothness rounds B and shows a dashed curve.
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
game controller's selected stick drives the same path (Left by default). Cross/A records.
Circle/B recenters. Square/X is rotate-180. Triangle/Y tracks a face
in frame or cancels. L1/R1 jump zoom out/in. L2/R2 hold-to-zoom
(deeper is faster). D-pad up/down ISO, left/right shutter. A toast
says Gamepad connected or disconnected; unplug rests the stick.
Operator Setup → Controls → Gamepad shows Connected / Not connected.
Choose **Gimbal joystick → Left / Right** in the same Controls tab. D-pad shutter
changes also update the shutter-angle readout when angle display is selected.
A gimbal stop pulses only after the head moves then stalls (Haptics
setting). Capture drums, the zoom disc, and duration dials pulse on
coarse snaps (172° → 180°, 3×, whole seconds), not on every hundredth
or half-second tick. AirPods head tracking is iPhone-only (no headphone IMU)
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
input-referred before the cube). Photo and Live Photo use Rec.709 for live
monitoring. DJI log conversions are hidden and bypassed, including saved manual
conversions; Creative and imported Custom looks remain available. Returning to
Video restores the saved conversion unless you changed your LUT selection.
Recorded clips keep their own color profile.
50/50 log-vs-LUT is monitor-only and must
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
Platform differences, including Frame.io and MetalFX, are listed in
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md).

The fitted portrait feed is centered vertically, with STBY, timecode and REC SETUP in
a separate row below the status area. View Assist, FIT/FILL and the joystick
cluster stay above the camera values in fixed positions when switching FIT/FILL.
Hold zoom for a continuous dial. The disc hub reads hundredths (1.53×); the chip
still shows tenths. In landscape the larger zoom disc sits on the trailing screen
edge and covers the controls beneath it until closed. In portrait it sits on the
bottom screen edge.

The joystick remains usable while the Motion Control editor is open, so you can
position the camera before saving a point. Other outside taps minimize the editor.
Motion Control durations use half-second dials up to 120 seconds. Swipe left
to increase duration and right to decrease it. Drag the expanded window or minimized pill directly; no hold is needed.
Duration dials and sliders keep their own gestures. Dragging
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
as iOS), then bilinear-fit the panel (peaking is the same 3-pass as GLES).
Floating controls use blurred translucent panels with sharp labels and icons.
The blur tracks the live or playback picture. Devices or sources that cannot
supply the blur use solid readable panels.
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

### TalkBack

The live-view readouts and the assist cells each speak as one labelled stop:
the REC chip reads state with elapsed time, the battery rows name phone or
camera and say "level unknown" rather than leaving a dash unvoiced, the
timecode names itself, and an assist cell reads its tool name, state and hold
gesture instead of its 9sp abbreviation.

Labelling a container needs `clearAndSetSemantics`. Plain `semantics` does not
absorb children, and `mergeDescendants = true` does not suppress them either —
the platform publishes the parent description *and* every child `Text` as
separate stops, even though Compose reports the merge as having happened. Leaf
nodes keep plain `semantics`, since a `Text` has nothing to absorb, and
`MonitorSlider` keeps its `progressBarRangeInfo` and set action, which a clear
would erase. `LiveChromeSemanticsTest` pins the rule against the platform
accessibility tree, so a copy of the wrong pattern fails there rather than on a
tester's phone.

Verified on a physical SM-S918B / Android 16. Media, settings and pairing carry
the same container leak and are a later pass.

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

### Saving photos and clips

**Save to Photos** places photos in Pictures/OpenPocketCine and videos in
Movies/OpenPocketCine. If Android cannot prepare a file for sharing, the app
shows an error. Camera originals remain unchanged.

### Upcoming share destinations

Share shows Google Drive, Dropbox, NAS (SMB), LucidLink, Backblaze B2 and
Vimeo Review as **Coming soon**. These destinations are previews of planned
support and cannot be selected yet. Use the available destinations to share now.

### On-screen joystick feel

In **Controls → On-screen joystick**, tune the virtual gimbal stick:

- **Invert pan** and **Invert tilt** reverse each direction independently.
- **Dead zone** ignores small movements near the center. The default is 8%.
- **Response curve** changes how movement grows with stick travel: Linear is
  direct, Standard keeps the current feel, and Fine gives gentler small moves.

Both inversion options default to off and the response defaults to Standard.
These settings are saved and affect the on-screen joystick. The existing
sensitivity setting continues to control overall speed.

The touch range extends 35% beyond the joystick's outer radius while the ring
and knob keep their existing size. Continue dragging past the ring for full
input. Returning to the center during a drag respects the dead zone; lifting
your finger releases the stick.

### Automatic error reports

On the first launch with automatic reporting available, the app asks whether to
send optional crash, error and feed-dropout reports. This also applies after an
update if you have never made that choice. Enable or Not now is remembered;
updates do not ask again after a decision. You can change the choice in
**Operator Setup → System → Automatic error reports**. The prompt keeps both
choices in a vertical button stack and scrolls when screen space is limited.
