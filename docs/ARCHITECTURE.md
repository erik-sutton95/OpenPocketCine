# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML framing, datalink, BLE advert decode, commands, status, LUTs, layout policy. Pure Foundation — no SwiftUI, UIKit, Android, or I/O. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI shell, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal |
| **Android app** | `Apps/Android/app/` | Jetpack Compose phone shell and Android platform adapters |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core |

The iOS Xcode project is generated: `cd ios && xcodegen generate`.

## Connection spine

1. BLE scan and pair (GATT).
2. Read camera Wi-Fi credentials.
3. Join the camera SoftAP via Hotspot Configuration.
4. UDP DUML datalink on the camera LAN (typically `192.168.2.1`).
5. Enable live view (`0x09/0xa8`); media packets on UDP 9004 (`pktType 0x02`).
6. Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p.

Platform shells own sockets, permissions, lifecycle, rendering, storage, and UI. Keep that
boundary: do not import SwiftUI into the core.

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
