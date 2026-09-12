# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Monitor presentation policy** | `Sources/MonitorPresentation/` | Foundation-only viewport geometry, capability gates and camera/media presentation values. No camera protocol or platform I/O. |
| **Shared native monitor UI** | `Sources/MonitorUI/` | SwiftUI pages, controls, navigation, camera home/pairing and media catalog presentation; bundled Sora resources. Camera state and actions are injected. iOS-only implementation, separate from the portable core. |
| **Shared native Android UI** | `Apps/Android/monitor-ui/` | Compose pages, controls, typography and icon assets. Camera state and actions are injected; no JNI or camera ownership. |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML, commands, status, LUTs, layout policy. **Portable** Foundation. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI **shell**, CoreBluetooth, NEHotspotConfiguration, sockets, VideoToolbox/Metal. Teardown: [live-session](live-session.md). |
| **Watch companion** | `ios/OpenPocketCineWatch/` | watchOS SwiftUI remote. WatchConnectivity only — never SoftAP. Embedded in the iPhone app. |
| **Android app** | `Apps/Android/app/` | Compose **shell**. Live picture and HUD I/O: [`ANDROID.md`](../ANDROID.md). Operator-visible behavior: [parity](PARITY.md). Teardown: [live-session](live-session.md). |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core |

The shared native UI modules own the Lucide catalog and the 14 custom View Assist
SVGs extracted from the approved mockup. `OpcIcon` remains a compatibility name
for the shared catalog; future brand apps import those same assets and renderers.
The assist catalog preserves the exact prototype paths, including its Tabler-derived
artwork and license. Regenerate Lucide Android VectorDrawables with
`just icons-vendor`. No JS runtime or system-icon substitutes are required.

The iOS Xcode project is generated: `cd ios && xcodegen generate`. The Watch
target is `OpenPocketCineWatch` in `ios/project.yml` — do not hand-edit the
xcodeproj. Wrist protocol: `WatchRelayProtocol` in the core; `WCSession` lives
in `WatchRelay` (iPhone) and `WatchSessionController` (watch).

## Shared monitor presentation

The multi-brand direction is [Shared Monitor Engine](SHARED-MONITOR-ENGINE.md).
UI 2.0 begins that extraction with two local SwiftPM products,
`MonitorPresentation` and `MonitorUI`. It does not rename or replace
`OpenPocketViewCore`. The [design inventory](UI-2.0-DESIGN.md) distinguishes the
reference's device screens from its simulated camera controls and preview tools.

The dependency direction is:

```text
OpenPocketCine app → MonitorUI → MonitorPresentation
                 → OpenPocketViewCore
```

`MonitorPresentation` knows viewport, safe area, capabilities and display values.
`MonitorUI` draws those values and forwards actions. Neither package imports
`CameraSession`, `AppModel`, a camera-brand enum, DUML, or the Android facade.
An app injects identity and a backend's actual capabilities; missing hardware
controls disappear rather than selecting a different brand's screen. Sora font
resources and registration travel with `MonitorUI`. Android uses the same boundary
through the local `:monitor-ui` Gradle library and its Osmo presentation adapter.

Each iOS app mounts `observeMonitorWindowGeometry()` around its root once.
The shared observer samples its containing window after UIKit lifecycle/layout
callbacks and publishes changed size/safe-area snapshots through the environment.
View bodies consume that snapshot; they do not ask a window to calculate its
safe areas during SwiftUI layout. This prevents reentrant layout on iOS 26 and
keeps rotation and same-size landscape-side changes independent of camera state.
The observer has no polling loop or video-frame subscription.
On iPadOS 26 it also samples the vertically corner-adapted safe area to reserve
the system window controls. The resulting additional top inset moves controls
and page headers; it does not crop or resize the live picture. Full-screen
windows without corner occlusion retain the reference geometry.
The iOS shell supports native iPad window resizing and does not set the deprecated
`UIRequiresFullScreen` compatibility flag. That mode scales a fixed-size scene on
iPadOS 26, leaving its reported geometry unaware of overlaid window controls.
Native resizing lets the same presentation layouts use the actual window bounds
and UIKit's control exclusions. See Apple's [migration guidance](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

The Osmo shell keeps `AppModel` and `CameraSession` as its integration owners.
`OsmoMonitorPresentation` and `OsmoCameraPageAdapter` translate their observed
state for shared presentation. Camera home and pairing forward the existing
connect/reconnect/cancel/rename/remove actions. Pairing stages advance from the
reported connection phase; a design-demo button cannot declare Wi-Fi or picture
ready. Unknown disconnected telemetry stays absent. Media catalog cells and
navigation accept shared descriptors while catalog, cache, playback and delivery
operations remain with their existing owners.

`MultiviewPresentationLayout` computes four persistent tile rectangles and fixed
transport/control positions. iOS maps the saved arrangement to that policy;
changing selection or layout never creates a second decoder for the selected
camera. Tap Layout to switch Grid/Center stage; hold it to open Shared Wi-Fi.
Clean hides the upper session controls and assist palette while retaining DISP
to restore them. Per-tile recovery, recording acknowledgement and station-network cleanup
remain in `MultiviewSession`. Its current shared assist control applies Auto LUT
through the existing per-camera LUT operation. The design's additional multi-feed
assists require a separate rendering and physical-performance qualification.

Live video and assist views remain mounted beneath settings and media overlays.
Geometry and chrome changes do not replace their decoder, Metal host, frame bus,
or connection owner. The existing `CameraSession.status` publication budget
still bounds observable telemetry; presentation adds no packet-driven updates
or live-enable writes. On iOS, an open assist inspector reuses the existing scope
tap or owns one cancellable image-preview task capped at 5 Hz. That task admits one
latest source buffer, scales to 320 pixels before processing and drops stale
work; it never attaches a second decoder or changes the native picture host.
Inspector demand belongs to the visible live or playback source. Inactive scenes
cancel image work, including UIKit inactivity notifications, and playback
inspectors cannot activate sampling on the retained live monitor.
Android previews reuse the existing raw scope tap, bounded to 213 × 120 pixels.
A separate EGL pbuffer worker runs the existing production shaders; it adds no
Vulkan render pass or decoder attachment. One admission includes rendering and
pending main-thread delivery. Owner, source and option epochs reject stale
results while preserving the 5 Hz cadence across option changes.

On iOS, fresh scope sizes follow `MonitorScopeSizing` for phone/tablet and orientation.
Their first manual resize becomes a saved absolute preference. Existing saved
scales and centers survive migration, including a legacy 1.0 scale whose original
intent cannot be inferred. Rotation changes automatic presentation without
rewriting scope options; resetting a scope restores automatic sizing.

The migration is intentionally incomplete: media/playback orchestration, scope
implementations and delivery coordinators still live in the Osmo shell, and
Nikon has not been migrated to these local packages. Full backend contracts and
cross-repository package adoption follow the documented engine phases. Do not
claim the thin-brand-app end state until another backend inherits the same
screens and workflows without copying them.

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
| SoftAP addressing, path-ready, handshake rebind, first-picture, foreground recover | `CameraSoftAP` | iOS `WiFiJoiner` / `NEHotspotConfiguration`; Android `CameraApJoiner` / `WifiNetworkSpecifier`. Handshake / first-picture / enable-once gates: Android JNI `cameraSoftAPDecision` (Kotlin `LiveViewEnablePolicy` is a JVM-test fallback only). |
| Cached SoftAP creds vs live BLE name | `CameraWifiResolution` | iOS Keychain; Android Keystore. Kotlin lockstep. A renamed SoftAP joins the live advertised name with the cached password (#257). |
| Stall, GOP-reset grace, AF-C grace, zoom grace, enable-once, rebuild ladder | `FeedWatchdog` | iOS `CameraSession.applyFeedWatchdog`; Android JNI `feedWatchdogCreate/Tick` — not a second Kotlin clone. `LinkDiagnoser` is observe-only (`feed: observe`) until [`connection-reliability.md`](connection-reliability.md) classifies #148. |
| Present hygiene (skip-dup, freeze ≠ flush, drawable gate, one enable) | `FeedPresentPolicy` | iOS `CIFeedView` / `PlaybackFeedSession`; Android `LiveFeedEffectsSession` (Kotlin lockstep + tests) |
| Clip shot color (`ColorGammaSxS`) | `ClipColorProfile` | iOS `ClipColorProfileIO`; Android `ClipColorProfile.kt` (Kotlin lockstep). Original take only — LRF/XRF is Rec.709 even for log. Shells read the `moov` tail (2 MiB Range when the 4K file is not cached) and store it in the media cache `color.json`. |
| Media HTTP storage, browse after enter-playback | `MediaHTTP.resolvedStorage`, `MediaBrowsePolicy` | iOS `CameraMedia`; Android `MediaLibraryController` (Kotlin lockstep). Pocket 3 `/v2` is storage 0. Newest `0x00/0x26` page lists without playback. |
| Gimbal cluster (stick + zoom + controls button) | `GimbalCluster` | iOS `LiveMonitorLayout` / portrait chrome; Android `GimbalCluster.kt` lockstep. |
| Gimbal mode / speed / ramp / A·B·C | `GimbalControl`, `GimbalProgram`, `GimbalMoveEngine` | iOS `LiveGimbalControls` + `CameraSession`; Android `LiveGimbalChrome` + `PocketCameraSession`. Direction Lock sends the verified world-facing lock command; joystick-hold Lock Gimbal remains paused ([gimbal controls](gimbal-controls.md)). Motion Control sends one native timed target per short leg (long arcs use timed native sub-moves), or streams a timed Bézier fillet from the background transport scheduler using direct feedback when Smoothness is nonzero. There is no artificial speed ceiling. Deadline/feedback failures are explicit. See [Motion Control takes](programmed-moves.md). `GimbalAxisObserver` stays HeadTrack-only. |
| Screen-relative gimbal stick | `GimbalStickMapping` (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs). Expo analog throw after deadzone (`GimbalStick.analogCurve`). Stick notify `0x04/0x01` at 25 Hz on the UDP ACK queue (`GimbalStick.streamInterval`); not MainActor `sendUntracked`. | iOS `DatalinkDriver.tickGimbalStick`; Android `DatalinkDriver.tickGimbalStick` on the ACK thread (`noteGimbalStick` / `restGimbalStick`) |
| Gimbal limit pulse | `GimbalLimitWatch` (stall ~300 ms after motion grace; skip pan during `FE 09` settle; rising-edge only) | iOS `CameraSession` + `GimbalGamepadBridge`; Android `PocketCameraSession` + `GimbalGamepadDriver` |
| Gamepad operator map | `GamepadOperator` (discussion #159: A record, B recenter, X 180, Y track, L1/R1 zoom chip, D-pad ISO/shutter). L2/R2 analog zoom is shell. | iOS `GimbalGamepadBridge` (`GCController`); Android `GimbalGamepadDriver` (`KeyEvent` / hat / `InputManager`) |
| AirPods look-at gimbal | `HeadTrackNative` (shared-forward native targets), `GimbalNativeTargetStream` (bounded UDP mailbox), `HeadTrack.look` (quaternion geometry) | iOS `HeadphoneMotionBridge` and session ownership tokens. Native targets drain on the ACK queue; stale samples and inactive scenes stop control. Roll readout only. Android: no IMU — PARITY exception. See [head tracking](head-tracking.md). |
| Drop storm, bounded reconnect | `SessionRecovery` | platform BLE rescan + SoftAP rejoin |
| Link score → 0–4 bars | `CameraLinkHealth` + `LinkSignalBars` | top-bar FPS chip (delivery health, not RSSI) |
| Camera SET mailbox, retransmit, settle | `CameraSetMailbox` | iOS `fireCamera`; Android JNI |
| Diagnostics redaction and report shape | `PrivacyRedactor`, `DiagnosticReport` | iOS `DiagnosticCenter` (os.Logger, MetricKit, screenshot paste); Android `diagnostics/DiagnosticCenter` (logcat + share) |
| Live-picture ND meter (stops / ND32 / ND 0.3 to balance the frame) | `NDFilterRecommendation` | iOS/Android **ND** HUD chip (Kotlin lockstep). Parks bottom-leading above the assist bar; directly draggable within the fixed-control boundaries. Long-press switches notation. Suggestion only — not a SET. Shares the LIGHTS/HISTO scope tap when the chip is on. |
| Watcher relay (Bonjour second-screen) | `WatcherRelayProtocol`, framing, join, bitrate ladder, `WatcherRelayEncodePolicy` admission/keyframe cooldown, `WatcherRelayRecovery` deadlines/backoff, frame freshness, fitted `WatcherFocusPoint`, control lease | iOS `WatcherRelayHost` (observable state), `WatcherRelayTransport` (socket queue), `WatcherRelayEncoder`, `WatcherRelayBrowser` / `WatcherRelayClient` (shared camera Wi-Fi only; `WatcherRelayNetwork` disables peer-to-peer everywhere). Android: PARITY exception — Sharing stays Coming soon. |

Platform shells own sockets, BLE, SoftAP join, permissions, lifecycle, rendering,
storage, and UI. Do not import SwiftUI, UIKit, Android, or Compose into the core.

See [`live-session.md`](live-session.md), [`feed-watchdog.md`](feed-watchdog.md),
[`connection-reliability.md`](connection-reliability.md),
[`PARITY.md`](PARITY.md), [`PERFORMANCE.md`](PERFORMANCE.md), [`UX.md`](UX.md),
and [`ANDROID.md`](../ANDROID.md).

See the [protocol handbook](https://openpocketcine.app/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).
