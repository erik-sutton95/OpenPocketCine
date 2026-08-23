# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML, commands, status, LUTs, layout policy. **Portable** Foundation. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI **shell**, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal. Teardown: [live-session](live-session.md). |
| **Android app** | `Apps/Android/app/` | Compose **shell**. Live picture and HUD I/O: [`ANDROID.md`](../ANDROID.md). Operator-visible behavior: [parity](PARITY.md). Teardown: [live-session](live-session.md). |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core |

HUD glyphs that both shells share are vendored Lucide SVGs (`OpcIcon` on iOS and Android).
Regenerate Android VectorDrawables with `python3 scripts/vendor-lucide-icons.py`. Do not add a JS
runtime. Custom keepers: zebra stripes, the Frame.io F mark, and the battery outline pill.
SF Symbols / Material stay only on controls this catalog has not replaced yet.

The iOS Xcode project is generated: `cd ios && xcodegen generate`.

## Connection spine

1. BLE scan and pair (GATT FFF0).
2. Read camera Wi-Fi credentials.
3. Join SoftAP `192.168.2.1`. On-path only after DHCP `192.168.2.2…254`
   (`CameraSoftAP.isAssociatedIPv4`).
4. UDP DUML to `192.168.2.1:9004` on an **ephemeral local port**. Camera 9004 is
   the remote only. Bind and ACK details: [live-session](live-session.md).
5. Enable live view **enable-once** after path + display are ready. Arm pktType
   `0x02` ingest on that write. Recover policy: [watchdog](feed-watchdog.md).
6. Pocket 4 / 4 Pro: HEVC 720p. Nano: AVC/H.264 High 720p. Decoder setup and
   NAL latch: [live-session](live-session.md).

### Policy in Swift, I/O in the shells

Business/protocol logic lives in `Sources/OpenPocketViewCore/` (the Swift-for-Android
SDK). Both apps must call the same state machines:

| Policy | Core type | Shell I/O |
| --- | --- | --- |
| SoftAP addressing, path-ready, handshake rebind, foreground recover | `CameraSoftAP` | iOS `WiFiJoiner` / `NEHotspotConfiguration`; Android `CameraApJoiner` / `WifiNetworkSpecifier` |
| Stall, GOP-reset grace, AF-C grace, enable-once, rebuild ladder | `FeedWatchdog` | iOS `CameraSession.applyFeedWatchdog`; Android JNI `feedWatchdogCreate/Tick` — not a second Kotlin clone |
| Drop storm, bounded reconnect | `SessionRecovery` | platform BLE rescan + SoftAP rejoin |
| Link score → 0–4 bars | `CameraLinkHealth` + `LinkSignalBars` | top-bar FPS chip (delivery health, not RSSI) |
| Camera SET mailbox, retransmit, settle | `CameraSetMailbox` | iOS `fireCamera`; Android JNI |

Platform shells own sockets, BLE, SoftAP join, permissions, lifecycle, rendering,
storage, and UI. Do not import SwiftUI, UIKit, Android, or Compose into the core.

See [`live-session.md`](live-session.md), [`feed-watchdog.md`](feed-watchdog.md),
[`PARITY.md`](PARITY.md), and [`ANDROID.md`](../ANDROID.md).

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
