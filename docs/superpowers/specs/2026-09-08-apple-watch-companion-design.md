# Apple Watch companion

**Date:** 2026-09-08
**Status:** approved in session (discussion #68, issue #101)
**Slice:** iOS watchOS companion (Wear OS later)

Wrist remote in the spirit of OpenZCine: live JPEG/HEIC preview, timecode, storage,
record/shutter. The iPhone stays the radio. The watch never joins SoftAP.

## Goal

A Watch app on the same TestFlight family can start/stop rec and show the live
preview, timecode, storage, and camera battery while the iPhone is on Pocket
SoftAP.

## Locked decisions

- JPEG/HEIC preview (OpenZCine frame pump), not tally-only.
- Watch rec fires immediately (same as gamepad Cross/A). Phone Record
  Confirmation still applies to the on-screen lamp only.
- OpenZCine chrome: timecode, 16:9 well, storage · rec/shutter · camera battery.
  Storage string matches the phone HUD (`N GB · P%`, remaining `N Min` fallback).
- No phone battery, no complication, no Wear OS, no Digital Crown gimbal, no
  watch SoftAP / camera BLE.
- Portable envelope in `OpenPocketViewCore`. `WCSession` + `UIImage` in the
  iOS shell. `ios/OpenPocketCineWatch` via XcodeGen.

## Architecture

| Layer | Path | Owns |
| --- | --- | --- |
| Protocol | `Sources/OpenPocketViewCore/WatchRelayProtocol.swift` | Envelope + Codable state/frame/command/result. Foundation. `watchOS(.v10)` on the package. |
| iPhone relay | `ios/OpenPocketCine/WatchRelay.swift` | `WCSession`, JPEG encode, drop-stale pump, rec/shutter callbacks. |
| Wrist app | `ios/OpenPocketCineWatch/` | SwiftUI monitor + `WatchSessionController`. Embedded in the iPhone app. |

Spine unchanged. WatchConnectivity is BLE-to-watch, independent of camera Wi-Fi.

## Protocol

`WCSession.sendMessageData`: `[kind: UInt8] + JSON`.

| Kind | Direction | Payload |
| --- | --- | --- |
| `0x01` state | phone → watch | `WatchRelayState` |
| `0x02` frame | phone → watch | `WatchRelayFrame` |
| `0x10` command | watch → phone | `WatchRelayCommand` |
| `0x11` result | phone → watch | `WatchCommandResult` |

State (Pocket-shaped): `isRecording`, `isPhotography`, `timecode` (HUD clock),
`media` (storage slot), `cameraBatteryPercent` (`-1` unknown), `cameraName`,
`connection` (`.connected` iff `ConnectionPhase.live`, else `.noCamera`),
`feedLive`, `feedAspectRatio` (16/9). Coalesce with
`matchesIgnoringLiveReadouts` (skip `timecode`).

Frame: JPEG image bytes in wire field `jpeg` + timecode +
`isRecording`.

Commands: `toggleRecord`, `capture`, `resume` (watch wake).

Result: `accepted`, `isRecording`, `error` — operator copy, no opcodes.

## Phone relay

`AppModel` owns one `WatchRelay`, activated at launch. Frames after a successful
live present only — `HevcDecoder.onWatchPreview` image/buffer, downscaled off the
present thread. Never a second decoder, never another `0x09/0xa8`. Drop-stale,
ack-paced, max 3 in flight. Adaptive width 320 / 416 / 512 from RTT. Old encode/ACK work retains its
reservation across wake/resume and cannot dispatch into a new generation.
The installed paired companion requests the existing VT decoder before the
first format; AF-S and assists-off still supply preview pixels. Wrist sleep
does not change decoder ownership. Thumbnails follow the committed picture flip.

Watch rec/shutter calls `CameraSession.pressShutter()` and skips the confirmation
sheet. Reject when not live, photo/video mismatch, or `controlBusy`.

## Watch UI

Stacked bars, not overlays: timecode (red while rec) · 16:9 well with rec stroke
· storage · rec/shutter · camera 5-bar gauge. Crown zooms the preview 1×–4×;
drag pans while zoomed. Placeholders: open the iPhone app / no camera / waiting
for live view.

## Project / CI

- XcodeGen `OpenPocketCineWatch`, bundle `com.opencapture.openpocketcine.watch`.
- Companion ID `com.opencapture.openpocketcine`. Same `Version.xcconfig`.
- Dependent watch app (`WKRunsIndependentlyOfCompanionApp` false).
- `just watch-build`; `just native-check` includes it.
- Embed the watch app in `Watch/` (XcodeGen Embed Watch Content). The iPhone
  Watch app only lists companions from that folder, not `PlugIns/`.
- PARITY exception: iOS-only. Wear later.

## Out of scope

Watch joining `192.168.2.1`. Independent camera BLE. Digital Crown gimbal.
Complication. Phone battery on the wrist. Wear OS.

## Verify

Core tests for the envelope and storage label. `just native-check` (includes
watchOS Simulator build). Operator-visible proof: physical Apple Watch, iPhone,
and Pocket while the phone is on SoftAP.
