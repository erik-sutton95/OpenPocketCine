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

**Enable-once**:
`0x09/0xa8` starts live view and is the only PLI; it is not a 1 Hz keyframe loop.
_Avoid_: IDR loop, live-start (alone)

**Watchdog**:
Portable stall-and-recover policy (`FeedWatchdog`).
_Avoid_: keepalive, heartbeat

**Chrome**:
Operator HUD around the picture (bars, chips, DISP), not the picture.
_Avoid_: UI, overlay

**Gimbal cluster**:
Stick, zoom chip, and (later) gimbal controls (follow / speed / A·B·C) as one
trailing-bottom parking spot in every orientation. Zoom stacks above the stick.
Controls grow leading of the stick without moving it.
_Avoid_: joystick pack, gimbal HUD

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
opcode, other pids). Replies are datalink pktType `0x03` — same command
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

**LUT exposure compensation**:
Input-referred stops applied before the Rec.709 cube (half-stop −3…+3). Pull after ETTR so the cube's mid-grey lands. Not camera EV. iOS Share **Bake exposure** writes that pull into the file.
_Avoid_: LUT gain, LUT mix, intensity, EV (the body SET)

**Clip color profile**:
Shot color in QuickTime Keys `com.dji.camera.ColorGammaSxS` (`Rec.709` / `Rec.2100 HLG` / `D-Log` / `D-Log2`) on the original take. LRF/XRF proxies are Rec.709 even for log. Playback Auto reads the original (or its `moov` tail) and stores it with the cached clip; `colr`/`nclx` is Rec.709 even for log.
_Avoid_: nclx (alone), color space box

**Proxy**:
720p LRF/XRF sidecar on the phone without the original camera file. Tagged **Proxy** in the library and playback chrome.
_Avoid_: preview (alone), low-res

**Full Resolution Caching**:
Storage switch (on by default). On, opening a clip also downloads the original camera file. Off keeps only the proxy.
_Avoid_: RAW cache, 4K always (the setting name is Full Resolution Caching)

**Physical**:
Proof on a real phone. Simulator cannot exercise BLE or camera Wi-Fi.
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
