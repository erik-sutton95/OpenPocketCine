---
title: Architecture
description: Portable Swift protocol core with a SwiftUI iOS shell and a Jetpack Compose Android shell.
---

OpenPocketCine is a shared Swift business/protocol core with native platform
shells. Policy lives in Swift; sockets, BLE, SoftAP join, rendering, and UI
live in the shells.

| Layer | Path | Role |
| --- | --- | --- |
| Shared core | `Sources/OpenPocketViewCore/` | DUML, commands, status, LUTs, layout policy. Foundation only — **portable**. |
| Presentation | `Sources/MonitorPresentation/` | Foundation-only capability values, native layout and selection policies. No camera I/O. |
| Shared iOS UI | `Sources/MonitorUI/` | Sora/theme, canvas, pages, catalog, controls and inspectors with injected values/actions/native rendering slots. |
| Shared Android UI | `Apps/Android/monitor-ui/` | Compose design language, capability values, layout policy and page scaffolds. |
| iOS app | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, Hotspot Configuration, VideoToolbox/Metal. |
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
feed host. Transport state machines, decoders, scope processing and delivery
still have their existing owners; their later extraction is described in the
[shared monitor engine plan](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/SHARED-MONITOR-ENGINE.md).

Operator-visible behavior must match across iOS and Android unless
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md)
lists an exception. Live UDP/decoder facts:
[`docs/live-session.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/live-session.md).
The full seam table:
[`docs/ARCHITECTURE.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/ARCHITECTURE.md).

Wire format is in [Protocol](../protocol/connection/).
