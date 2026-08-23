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
| iOS app | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, Hotspot Configuration, VideoToolbox/Metal. |
| Android app | `Apps/Android/app/` | Jetpack Compose shell, Vulkan/GLES live picture, MediaCodec. |
| Android facade | `Sources/OpenPocketCineAndroidFacade/` | JNI session boundary. Android does not SPM-link the core at runtime. |
| Tests | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core. |

Both apps must call the same state machines (`CameraSoftAP`, `FeedWatchdog`,
`SessionRecovery`, `CameraSetMailbox`). Do not clone that ladder in Kotlin.

HUD glyphs are vendored Lucide SVGs (`OpcIcon` on both shells).

Operator-visible behavior must match across iOS and Android unless
[`docs/PARITY.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/PARITY.md)
lists an exception. Live UDP/decoder facts:
[`docs/live-session.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/live-session.md).
The full seam table:
[`docs/ARCHITECTURE.md`](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/ARCHITECTURE.md).

Wire format is in [Protocol](../protocol/connection/).
