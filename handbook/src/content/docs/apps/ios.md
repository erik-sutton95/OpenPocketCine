---
title: iOS app
description: SwiftUI iPhone and iPad shell. Physical device for BLE and camera Wi-Fi. TestFlight is the public beta.
---

The production iOS app is a universal iPhone and iPad SwiftUI shell in
`ios/OpenPocketCine/`. It is the operator-proven datalink. Generate the Xcode
project with XcodeGen — see [Setup](../guides/setup/).

## Field Monitor interface

The native UI uses Sora typography, cyan controls and dark panels. Portrait
phones place exposure values in two rows above the system buttons; landscape
puts those values along the bottom of the picture. **REC SETUP** opens capture
format, color and shooting options from the top of the monitor. Portrait keeps
Format / Color / Mode tabs on the details drawer; landscape has no extra
category row, and shooting mode is its own top control (not FORMAT). ISO,
shutter, white balance, focus and audio stay along the bottom and remain
visible while a top picker is open. Auto exposure keeps EV as the value and
shows the camera-chosen shutter under it (`EV 1/200s`). Tap a value for the full details drawer;
hold or drag for a compact dial. Lift to apply the selected value. Camera controls hold your selection while the
camera confirms it, so an older status update does not briefly move the dial back.
A rejected or unconfirmed change returns to the reported camera value after settling.
Capture tabs retain their matching labels while camera updates change the available modes.
Hold Record to open shooting mode.
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
Automated physical iPhone testing with Pocket 4 Pro verified Photo chrome in
portrait and both landscape orientations, the 3× Slow Motion 200p readout and
picker ceiling, continued live frames, and restoration of Video controls.
The test did not trigger still capture or recording; other bodies and the
remaining capture-submode controls still need physical qualification.
In portrait, Settings and Media remain usable with a picker open; returning to
the monitor restores that picker. The fitted feed is centered vertically; STBY,
timecode and REC SETUP sit in a separate row below the notch or status area.
View Assist, FIT/FILL and the joystick cluster stay above the camera values in
fixed positions when switching FIT/FILL.

The camera battery gauge shows the percentage reported by your Osmo, or a dash
when unavailable. Top capture settings, STBY and timecode align in one row;
Lock matches the Settings and Media button size.
The live signal indicator uses the Link Health colors from Settings: red for
Poor (0–1 bars), orange for Watch (2–3), and green for Stable (4).

Floating controls use blurred translucent panels with sharp labels and icons.
The blur tracks the live or playback picture. Reduce Transparency uses solid
panels. Some live-video paths use the system's blur treatment until decoded
picture samples are available.

The View Assist palette collapses into the lower-left control area. Expand it for the
full catalog; tap a tool to toggle it or hold to open its options inspector.
Playback uses that same live-view slot.
Image previews use the raw feed and work with all scopes off.
On Pocket 4 Pro, tap zoom to alternate 1× and 3×; double tap for 6× and 12×
when digital zoom is available. Other cameras retain their supported zoom stops.
Hold the zoom value for a continuous dial. The disc hub reads hundredths (1.53×)
and the chip still shows tenths. Its limits and recording restrictions
remain camera-specific. In landscape the larger disc sits on the trailing
screen edge and covers the controls beneath it until closed. In portrait it
sits on the bottom screen edge. Gimbal cameras expose Mode, Speed, Ramp and
the existing experimental Motion Control editor in a wider trailing drawer. Mode, Speed and
Ramp each have a tab with their own dial; the Motion Control action stays visible.

Operator Setup → Display includes **HDR display** (off by default). It uses this
iPhone or iPad's HDR panel so live view, scopes, settings, media, playback and
on-screen type stay readable in sun. The picture is a brightness aid, not a
grade: WAVE, HISTO, zebras and false color still read the decoded camera
signal. Screen recording and AirPlay temporarily use a normal SDR picture.
It does not change the camera's HDR/HLG color mode or the file on the card.
Turn it off indoors; extra brightness uses more power.

Operator Setup and Media use a navigation rail in landscape and scrolling tabs
in portrait. Settings and Media place Back outside the full-height sidebar in
landscape; portrait keeps it beside the brand and title in the header. Back uses
the same button styling as the live-view controls. The bottom of the Media sidebar
holds one row with Grid and List buttons and Small/Medium/Large sizes; in portrait,
these controls stay at the bottom of the page. Filter uses the same chip as Sort.
The filter card stays fully on screen, including next to the island and above
the home indicator. Set a start and end date with the calendar, and filter by
log/colour profile when that profile is known for a clip. Pull down on the library to refresh.
Hold a clip to begin selecting, then drag across clips to select a range. In
selection mode, swipe up or down to scroll without changing the selection, or
drag sideways to select a range. Hold a clip to sweep in any direction, including
near the top or bottom of the gallery to autoscroll; lift your finger to stop.
Selection circles appear only while selecting.

Media retains favorites, cache state,
playback assists and the existing delivery actions. Cached availability refreshes
as files finish downloading. In Operator Setup → Storage, **Local Media Cache**
shows **Checking…** while measuring stored files. **Clear Cache** keeps the clip
list and recorded color information; **Clearing…** shows while old files are
removed. A failed deletion stays included in the size so Clear can retry it.

Playback assists wait for a ready clip with a valid playback position before
requesting its first frame. Upscaler preparation runs separately from interface
updates. Physical qualification of these build 111 follow-up fixes is still pending;
report the time and action if playback or the interface freezes.

On iPad, the interface reflows as you resize the app window. System window buttons
stay clear of the monitor controls. Camera-connected use while resizing is still
under physical iPad validation.

View Assist favorites match the live system-button size and remember which
tools you actually use (saved on the phone). Collapsed, landscape keeps two
favorites and portrait keeps one, under the arrow. The expanded catalog
uses those same cells. Tap the arrow to open or close, or press and drag it
so the expanding edge stays under your finger; a flick finishes the motion.
The landscape expand
arrow accepts taps farther to its right, with the toolbar anchored in place.

## Moving scopes

Newly enabled windowed scopes start in the center, ready for you to place them.
The false-color reference key also starts centered and can be dragged.
Saved positions remain yours. AUDIO starts on the left at vertical center and
can also be dragged. Hold AUDIO for Vertical / Horizontal bars and optional
left/right dBFS readings; these affect the meter display, not camera recording.

Drag WAVE, PARADE, HISTO, VECTOR, LIGHTS, or ND directly to move it. Drag its
corner grip to resize. Scopes can sit partly under the top and bottom bars.
Scopes can reach closer to the bottom edge and sit underneath the entire joystick,
zoom, and gimbal-controls cluster in portrait or landscape. The cluster stays above
scopes. Panels can reach equally close to the left and right edges. Record,
media, and settings stay protected. Panels fit the available
space after rotation or resizing, including saved positions. Long-press a View Assist toolbar button for its settings.

## What it does

- Bluetooth pairing, camera Wi-Fi join, saved cameras, reconnect
- HEVC live view on Pocket 4 / 4 Pro; AVC observed on Pocket 3 and Osmo Nano
- Scopes, exposure/focus assists, framing tools, customizable DISP chrome.
  False color Scale is CineStop / EL Zone / IRE / Limits. CineStop is
  video-level IRE stripes over grayscale. EL Zone is 15 contiguous stops
  from 18% gray (+6 white, −6 black). IRE is six video-level zones over
  grayscale (crush, near-black, 18% gray, +1 stop, near clip, clip).
  Long-press options lift above the keyboard so number fields (Zebra
  Highlight / Midtone) stay visible; Done dismisses the number pad.
  Long-press LUT: DJI / Creative / Custom. DJI Auto uses the official Rec.709
  cubes. Creative is Mono / Contrast / Warm / Cool. Exposure compensation is
  −3…+3 at ½ stop before the cube. 50/50 log-vs-LUT is monitor-only and must
  not drop the live picture. Auto on a clip reads
  `com.dji.camera.ColorGammaSxS` from the original take (same field Mimo Color
  Recovery uses) — not the 720p LRF sidecar, which is Rec.709 even for log.
  Last live D-Log / D-Log2 is the fallback when that atom is missing —
  `colr`/`nclx` is Rec.709 even for log. Opening LUT on a disconnected clip
  keeps that Auto cube (it does not restamp from a missing live SET).
  In Photo and Live Photo, live monitoring uses Rec.709: DJI log conversions
  are hidden and bypassed, including a saved manual conversion. Creative and
  imported Custom looks remain available. Returning to Video restores the
  saved conversion unless you changed your LUT selection. Opening a recorded
  clip still uses that clip's color profile.
- Camera writes (record, ISO, EV, zoom, gimbal on Pocket). Current zoom chips are (Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×; Pocket 3 1×/2×/4×
  with 4K max 2×; Nano 1×). Pocket 3's confirmed **2.7K limit is 3×**; its
  generic 4× choice still needs correction ([survey](https://openpocketcine.app/docs/protocol/pocket3/#zoom-and-med-tele)).
  Zoom must not drop the live picture. FORMAT lists
  `camcap_video_format` pairs (2.7K / 4:3 / 1:1 / 9:16 when the body
  advertises them; aspect is the res byte). A tap stays on that pair until
  the body reports it. Pocket 3 normal Video also has a
  [documented fallback](https://openpocketcine.app/docs/protocol/commands/#pocket-3-format-choices-without-a-capability-table)
  when the camera supplies no capability table (16:9 and 1:1; 9:16 stays
  body Lock Portrait unless already reported); reported choices take priority.
  Physical iPhone build 99 passed one 2.7K/25 D-Log M record and warm reconnect
  ([survey evidence](https://openpocketcine.app/docs/protocol/pocket3/#openpocketcine-recording-and-warm-reconnect)).
  The full matrix, camera cold boot and other shooting modes remain unqualified.
  COLOR follows the body: D-Log2 is Pocket 4 Pro only; Pocket 4 is D-Log;
  Pocket 3 is D-Log M (HLG is HDR); Nano is 8-bit / 10-bit / D-Log M.
  Auto ISO ranges start at 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro.
  View Assist **ND** is a small chip on the live picture (centered until placed; drag to move). Long-press to switch Stops,
  ND32, or ND 0.3. It meters against middle gray and suggests a screw-on
  ND to balance the frame. The app cannot set a filter.
  The gimbal stick
  and zoom chip sit together as a cluster at the lower right: above the camera
  values in portrait and over the picture in landscape, on iPhone and iPad. A
  gimbal-controls button sits beside zoom (Pocket only). Its trailing drawer
  has Mode, Speed and Ramp tabs, each with its own dial: Follow / Tilt locked / FPV / Direction Lock,
  Slow / Default / Fast, and stick ramp. The Motion Control footer opens the experimental editor for an A→B (optional C) take
  (set A and B, choose each leg’s duration; hold and drag
  anywhere on the editor). With C set, Smoothness rounds the corner near B and shows a dashed curve.
  Zero hits B exactly; higher values bypass B while preserving A/C and total
  duration. There is no artificial speed cap. Moves are experimental: keep the camera fixed, rehearse,
  and check framing before a take. Programmed and head-tracking tilt targets
  stay within −44° to +70°. A missed timed point stops the move;
  professional positional/timing accuracy has not been qualified. Stick
  throw is analog with an ease-in curve (small push crawls; full throw is
  fastest). Selecting a gimbal mode switches off AirPods head tracking; enable
  and calibrate it again to resume. Direction Lock keeps the camera pointing in the same direction while
  the handle rotates; choose another mode to release it. The separate joystick-hold
  Lock Gimbal behavior remains under investigation and is not available in the app.
  Ramp smooths joystick-input changes: Off is immediate, Soft eases more gradually
  than Medium. Releasing the stick still stops immediately. Head tracking is experimental (Operator Setup → Controls,
  off by default). With AirPods that report motion, the compass above the
  joystick on the right is Calibrate Head Lock: that head pose and that
  gimbal pose are shared forward. A head turn pans the Pocket; a nod tilts.
  The gimbal follows that direction using direct angle targets. Roll is shown,
  not driven. The same control becomes STOP and clears the lock. Manual controls and Motion Control takes take
  priority; lost head motion pauses tracking. Allow Motion & Fitness when
  prompted. If motion never arrives, Calibrate offers an explicit retry;
  a Bluetooth connection alone does not confirm motion delivery.
  Scopes can be moved beneath the
  compass Head Lock control in either orientation. Responsiveness remains
  experimental. A connected game controller's selected stick drives the same path (Left by default).
  Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y
  tracks a face in frame or cancels. L1/R1 jump zoom out/in. L2/R2
  hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter.
  A toast says Gamepad connected or disconnected; unplug rests the
  stick. Operator Setup → Controls → Gamepad shows Connected / Not
  connected. Choose **Gimbal joystick → Left / Right** in the same Controls tab.
  D-pad shutter changes also update the shutter-angle readout when angle display is selected.
  A gimbal stop pulses only after the head moves then stalls
  (Haptics setting). Capture drums, the zoom disc, and duration
  dials pulse on coarse snaps (172° → 180°, 3×, whole seconds),
  not on every hundredth or half-second tick. Stick
  pan stays picture-relative. The rotate-180 button inverts pan at the
  end of the rotation (like Mimo). Extra-mirror live view when that 180
  lands and Selfie Flip is off; Flip on skips extra-mirror. The last
  picture stays for a couple of frames before that X-flip so the feed
  does not swap in place. Joystick yaw to 180 does not invert. Reconnect
  while at 180 inverts without another triple-tap. D-Log2 cannot zoom:
  idle hops to D-Log on the first step off 1× and waits for that color
  SET before any zoom write (the chip stays at 1× until D-Log lands);
  while rolling the chip grays and tap/pinch toast instead of changing
  color.
- Media library (Pocket 3: newest page lists after a take even if enter-playback ACKs E0; `/v2` is storage 0), playback with LUT / peaking / false colour / zebra on the 720p
  proxy (same present order as live: identity player and Metal are siblings;
  GPU latest-wins, freeze keeps the last frame). Preview LUT grades the
  decoded 420 frame on Metal at 1440 px — not `AVVideoComposition` (that
  path is export bake). LUT replace hides the player once Metal owns the
  picture. Next/prev with LUT on keeps the grade without cycling the chip.
  Auto LUT remembers shot color with the
  cached clip, so it still binds when the camera is disconnected. A **Proxy**
  tag means only the 720p sidecar is on the phone — connect to share the
  original. Storage **Full Resolution Caching** (on by default) also caches
  the original when you open a clip. Proxies download incrementally to disk
  to keep the interface responsive. LUT bake on export can include the
  LUT exposure pull (Bake exposure under Bake LUT; on by default).
  Convert log (off by default, exclusive with Bake LUT) offers an **Output
  curve** choice: D-Log or D-Log2 for the whole selection. Clips already on
  that curve keep their pixels; other log clips are converted and tagged with
  the destination curve. This is a technical transform, not a look.
  Camera originals stay untouched. Rec.709 stays Bake LUT; D-Log M is not converted.
- Optional Frame.io upload when you add your own Adobe keys (Platform API v4)
- Apple Watch companion: live preview, timecode, storage, camera battery,
  record / shutter. Preview works with AF-S and all image assists off, and
  follows the phone's horizontal picture flip. Disconnect labels the retained
  picture **No camera connected**. The iPhone stays on camera Wi-Fi; the Watch cannot join
  it. Keep the iPhone app open. Rec on the wrist does not ask for
  confirmation. The watch screen follows **Wake Duration** (Watch Settings →
  Display & Brightness; 70 Seconds is the maximum). Third-party apps cannot
  stay at Flashlight brightness. Always On keeps the last frame after the
  backlight dims.
- **Share this feed** (Operator Setup → Sharing): this iPhone re-serves live view to other OpenPocketCine iPhones and iPads on the **same camera Wi-Fi**. On the host, tap **Show Wi-Fi code**. Scan it with Camera on the watching device and accept **Join Network**, then return to OpenPocketCine → **Watch a feed** and select the host. You can also join that Wi-Fi in Settings. Only the host connects to the camera inside the app. The watcher has local view assists and scopes, camera readings, REC tally, and **Clean view**. **Request control** asks the host for permission to record, focus, and change supported ISO/shutter/zoom settings; **Release** gives it back. Brief interruptions hold the last picture and automatically retry three times. If sharing ends or reconnection fails, the watcher keeps the error visible; tap **Choose a feed** to rejoin. The QR code contains the Wi-Fi password; show it only to people you want on that network. An optional watcher passcode controls access to the feed separately. The host shares one encode, and a slow watcher waits for a fresh keyframe while others continue. Peer-to-peer discovery and streaming are disabled because they caused severe stuttering during physical testing. One iPad watcher was reported smooth after joining the same Wi-Fi; multiple watchers still need physical verification. Android Sharing is not in this build.

The final watcher QR onboarding, passcode and recovery changes still need
dedicated physical acceptance. The earlier one-iPad smoothness report does not
qualify those newer flows or multiple wireless watchers. See the
[watcher relay evidence](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/watcher-relay.md).

On **Your cameras**, PAIRED and NEARBY groups separate remembered cameras from
new discoveries. Select a camera to see its connection progress and **Cancel**.
**Pair new camera** opens the guided flow; select a discovered camera, then
**Continue**. Media and Settings remain available without connecting.

**Multiview** is an experimental iPhone/iPad stage for several cameras on shared
Wi-Fi. From **Your cameras**, tap the grid icon to set up the network and add
cameras. Each camera has its own preview and recording controls; Record all
requests recording together without frame-accurate synchronization. See the
[Multiview guide](https://openpocketcine.app/docs/guides/multiview-prototype/) for supported observations,
session network selection, saved preferences and remaining physical checks. Pocket 3, Pocket 4 Pro and
Nano preview and recording have been checked together on iPhone. Pocket 3
recovery after an app switch required a full rejoin and roughly a minute in the
recorded test. Android Multiview remains unavailable.

Tap Layout to switch Grid/Center stage; hold Layout for Shared Wi-Fi. Clean
hides the upper session controls and assist palette; DISP restores them.

Motion Control shows A, B and C with their reported pan, tilt and zoom, or
**Not set**. The joystick remains usable while the editor is open, so you can
position the camera before saving a point. Other outside taps minimize the editor
without activating the controls behind it. Durations use half-second dials up to
120 seconds. Swipe left to increase duration and right to decrease it. Drag the expanded window or minimized pill directly; no hold is needed.
Duration dials and sliders keep their own gestures. Dragging
does not activate Start/Stop or expand. Start shows a cancellable three-second
countdown before preparation and approach to A. Pause holds the move; Resume
continues from the stopped position without another countdown. Stop clears the
continuation. Manual control or disconnect also cancels a paused move. Long pan returns follow
the reachable arc rather than wrapping through the gimbal stop. Selfie Flip
does not reverse stored mechanical angles; MIRROR changes the preview only.
The recorded physical motion checks are on Pocket 4 Pro; Pocket 3 and broader
firmware qualification remain pending. See
[Motion Control qualification](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/programmed-moves.md#evidence-and-qualification).

Verify record start/stop on the camera body until you trust the link.

If live view never starts after Wi-Fi joins, pause local VPNs and ad
blockers or exclude this app
([Troubleshooting](../guides/troubleshooting/)).

## Device requirements

BLE, Local Network, and Hotspot Configuration do not work in the Simulator.
Operator-visible UI changes are proven on a **physical** iPhone (and iPad when
the layout is in play). Protocol tests (`just test`) do not need hardware.
iPad hides the system time / battery bar; monitor chrome is the HUD.

Platform notes for the wire (Hotspot Configuration, Local Network, CoreBluetooth):
[iOS protocol notes](../protocol/ios/).

## Releases

Public beta: [TestFlight](https://testflight.apple.com/join/1tmt3aEB). PRs that
change `Sources/`, `ios/`, or `Package.swift` replace
`ios/TestFlight/WhatToTest.en-US.txt` with the this-build window. See
[`docs/tester-notes.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/tester-notes.md).

Maintainers using Xcode Cloud must register both the iPhone bundle ID and
`com.opencapture.openpocketcine.watch` on their Apple Developer team before
exporting an archive with the Watch companion. Cloud cannot register the Watch
identifier during export. Setup and export-log troubleshooting:
[Watch companion signing](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/testflight-ci.md#watch-companion-signing).

If pairing or live view fails: Connection setup **Share Diagnostics**, or
Operator Setup → System → **Share Diagnostics**, or take a screenshot for
TestFlight and paste the copied report into the feedback. The report has no
name, location, or Wi-Fi password.

### False color during exposure changes

False color keeps its previous complete color map while an updated exposure map
is prepared. The picture continues updating; paint and coverage switch together.
The first activation can still take a moment to prepare the map.

D-Log M scopes use their own signal scale. Sensor clipping and shadow limits
remain uncalibrated; see the D-Log M scope notes below.

Video and assist overlays resize together when rotating the phone or switching
between Fit and Fill, keeping false color, peaking, and zebra paint aligned with
the picture during the transition.

### D-Log M scopes

D-Log M uses a direct 0–100 preview-signal scale for waveform, parade, histogram
and zebras, without the D-Log black-point or ISO ceiling. Low/high signal warnings
do not establish where the camera sensor loses detail. EL Zone (`DLM ≈`) and the
gray guide use an estimated Pocket 3 curve; use IRE for signal measurements,
especially on other D-Log M cameras. Live-preview calibration remains pending.

ND recommendations also derive stops from that estimated curve. Treat D-Log M
ND readings as estimates, not calibrated filter or sensor-limit measurements.
LUT exposure compensation, including **Bake exposure** on export, and Face
Priority EV still use the previous D-Log approximation for D-Log M. The scope
fix did not calibrate those controls. This limitation concerns exposure math,
not the choice of the official D-Log M conversion cube. See the
[D-Log M investigation](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/pocket3-dlogm-curve.md).

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
**Operator Setup → System → Automatic error reports**.

If System says “This build cannot send automatic reports,” the installed build
has no reporting destination. A configured TestFlight update is required;
reinstalling the same build will not enable it. When that update arrives, the
app asks if you have not previously chosen Enable or Not now.
