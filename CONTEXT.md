# OpenPocketCine

Shared language for the Osmo field-monitor domain. Implementation lives in the
code and in `docs/`; this file is the glossary only.

## Language

**Core**:
The portable Swift protocol and business-logic package (`OpenPocketViewCore`).
_Avoid_: SDK, engine, shared module

**Shell**:
The platform app that owns I/O and UI: SwiftUI on iOS, Compose on Android.
_Avoid_: client, frontend, app layer

**Facade**:
The Android JNI session boundary (`OpenPocketCineAndroidFacade`).
_Avoid_: bridge, wrapper

**Spine**:
Required connection order: BLE → SoftAP → UDP datalink → live view.
_Avoid_: pipeline, stack

**SoftAP**:
The camera’s Wi-Fi access point at `192.168.2.1`.
_Avoid_: hotspot (except when naming the iOS API)

**Datalink**:
UDP port 9004 DUML transport between phone and camera.
_Avoid_: media port, stream

**One client**:
Live HEVC/AVC on the camera SoftAP is unicast UDP to one phone 5-tuple.
Camera multicast is won't-do.
_Avoid_: camera multicast, NDI (as this path), SRT (as this path)

**Host**:
The phone that holds the Pocket datalink and may advertise the watcher relay.
_Avoid_: broadcaster (in operator copy)

**Watcher**:
Another OpenPocketCine install on the same camera Wi-Fi that joins the host’s
shared feed. Does not open its own camera session.
_Avoid_: client, viewer (in operator copy)

**Watcher relay**:
Phone-as-encoder second-screen. Bonjour `_opc-mon._tcp`, iOS host + iOS watcher.
The host shares its camera picture with watchers on the same camera Wi-Fi.
_Avoid_: camera multicast, NDI, SRT, monitor relay

**Enable-once**:
`0x09/0xa8` starts live view and is the only PLI; it is not a 1 Hz keyframe loop.
_Avoid_: IDR loop, live-start (alone)

**Watchdog**:
Portable stall-and-recover policy (`FeedWatchdog`). Production repair for live UDP.
_Avoid_: keepalive, heartbeat

**Repair owner**:
The one production policy that maps a classified live-link failure to a
single repair. `FeedWatchdog` acts today. `LinkDiagnoser` classifies and is
logged (`feed: observe`) but is not wired to repair.
_Avoid_: dual watchdog, diagnoser (alone)

**ACK window**:
Three independent camera send windows in pktType `0x04`: video `0x02`,
ackedData `0x03` (command replies, including Flip GET), extra from `0x01`.
Stale group 1 stops GET/SET while HEVC continues.
_Avoid_: ACK (alone) when you mean a DUML command ACK

**Chrome**:
Operator HUD around the picture (bars, chips, DISP), not the picture.
_Avoid_: UI, overlay

**Gimbal cluster**:
Stick, zoom chip, and gimbal-controls button as one trailing-bottom parking
spot in every orientation. Zoom stacks above the stick. The button sits
leading of zoom (same size). Follow / speed / ramp / A·B·C live in the
button's sheet, not leading of the stick.
_Avoid_: joystick pack, gimbal HUD

**Gimbal pad**:
Connected extended gamepad (discussion #159). Left stick is the gimbal
stick (same expo throw and picture-relative invert as the on-screen stick).
Cross/A records (skips the rec-confirmation sheet). Circle/B recenters.
Square/X is rotate-180. Triangle/Y tracks a face in frame or cancels.
L1/R1 jump the zoom chip (out does not wrap to tele). L2/R2 hold-to-zoom
(deeper trigger is faster). D-pad up/down ISO, left/right shutter
(left opens / slower, right closes / faster). Toast Gamepad
connected/disconnected. Unplug rests the stick and zoom. On-screen stick
wins while held. Controls **Gamepad** row shows Connected / Not connected.
Limit haptic fires only after that axis moves, then stalls at a stop.
_Avoid_: DualSense (alone) in operator copy

**Motion Control**:
A repeatable pan/tilt take through A→B and optional C with a chosen duration
for each leg. Preparation at A is outside the take. At zero **Smoothness**,
B is an exact target; above zero a timed Bézier fillet rounds near B, preserving
A/C and total duration. The dashed curve is a preview, not a tracking box.
A failed required checkpoint invalidates the take. Physical accuracy remains experimental.
_Avoid_: Programmed move, camera-native path, guaranteed precision

**Gimbal lock (all axes)**:
Latched joystick-hold. No captured opcode. The Locked chip toasts and does
not SET. Distinct from Tilt locked (param `04`).
_Avoid_: treating Locked as Tilt locked

**Head tracking**:
iOS-only AirPods IMU (`CMHeadphoneMotionManager`). Controls **Head
Tracking (Experimental)**, off by default. **Calibrate Head Lock** captures
shared forward: a still head quaternion and a fresh camera-native pose.
Look uses nose azimuth/elevation (`HeadTrack.look`), not Euler differences.
`HeadTrackNative` maps that look to native timed-angle targets, with a
100 ms command horizon. Neither native path has an artificial speed ceiling.
Pitch uses the captured native attitude `@0`; display look-up remains `−@20`.
Clamp the body-relative reach before mapping pitch into native coordinates.
Roll is readout only. STOP clears Head Lock. Manual control, programmed moves
and inactive scenes suspend head driving. Samples expire by measurement age;
old stream callbacks cannot regain control. Android has no AirPods IMU.
See [head tracking](docs/head-tracking.md) for transport and qualification.
_Avoid_: spatial audio in operator copy

**Triple-tap 180 (TT180)**:
Mechanical 180 via `FE 09` (app rotate-180 button or Pocket joystick
triple-press). Invert pan when that 180 settles (~165° / ~15°), not at
the 90° midpoint. Extra-mirror live HEVC when TT180 and Selfie Flip is
off (Mimo). Joystick yaw to 180 is not TT180. Reconnect-at-180 seeds
TT180 from settled attitude; a 0° stub does not lock front. MIRROR
assist XORs.
_Avoid_: true selfie, selfie mode (alone), Mimo selfie toggle

**Selfie Flip**:
Pocket body Control Center. `0x02/0x8E` pid `0x0038` GET ~1 Hz (`00`
off / `01` on). No app SET. Off: encoder is mirrored — extra-mirror at
TT180. On: encoder is true-to-scene — skip extra-mirror. Extra-mirror
holds the last picture ~3 frames before X-flipping (no in-place swap).
File follows Flip; Mimo live stays readable. GET is untracked on the live
UDP ACK pump (~1 Hz) and must not complete audio / glamour `0x8E` waiters (same
opcode, other pids). Keepalive BLE GET when UDP replies go stale (≥2 s).
Replies are datalink pktType `0x03` — same command
window as record/stop, zoom ACK, and every other GET/SET. The 40 Hz window
ACK must echo that seq in group 1 (not handshake `baseSeq`) or the
command downlink goes stale while HEVC keeps moving.
_Avoid_: treating Flip as HEVC SEI / BLE GATT

**Parity**:
Operator-visible match to the iOS baseline unless `docs/PARITY.md` lists an exception.
_Avoid_: pixel-identical, 1:1 clone

**Assist**:
A monitor tool on the picture (LUT, peaking, zebra, scopes, grids).
_Avoid_: filter, effect

**ND suggestion**:
View-assist HUD chip on the live picture (toolbar **ND**, next to LIGHTS). Parks bottom-left above the assist bar; hold-drag to move. Long-press **Units** switches Stops (`+5.0`), filter factor (`ND32`), and optical density (`ND 0.3` / `ND 0.4`). Reads luma vs middle gray. Not a camera SET. Off unless the operator turns the chip on.
_Avoid_: auto ND, ND SET, shutter-sheet nag

**LUT exposure compensation**:
Input-referred stops applied before the Rec.709 cube (half-stop −3…+3). Pull after ETTR so the cube's mid-grey lands. Not camera EV. iOS Share **Bake exposure** writes that pull into the file.
_Avoid_: LUT gain, LUT mix, intensity, EV (the body SET)

**Clip color profile**:
Shot color in QuickTime Keys `com.dji.camera.ColorGammaSxS` (`Rec.709` / `Rec.2100 HLG` / `D-Log` / `D-Log2`) on the original take. LRF/XRF proxies are Rec.709 even for log. Playback Auto reads the original (or its `moov` tail) and stores it with the cached clip; `colr`/`nclx` is Rec.709 even for log.
_Avoid_: nclx (alone), color space box

**Log color transform**:
Technical D-Log ↔ D-Log2 convert on iOS Share (**Convert log**, off by default). Decode source log, D-Gamut ↔ D-Gamut2 through Rec.709 linear, encode dest log. Not a look LUT. Exclusive with Bake LUT. Camera original is untouched. Rec.709 display stays Bake LUT. D-Log M is out.
_Avoid_: CST (alone) in operator copy, ACES, Rec.709 CST

**Proxy**:
720p LRF/XRF sidecar on the phone without the original camera file. Tagged **Proxy** in the library and playback chrome.
_Avoid_: preview (alone), low-res

**Full Resolution Caching**:
Storage switch (on by default). On, opening a clip also downloads the original camera file. Off keeps only the proxy.
_Avoid_: RAW cache, 4K always (the setting name is Full Resolution Caching)

**Frame.io upload**:
Optional iOS clip upload through the Frame.io Platform API (v4) with Adobe IMS
user OAuth (PKCE). Bring-your-own Adobe Native App keys. Not an Adobe
integrator program.
_Avoid_: Camera to Cloud, C2C, camera-to-cloud, Camera-to-Cloud

**Watch companion**:
Apple Watch remote over WatchConnectivity. The iPhone stays the radio.
Preview, rec, timecode, storage. Not the link-health “Watch” band (50–79).
_Avoid_: Watch (alone) for the wrist app; Wear (that is Android)

**Physical**:
Proof on a real phone. Simulator cannot exercise BLE or camera Wi-Fi.
Watch companion proof is a physical Apple Watch plus iPhone on Pocket SoftAP.
_Avoid_: on-device (prefer **physical**)

**Hygiene**:
Secrets, captures, unofficial LUTs, and PII stay out of git.
_Avoid_: cleanliness

**Portable**:
Foundation-only core: no SwiftUI, UIKit, Android, Compose, or filesystem I/O.
_Avoid_: cross-platform, shared

**Budget**:
A living SLO for the live path (frame rate, ACK, HUD Hz, scope tap).
_Avoid_: perf tweak, optimization (alone)

**FTUE**:
The first-run pairing wizard: BLE → approve → SoftAP → live picture.
_Avoid_: onboarding, tutorial, splash (the splash is not the wizard)

**Closed testing**:
Google Play track for the Android waitlist (`alpha`). Email list, opt-in URL,
Play-delivered updates. Internal testing is the 100-tester smoke track, not the
waitlist.
_Avoid_: TestFlight (for Android), Firebase App Distribution, open testing (until we mean that)
