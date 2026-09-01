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
| Stall, GOP-reset grace, AF-C grace, zoom grace, enable-once, rebuild ladder | `FeedWatchdog` | iOS `CameraSession.applyFeedWatchdog`; Android JNI `feedWatchdogCreate/Tick` — not a second Kotlin clone. `LinkDiagnoser` is observe-only (`feed: observe`) until [`connection-reliability.md`](connection-reliability.md) classifies #148. |
| Present hygiene (skip-dup, freeze ≠ flush, drawable gate, one enable) | `FeedPresentPolicy` | iOS `CIFeedView` / `PlaybackFeedSession`; Android `LiveFeedEffectsSession` (Kotlin lockstep + tests) |
| Clip shot color (`ColorGammaSxS`) | `ClipColorProfile` | iOS `ClipColorProfileIO`; Android `ClipColorProfile.kt` (Kotlin lockstep). Original take only — LRF/XRF is Rec.709 even for log. Shells read the `moov` tail (2 MiB Range when the 4K file is not cached) and store it in the media cache `color.json`. |
| Gimbal cluster (stick + zoom + reserved controls) | `GimbalCluster` | iOS `LiveMonitorLayout` / portrait chrome; Android `GimbalCluster.kt` lockstep. |
| Screen-relative gimbal stick | `GimbalStickMapping` (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs). Expo analog throw after deadzone (`GimbalStick.analogCurve`). Stick notify `0x04/0x01` at 25 Hz on the UDP ACK queue (`GimbalStick.streamInterval`); not MainActor `sendUntracked`. | iOS `DatalinkDriver.tickGimbalStick`; Android `DatalinkDriver.tickGimbalStick` on the ACK thread (`noteGimbalStick` / `restGimbalStick`) |
| Gimbal limit pulse | `GimbalLimitWatch` (stall ~300 ms after motion grace; skip pan during `FE 09` settle; rising-edge only) | iOS `CameraSession` + `GimbalGamepadBridge`; Android `PocketCameraSession` + `GimbalGamepadDriver` |
| Gamepad operator map | `GamepadOperator` (discussion #159: A record, B recenter, X 180, Y track, L1/R1 zoom chip, D-pad ISO/shutter). L2/R2 analog zoom is shell. | iOS `GimbalGamepadBridge` (`GCController`); Android `GimbalGamepadDriver` (`KeyEvent` / hat / `InputManager`) |
| AirPods look-at gimbal | `HeadTrack` (SET-relative nose look; throw until live `0x04/0x05` matches) | iOS `HeadphoneMotionBridge`. Roll readout only. Android: no IMU — PARITY exception. |
| Drop storm, bounded reconnect | `SessionRecovery` | platform BLE rescan + SoftAP rejoin |
| Link score → 0–4 bars | `CameraLinkHealth` + `LinkSignalBars` | top-bar FPS chip (delivery health, not RSSI) |
| Camera SET mailbox, retransmit, settle | `CameraSetMailbox` | iOS `fireCamera`; Android JNI |

Platform shells own sockets, BLE, SoftAP join, permissions, lifecycle, rendering,
storage, and UI. Do not import SwiftUI, UIKit, Android, or Compose into the core.

See [`live-session.md`](live-session.md), [`feed-watchdog.md`](feed-watchdog.md),
[`connection-reliability.md`](connection-reliability.md),
[`PARITY.md`](PARITY.md), [`PERFORMANCE.md`](PERFORMANCE.md), [`UX.md`](UX.md),
and [`ANDROID.md`](../ANDROID.md).

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
