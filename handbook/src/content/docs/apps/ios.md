---
title: iOS app
description: SwiftUI iPhone and iPad shell. Physical device for BLE and camera Wi-Fi. TestFlight is the public beta.
---

The production iOS app is a universal iPhone and iPad SwiftUI shell in
`ios/OpenPocketCine/`. It is the operator-proven datalink. Generate the Xcode
project with XcodeGen — see [Setup](../guides/setup/).

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
- Camera writes (record, ISO, EV, zoom, gimbal on Pocket). Zoom chips follow
  the body (Pocket 4 Pro 1×/3×/6×/12×; Pocket 4 1×/2×/4×; Pocket 3 1×/2×/4×
  with 4K max 2×; Nano 1×). Zoom must not drop the live picture. FORMAT lists
  `camcap_video_format` pairs (2.7K / 4:3 / 1:1 / 9:16 when the body
  advertises them; aspect is the res byte). A tap stays on that pair until
  the body reports it. Pocket 3 normal Video also has a
  [documented fallback](https://openpocketcine.app/docs/protocol/commands/#pocket-3-format-choices-without-a-capability-table)
  when the camera supplies no capability table; reported choices take priority.
  This does not establish support for those pairs in SlowMo or other modes.
  COLOR follows the body: D-Log2 is Pocket 4 Pro only; Pocket 4 is D-Log;
  Pocket 3 is D-Log M (HLG is HDR); Nano is 8-bit / 10-bit / D-Log M.
  Auto ISO ranges start at 50 on Pocket 3 / Pocket 4 and 100 on Pocket 4 Pro.
  View Assist **ND** is a small chip on the live picture (bottom-left,
  above the assist bar; hold-drag to move). Long-press to switch Stops,
  ND32, or ND 0.3. It meters against middle gray and suggests a screw-on
  ND to balance the frame. The app cannot set a filter.
  The gimbal stick
  and zoom chip sit together as a cluster in the trailing-bottom of the
  picture — the same on iPhone and iPad, portrait and landscape. A
  gimbal-controls button sits beside zoom (Pocket only). That sheet parks
  like a capture picker and sets Follow / Tilt locked / FPV, Slow /
  Default / Fast, stick ramp, and a Motion Control A→B (optional C) take
  (set A and B, choose each leg’s duration; hold and drag
  anywhere on the editor). With C set, Smoothness rounds the corner near B and shows a dashed curve.
  Zero hits B exactly; higher values bypass B while preserving A/C and total
  duration. There is no artificial speed cap. Moves are experimental: keep the camera fixed, rehearse,
  and check framing before a take. Programmed and head-tracking tilt targets
  stay within −44° to +70°. A missed timed point stops the move;
  professional positional/timing accuracy has not been qualified. Stick
  throw is analog with an ease-in curve (small push crawls; full throw is
  fastest). Off / Soft / Medium ramp eases the throw over time. Head tracking is experimental (Operator Setup → Controls,
  off by default). With AirPods that report motion, Calibrate Head Lock —
  centered above the bottom bars — is shared forward: that head pose and
  that gimbal pose are zero. A head turn pans the Pocket; a nod tilts.
  The gimbal follows that direction using direct angle targets. Roll is shown,
  not driven. STOP clears the lock. Manual controls and Motion Control takes take
  priority; lost head motion pauses tracking. Responsiveness remains experimental. A connected game controller's left stick drives the same path.
  Cross/A records. Circle/B recenters. Square/X is rotate-180. Triangle/Y
  tracks a face in frame or cancels. L1/R1 jump zoom out/in. L2/R2
  hold-to-zoom (deeper is faster). D-pad up/down ISO, left/right shutter.
  A toast says Gamepad connected or disconnected; unplug rests the
  stick. Operator Setup → Controls → Gamepad shows Connected / Not
  connected. A gimbal stop pulses only after the head moves then stalls
  (Haptics setting). Stick
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
  the original when you open a clip. LUT bake on export can include the
  LUT exposure pull (Bake exposure under Bake LUT; on by default).
  Convert log (off by default, exclusive with Bake LUT) offers an **Output
  curve** choice: D-Log or D-Log2 for the whole selection. Clips already on
  that curve keep their pixels; other log clips are converted and tagged with
  the destination curve. This is a technical transform, not a look.
  Camera originals stay untouched. Rec.709 stays Bake LUT; D-Log M is not converted.
- Optional Frame.io upload when you add your own Adobe keys (Platform API v4)
- **Share this feed** (Operator Setup → Sharing): this iPhone re-serves live view to other OpenPocketCine iPhones and iPads on the **same camera Wi-Fi**. On the host, tap **Show Wi-Fi code**. Scan it with Camera on the watching device and accept **Join Network**, then return to OpenPocketCine → **Watch a feed** and select the host. You can also join that Wi-Fi in Settings. Only the host connects to the camera inside the app. The watcher has local view assists and scopes, camera readings, REC tally, and **Clean view**. **Request control** asks the host for permission to record, focus, and change supported ISO/shutter/zoom settings; **Release** gives it back. Brief interruptions hold the last picture and automatically retry three times. If sharing ends or reconnection fails, the watcher keeps the error visible; tap **Choose a feed** to rejoin. The QR code contains the Wi-Fi password; show it only to people you want on that network. An optional watcher passcode controls access to the feed separately. The host shares one encode, and a slow watcher waits for a fresh keyframe while others continue. Peer-to-peer discovery and streaming are disabled because they caused severe stuttering during physical testing. One iPad watcher was reported smooth after joining the same Wi-Fi; multiple watchers still need physical verification. Android Sharing is not in this build.

The final watcher QR onboarding, passcode and recovery changes still need
dedicated physical acceptance. The earlier one-iPad smoothness report does not
qualify those newer flows or multiple wireless watchers. See the
[watcher relay evidence](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/watcher-relay.md).

**Multiview** is an experimental iPhone/iPad stage for several cameras on shared
Wi-Fi. From **Your cameras**, tap the grid icon to set up the network and add
cameras. Each camera has its own preview and recording controls; Record all
requests recording together without frame-accurate synchronization. See the
[Multiview guide](https://openpocketcine.app/docs/guides/multiview-prototype/) for supported observations,
setup, saved stages and remaining physical checks. Pocket 3, Pocket 4 Pro and
Nano preview and recording have been checked together on iPhone. Pocket 3
recovery after an app switch required a full rejoin and roughly a minute in the
recorded test. Android Multiview remains unavailable.

Motion Control durations use half-second dials up to 120 seconds. Swipe left
to increase duration and right to decrease it. Move the expanded
window by holding anywhere, or drag the minimized pill directly. Dragging
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
change `Sources/`, `ios/`, or `Package.swift` update
`ios/TestFlight/WhatToTest.en-US.txt` for operators. See
[`docs/testflight-ci.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/testflight-ci.md).

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
