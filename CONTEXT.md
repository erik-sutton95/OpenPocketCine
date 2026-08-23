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

**Parity**:
Operator-visible match to the iOS baseline unless `docs/PARITY.md` lists an exception.
_Avoid_: pixel-identical, 1:1 clone

**Assist**:
A monitor tool on the picture (LUT, peaking, zebra, scopes, grids).
_Avoid_: filter, effect

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
