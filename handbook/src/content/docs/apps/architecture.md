---
title: Architecture
description: Portable Swift protocol core with a SwiftUI iOS shell and a Jetpack Compose Android shell.
---

OpenPocketCine is a shared Swift business/protocol core with native platform
shells. Portable policy lives in OpenCine; its DJI Apple target owns iOS Bluetooth,
Wi-Fi and datalink adapters. Apps compose those owners with native rendering and UI.

| Layer | Path | Role |
| --- | --- | --- |
| Shared core | `Sources/OpenPocketViewCore/` | DUML, commands, status, LUTs, layout policy. Foundation only — **portable**. |
| Presentation | OpenCine `MonitorPresentation` | Foundation-only capability values, native layout and selection policies. No camera I/O. |
| Shared iOS UI | OpenCine `MonitorUI` | Sora/theme, canvas, pages, catalog, controls and inspectors with injected values/actions/native rendering slots. |
| Shared Android UI | OpenCine `Android/monitor-ui/` | Compose design language, capability values, layout policy and page scaffolds. |
| DJI Apple transport | OpenCine `OpenCineDJIApple` | Bluetooth/network delivery and control transactions; injected host policy and diagnostics, no UI or storage ownership. |
| Apple picture runtime | OpenCine `OpenCineApple` | Decoder, native assists, source publications and retained picture presentation with configured source calibration and diagnostics. |
| iOS app | `ios/OpenPocketCine/` | SwiftUI composition, credential/permission policy and native picture adapters. |
| Watch companion | `ios/OpenPocketCineWatch/` | watchOS remote over WatchConnectivity. Phone stays the radio. |
| Android app | `Apps/Android/app/` | Jetpack Compose shell, Vulkan/GLES live picture, MediaCodec. |
| Android facade | `Sources/OpenPocketCineAndroidFacade/` | JNI session boundary. Android does not SPM-link the core at runtime. |
| Tests | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core. |

Both apps must call the same state machines (`CameraSoftAP`, `FeedWatchdog`,
`SessionRecovery`, `CameraSetMailbox`, `CameraWifiResolution`). Android reaches
those through JNI (`cameraSoftAPDecision`, `feedWatchdogTick`) or a Kotlin
lockstep (`CameraWifiResolution`). Do not clone the SoftAP / watchdog ladder
in Kotlin.

HUD glyphs use vendored Lucide SVGs (`OpcIcon` on both shells), with the design’s
custom View Assist artwork preserved in a shared catalog. Typography is Sora.
Brand adapters translate the current camera into presentation values and capabilities.
Opening pages, changing display mode, and rotating the device retain the native
feed host. The Apple control exchange owns reply and SET lifetime while the app retains
presentation pins and session recovery decisions. Common receipt confirmation requires
camera reports. Live decoder and playback publications own separate source leases:
closing an old source cannot clear its successor or calibrate a covered clip.
The app supplies the measured DJI profile and actual camera reports; the shared
native owner retains decode and presentation lifetime. Connection/recovery and
continuous DJI gesture migration remain unfinished. Remaining native/session extraction is described in the
[shared monitor engine plan](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/SHARED-MONITOR-ENGINE.md).

Operator-visible behavior must match across iOS and Android unless
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md)
lists an exception. Live UDP/decoder facts:
[`docs/live-session.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/live-session.md).
The full seam table:
[`docs/ARCHITECTURE.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/ARCHITECTURE.md).

Wire format is in [Protocol](../../protocol/connection/).

The iOS DJI integration also owns each connection's registration heartbeat and camera-path
grace. The app composes picture, gallery and motion maintenance without duplicating the
timer; inactive scenes and covered monitors keep registration. This extraction retains
the existing recovery timing and does not complete the remaining session migration.

Negotiated-picture recovery also uses one per-session DJI Apple owner. It serializes
endpoint repair and current media return, keeps the existing picture deadline and
rejects stale completions after a replacement. A media transition retires picture intent
without canceling admitted endpoint negotiation. Native picture actions and the full
connection/recovery policy remain app adapters; no camera command or portable policy
changes in this Apple-only ownership move. Physical camera qualification remains pending.

Clip playback also uses the shared Apple video-output, assist and audio-meter
owners. Pocket supplies its source calibration, HDR preference and audio-session
policy. An unmeasured audio source remains unavailable rather than appearing as
silent measurements. The portable conform-preview policy comes from shared
Media. Automated consumer and simulated native playback checks pass; physical
device qualification remains pending. The gallery, player workflow and delivery
are still app-owned parts of the shared-shell migration.

Native clip export also uses the shared Apple exporter. Pocket retains output
filenames, its exports folder, clip metadata and DJI shot-color policy. The
shared owner supplies copy, transcode, LUT processing and progress. Physical
export and Share qualification remain pending.
