# Architecture

OpenPocketCine is a shared Swift business/protocol core with native platform shells.

| Layer | Path | Purpose |
| --- | --- | --- |
| **Monitor presentation policy** | OpenCine `MonitorPresentation` (`../OpenCine`) | Foundation-only viewport geometry, capability gates and camera/media presentation values. No camera protocol or platform I/O. |
| **Shared native monitor UI** | OpenCine `MonitorUI` (`../OpenCine`) | SwiftUI pages, controls, navigation, camera home/pairing and media catalog presentation; bundled Sora resources. Camera state and actions are injected. iOS-only implementation, separate from the portable core. |
| **Shared native Android UI** | OpenCine `Android/monitor-ui/` (sibling checkout, Gradle included build `opencine`) | Compose pages, controls, typography and icon assets. Camera state and actions are injected; no JNI or camera ownership. |
| **Shared core** | `Sources/OpenPocketViewCore/` | DUML, commands, status, LUTs, layout policy. **Portable** Foundation. |
| **DJI Apple integration** | OpenCine `OpenCineDJIApple` | Bluetooth/network transport and control exchange with injected host policy. No UI, storage or monitor-runtime import. |
| **Apple picture runtime** | OpenCine `OpenCineApple` | Decoder, native assist work, source publications and retained picture presentation. Source interpretation is configured by the app. |
| **iOS app** | `ios/OpenPocketCine/` | SwiftUI composition, credential/permission policy, source calibration and remaining session/recovery orchestration. Teardown: [live-session](live-session.md). |
| **Watch companion** | `ios/OpenPocketCineWatch/` | watchOS SwiftUI remote. WatchConnectivity only — never SoftAP. Embedded in the iPhone app. |
| **Android app** | `Apps/Android/app/` | Compose **shell**. Live picture and HUD I/O: [`ANDROID.md`](../ANDROID.md). Operator-visible behavior: [parity](PARITY.md). Teardown: [live-session](live-session.md). |
| **Android facade** | `Sources/OpenPocketCineAndroidFacade/` | Swift session and JNI boundary |
| **Tests** | `Tests/OpenPocketViewCoreTests/` | Swift Testing suite for the portable core |

The shared native UI modules own the Lucide catalog and the 14 custom View Assist
SVGs extracted from the approved mockup. `OpcIcon` remains a compatibility name
for the shared catalog; future brand apps import those same assets and renderers.
The assist catalog preserves the exact prototype paths, including its Tabler-derived
artwork and license. Regenerate Lucide SVGs and Android VectorDrawables with
OpenCine's `scripts/vendor-lucide-icons.py`. No JS runtime or system-icon
substitutes are required.

The iOS Xcode project is generated: `cd ios && xcodegen generate`. The Watch
target is `OpenPocketCineWatch` in `ios/project.yml` — do not hand-edit the
xcodeproj. Wrist protocol: `WatchRelayProtocol` in the core; `WCSession` lives
in `WatchRelay` (iPhone) and `WatchSessionController` (watch).

## Common-control connection lifetime

`CameraSession.control` is bound to one native connection through OpenCine's
`DJIControlSessionBinding`. A new operator connection gets a fresh common session;
datalink recovery keeps its session identity and advances its control epoch.
Saved-camera scanning retires the old binding before changing the native target,
so a late close cannot cancel the next camera's connection attempt.

Closing the current owned common session invokes the existing native disconnect
teardown once. Native teardown retires the common binding before resetting the
transport; this prevents reentrant cleanup. Returning a borrowed Multiview view
retires only its controls and leaves the tile's transport/decoder owner alive.
Settings and Media coverage retain the connection. The common binding sends no
camera commands and never stops recording; gimbal/motion cleanup remains the
existing native disconnect behavior.

Both app roots now compose `AppShell` over that connection with one
`MonitorControlModel`. `ShellModel` owns pairing, the active monitor, scene
activity and Settings/Media coverage; the compatibility panel properties
project its one cover value. `MonitorScreen` holds the existing native picture
host and common status, capture and system positions. Native gimbal, tracking,
assist, settings, media and recovery content fill bounded slots. Covers retain
the picture and camera; a borrowed Multiview monitor returns its loan once.
The watch relay keeps its existing remote-source experience.

ISO, manual shutter duration, Kelvin and EV use typed common capture choices
and the editor captured when the gesture or panel opened. Common AF-S/AF-C and
zoom cycle commands use capability admission. DJI focus-tracking strategy,
Auto ISO limits, AWB/AE lock, operator shutter angle, exposure mode, iris
strategy and continuous zoom completion retain their typed native adapters.
In particular, native pinch/dial completion still owns DJI color restoration;
moving that gesture lifecycle belongs to the later native-runtime increment.

## Apple control exchange

The iOS app composes `DjiAppleControlExchange` from `OpenCineDJIApple` with its Bluetooth
link and datalink. The exchange owns the sole BLE drain, reply requests, held pairing
replies and SET mailbox lifetime, including cancellation, retransmission and coalescing.
App adapters retain status decoding and presentation pins, operator authority, incident
storage, credential policy and the decision to repair a session. The integration imports
no UI or neutral native monitor runtime.

Common receipt confirmation uses `cameraReportedCapture`, including explicit recording
report presence. The separate `legacySettlement` context preserves existing busy-release
and recovery decisions from presentation state. Initial command admission and native
teardown keep their existing ordering. Closing a local exchange sends no camera command
and leaves transport ownership with the caller, including a borrowed Multiview tile.

## Apple negotiated-picture recovery

`OpenCineDJIApple.DjiApplePictureRecovery` owns the single repair task/generation,
negotiated endpoint workflow, bounded genuine-picture wait and held-cycle history.
Current media return claims the same slot, including a full-rejoin gap with no driver.
The app supplies one authority aggregate and four native actions: ordered preparation,
initial enable, bounded first-picture inspection and actual source/presentation freshness.
Its native decoder repair and full rejoin use the same owner-issued attempt. Retiring
picture intent preserves negotiation; a genuine current-transport failure still escalates.

The app retains gimbal/control/native preparation, FeedWatchdog decisions and camera grace,
gallery resume, full connection/recovery episode, saved credentials and journal. The shared
owner imports no UI/native monitor runtime. The 100ms polling, 16s default picture deadline
and existing held-cycle history remain unchanged; reset cancels local work without resetting
that history or sending a camera command. This is an Apple-only ownership move; Kotlin
continues to use its existing integration scheduler and portable policies. Full P2 and
physical camera qualification remain unfinished.

## Apple picture ownership

`HevcDecoder` configures `OpenCineApple.MonitorLiveVideoRuntime` with the existing DJI
source calibration, official look data, transfer inference and diagnostic hooks. The
shared owner holds VideoToolbox format/session lifetime, encoded and decoded demand,
assist work, frame baking, native picture presentation and metrics. `CIFeedView`,
the display container, scaler and upscaler use those same native owners. DJI transport
supplies encoded input and recovery signals; `CameraSession` still decides when the
existing watchdog sends a camera command. The integration imports no picture runtime.

A source lease fences publication and calibration. Camera reports update only the
runtime's current live lease, even while a clip owns the display projection. A weak
provider installed by the actual camera or tile owner seeds a newly attached or
reopened source from decoded reports. Unknown stays absent, and presentation pins
never supply calibration. The measured reference EI in the calibration profile is
the table's origin, not a claim about the camera's current ISO.

Playback owns a separate publication lease and carries it with the item epoch through
asynchronous assist work. An old decoder or playback session cannot clear its
successor's publication. Settings/Media coverage and borrowed Multiview return retain
the actual source. Runtime reset supports reuse; terminal close retires that owner.
The picture view does not close the decoder. Connection, recovery, keepalive and
continuous DJI gesture ownership remain app-side work in the later P2 increments.

## Apple clip playback ownership

Pocket configures `OpenCineApple.MonitorPlaybackFeedSession` with its existing
measured source profile, HDR display preference, journal and frame-advance
notification. `MonitorPlaybackFeedHost` holds the identity AVPlayer layer and
processed-picture siblings. The shared owner holds video-output attachment,
display-link polling, the serial pull queue, item/source retirement and assist
publication. The app attaches that output before replacing the player's item.
Its adapter converts existing operator effects into `MonitorFrameEffects` values;
it contains no second sampling or rendering loop.

`MonitorPlaybackAudioMeterRuntime` owns the real audio tap, cancellable track
query, source lease, polling and meter history. The app retains AVAudioSession
activation policy and converts measured values for its existing overlay.
Unmeasured audio stays absent through the overlay and clip inspector; measured
zero remains known silence. Player disposal closes the audio and feed owners.
Portable conform policy is the shared `MonitorConformPreview`, using the existing
constructor and source names through an app type alias.

The adjacent `PlaybackVideoLayout` public helper retains its original code body
until whole-player/layout adoption. It is temporary app compatibility policy,
separate from the shared conform algorithm.

The gallery/DUML adapter, per-clip preparation and player workflow, assists UI and
delivery remain app-owned migration work; AVAudioSession policy stays with the app.
This bounded adoption passes portable, strict, repository, both-architecture iOS
build and Android consumer checks. All 50 affected native iOS tests pass, including
real decoded-video source retirement. These native fixtures are SIMULATED;
full P2 and physical device playback qualification remain unfinished.

## Shared monitor presentation

The multi-brand direction is [Shared Monitor Engine](SHARED-MONITOR-ENGINE.md).
UI 2.0 begins that extraction with two SwiftPM products,
`MonitorPresentation` and `MonitorUI`, which now live in the OpenCine package
(sibling checkout `../OpenCine`, referenced by path from `ios/project.yml`).
It does not rename or replace `OpenPocketViewCore`. The [design inventory](UI-2.0-DESIGN.md) distinguishes the
reference's device screens from its simulated camera controls and preview tools.

The dependency direction is:

```text
OpenPocketCine app → MonitorUI → MonitorPresentation
                 → OpenPocketViewCore
```

`MonitorPresentation` knows viewport, safe area, capabilities and display values,
including operator chrome tokens (readout type, settings-card title gap, compact
capture height, category-tab and grabber gating). Motion placement uses
module-owned `Point` / `Size` (`Double`) so the portable policy compiles on the
Release SDK without CoreGraphics overlays; native shells convert at their
presentation boundary. That is a compiler/SDK seam, not an operator-visible
behavior change. `MonitorUI` draws those values
and forwards actions. Neither package imports
`CameraSession`, `AppModel`, a camera-brand enum, DUML, or the Android facade.
An app injects identity and a backend's actual capabilities; missing hardware
controls disappear rather than selecting a different brand's screen. Sora font
resources and registration travel with `MonitorUI`. Android uses the same boundary
through the shared `monitor-ui` library (OpenCine included build) and its Osmo presentation adapter.

Each iOS app mounts `observeMonitorWindowGeometry()` around its root once.
The shared observer samples its containing window after UIKit lifecycle/layout
callbacks and publishes changed size/safe-area snapshots through the environment.
View bodies consume that snapshot; they do not ask a window to calculate its
safe areas during SwiftUI layout. This prevents reentrant layout on iOS 26 and
keeps rotation and same-size landscape-side changes independent of camera state.
The observer has no polling loop or video-frame subscription.
On iPadOS 26 it also samples the vertically corner-adapted safe area to reserve
the system window controls. This corner-adapted sample is iPad-only: iPhone
rounded corners must not add a second top offset. The resulting additional top
inset moves controls and page headers; it does not crop or resize the live picture. Full-screen
windows without corner occlusion retain the reference geometry.
The iOS shell supports native iPad window resizing and does not set the deprecated
`UIRequiresFullScreen` compatibility flag. That mode scales a fixed-size scene on
iPadOS 26, leaving its reported geometry unaware of overlaid window controls.
Native resizing lets the same presentation layouts use the actual window bounds
and UIKit's control exclusions. See Apple's [migration guidance](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

The Osmo shell keeps `AppModel` and `CameraSession` as its integration owners.
`OsmoMonitorPresentation` translates live state for shared presentation. Camera
home and pairing use OpenCineAppKit's `CamerasModel`, `CamerasScreen` and
`PairScreen` on both platforms. `DJIIntegration` connects through the iOS
`DJIConnectPort` over `CameraSession`; Android `DjiIntegration` connects through
the shared DJI session. The app supplies pairing callouts and the existing
station-network wizard as typed slots. Pairing stages advance from the reported
connection phase. Unknown disconnected telemetry stays absent. Media catalog
cells and navigation accept shared descriptors while catalog, cache, playback
and delivery operations remain with their existing owners.

`SavedCamerasStore` owns a versioned saved-camera document in each app's existing
preference namespace. `BodyRecordsV0` imports the legacy records and mirrors
edits back so older builds remain usable. A three-way merge keeps edits made
after a downgrade and preserves document-only route identities. Saved camera
IDs, Keychain/Keystore entries, media favorites and preference keys do not move.
One malformed legacy record is retained without erasing the readable cameras.

Small option collections use `MonitorSnapshotRows`: bindings and label callbacks
are evaluated on the main actor into immutable row values. SwiftUI may later
materialize `ForEach` content on its asynchronous renderer; that deferred closure
only returns the stored row. Button actions retain main-actor ownership. Native
regression tests invoke the real deferred content off-main. This is for bounded
option groups, not eager rendering of unbounded media catalogs.

The shared native `MonitorTabStrip` components draw one baseline and its active
segment: left for vertical navigation, bottom for horizontal tabs. They add no
plate, box, fill or inter-tab dividers. Camera/recording controls and navigation
in Settings, Media, assists and LUT catalogs retain their selection and actions.
Ordinary setting-value selectors remain separate controls.

`MultiviewPresentationLayout` computes four persistent tile rectangles, the
Exit/Wi-Fi controls, readouts and the shared collapsible View Assist palette.
Grid keeps four portrait rows or two landscape columns. Portrait Center stage
keeps its full-width 16:9 main feed and right-side tools below it. Landscape
Center stage moves Wi-Fi below Exit, puts tools in the left column, and gives
its larger 16:9 main feed bottom in-picture readouts. Existing tile metadata
reserves a separate row above them. A far-right secondary viewport ends above
native DISP/Record and scrolls three retained camera hosts. Only content alpha
fades at scrollable edges; no colored overlay or label is painted there. A
left cutout bounds the palette below the island while preserving native touch
targets and scrolling. Grid retains the opposite-cutout toolbar policy. Record
and DISP always reuse the platform's normal Field Monitor geometry.

The stage itself (tiles, camera options, tools, program readouts, DISP, record
on all cameras and the camera picker) is OpenCine's shared `MultiviewStage`
(appkit, SwiftUI and Compose). Pocket maps each `MultiviewSession` tile to a
`MultiviewTile` value (`MultiviewTileValues`) and answers the stage's actions;
pictures, the video backdrop, camera settings, network setup and borrowed Live
View stay in the app. The iOS canvas (`MultiviewStageCanvas`, OpenCine
MonitorUI) retains four child hosting controllers keyed by slot and moves their
existing views between the canvas and native scroll view. Scroll changes update a native alpha mask; backdrop preparation reads
actual converted view bounds and intersects them with the scroll viewport at
its existing admission cadence. No scroll observer publishes into the camera
session, and no additional decoder or preview-enable path is created.
Per-camera options remain available inside every occupied tile, including the
smaller portrait feeds. One tap selects without changing the arrangement.
Clean hides the upper session controls and assist palette while retaining DISP
to restore them. Per-tile recovery, recording acknowledgement and station-network cleanup
remain in `MultiviewSession`. Its current shared assist control applies Auto LUT
through the existing per-camera LUT operation, enabled by default for newly
added cameras. Tile batteries and HH:MM:SS timecode reuse Live View presentation.
Camera options use bounded floating monitor components. Camera settings opens
from the toolbar with a tab per connected camera. Its editor reuses the Live View setting controls and command settlement,
with a binding that has no feed ownership. Changing tabs or losing the selected
connection retires pending edits; opening or closing the editor cannot replace
the tile's decoder, frame callbacks or network owner. The design's additional multi-feed
assists require a separate rendering and physical-performance qualification.

Saved-camera Add setup and Multiview use one iOS `StationNetworkSetupView` for
source choice, current/saved/nearby networks, credentials and scan-to-connect
handoff. Fixed section headers align the columns through scan state changes;
Connect and manual network entry stay in the bottom safe/keyboard-adjusted footer. The entry points inject their connection owners. Android Multiview
uses the equivalent shell form, `StationNetworkSetup`, with injected scan and
connect actions. Saved-camera setup chips and Add setup use the shared flow on both platforms.
`MultiviewProvisioner` owns a bounded camera scan and returns the camera to its
access point on the same BLE link, including cancellation. Multiview journals a
cleanup obligation immediately before the station setter, removes it only on a
confirmed return and waits for the scan before stage shutdown. No network form
owns a live decoder, watchdog or preview-enable path.

Live video and assist views remain mounted beneath settings and media overlays.
Geometry and chrome changes do not replace their decoder, Metal host, frame bus,
or connection owner. The existing `CameraSession.status` publication budget
still bounds observable telemetry; presentation adds no packet-driven updates
or live-enable writes. On iOS, an open assist inspector reuses the existing scope
tap or borrows the session-retained image renderer. Shared `MonitorPreviewAdmission`
retains one occupied work slot and a monotonic 200 ms admission floor across tabs,
dismissal and remount. Cancelling invalidates adoption without releasing a still-running
job. Admission precedes LUT preparation and scales the latest source to 320 pixels
before processing. Owner, source and option epochs reject stale results; there is
no second decoder or change to the native picture host.
The live sample bus retains the latest raw decoded buffer independently of scope
bundle publication. Image inspectors therefore receive picture with every scope
off. This is a reference assignment at the existing completion boundary, not a
copy, extra decoder, scope calculation or frame-rate observable publication.
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
rewriting scope options; resetting a scope restores automatic sizing. Fresh
windowed tools and the floating false-color reference key open at the canvas
center; existing saved positions survive. The audio meter uses the same movement
bounds with a left/vertical-center initial position and separate persisted bar
orientation, dB display and portrait/landscape position preferences. Live and
playback inject their existing level measurements without another audio sampler.
The slim meter plate does not grow when its channel labels are enabled.

Floating system buttons share `MonitorChromeButton` for visible shape, glass,
active/disabled appearance and press feedback. Camera taps and held previews
use one capture drawer renderer and geometry: tap is the details drawer, hold is
the compact 128 pt dial at the same well. FORMAT / COLOR / shooting mode hang
from the top well; landscape shooting mode is its own top sheet, not FORMAT.
Camera values stay bottom-center and remain visible during a top tap or hold.
The held presentation is
read-only and cannot refresh camera settings. The Osmo adapter retains option
mapping, release authorization and delayed command settlement. Gimbal Mode /
Speed / Ramp use tabs within the shared inspector, with the same value drum used
by capture controls. `MonitorMotion` owns reference timing and easing so shells do
not tune independent versions of a widget's animation.

Covered chrome uses `monitorPresentationVisibility`. Coverage by an opaque page
is separate from scene activity and from a visible source lacking pixels. The
host stays mounted; opacity, hit-testing and accessibility follow coverage, and
decorative pulses stop without remounting page or native-feed owners. The shared
modifier must not introduce a layout stack or force accessibility visible on an
ancestor: either can override the ordering or accessibility of bounded controls.
A control that explicitly opts into accessibility, such as Record, applies its
coverage gate at that bounded control; persistent capture panels apply the same
gate before viewport placement. Callers apply their final restrictive hit-testing
predicate after the visibility modifier. Portrait Settings and Media retain their
original native input through the picker's dismiss plane: iOS excludes their
enabled rectangles, and Android registers them in the same bounded region owner
as readouts. Disabling or unmounting a control retires its exclusion.

`MonitorCanvas` stores main-actor builders for picture, assists and chrome, then
evaluates each in its own fixed child body. Observable reads belong to that
slot instead of the parent geometry calculation. Parent layout changes supply
fresh builders; there is no cached output or equality gate that could retain
stale state. Hosted tests verify independent telemetry delivery, updated layout
captures and native view identity through rotation and coverage.

UI 2.0 surface policy separates Gaussian blur, saturation and tint from geometry
and foreground content. Shared widgets consume passive image products and their
canvas placement; they do not request camera frames. Platform presentation
owners admit bounded display-look work, reuse the existing frame source and
invalidate old products when the visible source changes. This lets another
camera shell reuse the surface renderer without copying decoder or connection
logic. The [reference contract](UI-2.0-DESIGN.md#blurred-surfaces) defines the
values; [parity](PARITY.md#ui-20-qualification) records source and platform
fallbacks, and [performance](PERFORMANCE.md) owns admission limits.

Compose page navigation keeps the content slot in one composition position as
the rail becomes a portrait tab row; rotation does not remount the page owner.
Assist and gimbal panes share `MonitorInspector`, and the Motion Control duration
ruler lives in `MonitorDurationDial` with injected range, labels and actions.
Clip cards accept an optional favorite action; its absence removes the action
from both grid and list layouts without importing a camera capability enum.
The shared camera readout owns the original pointer and a display-only preview
slot. The Osmo shell injects the compact or details drawer for that well and
revalidates source, lifecycle, lock state and current options immediately before
dispatching a release action.

Shared editing widgets pair each begin event with exactly one normal or
cancelled completion. Playback scrub cancellation clears the host's editing
state without inventing a final seek; the player adapter decides whether an
interrupted current clip resumes. Source changes and disappearance cannot
restart a dismissed player.

The migration remains incomplete, but shared adoption now includes iOS
`MonitorClipDelivery`, Android `MonitorOriginalDeliveryHost` and Android
`MonitorAssistState`. Shared MonitorUI owners render Apple scope plots. The app
retains source calibration, composition and native integration policy. Android
original sharing does not imply conversion or Frame.io parity. Current adoption
and remaining verification are tracked in the [engine plan](SHARED-MONITOR-ENGINE.md).
Do not claim the thin-brand-app end state until another backend inherits the same
screens and workflows without copying them and the advertised paths are qualified.

## Apple session heartbeat

`DjiAppleSessionHeartbeat` owns the actual iOS registration timer and camera-path grace.
The app supplies one lifecycle/repair context and consumes bounded maintenance/path-loss
events. Native picture/watchdog decisions, gallery, journal and gimbal cleanup retain their
app adapters. Registration runs through inactive scenes, covers and held picture, with BLE
before datalink registration/ACK and the unchanged Selfie Flip fallback. Run and endpoint
identity reject old wakes after disconnect or replacement. Borrowed Multiview views do not
start a second heartbeat and cannot retire the tile's owner.

The app no longer owns this loop or `CameraPathRecovery` history. It retains connection,
foreground, negotiated picture repair and bounded session-recovery orchestration, which
remain later P2 increments. The shared integration imports no UI or neutral native monitor.
Physical iPhone/camera qualification remains untested.

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
| Present hygiene (skip-dup, freeze ≠ flush, drawable gate, one enable) | `FeedPresentPolicy` | iOS OpenCineApple picture runtime plus `PlaybackFeedSession` player composition; Android `LiveFeedEffectsSession` (Kotlin lockstep + tests) |
| Clip shot color (`ColorGammaSxS`) | `ClipColorProfile` | iOS `ClipColorProfileIO`; Android `ClipColorProfile.kt` (Kotlin lockstep). Original take only — LRF/XRF is Rec.709 even for log. Shells read the `moov` tail (2 MiB Range when the 4K file is not cached) and store it in the media cache `color.json`. |
| Media HTTP storage, browse after enter-playback | `MediaHTTP.resolvedStorage`, `MediaBrowsePolicy` | iOS `CameraMedia`; Android `MediaLibraryController` (Kotlin lockstep). Pocket 3 `/v2` is storage 0. Newest `0x00/0x26` page lists without playback. |
| Gimbal cluster (stick + zoom + controls button) | `GimbalCluster` | iOS `LiveMonitorLayout` / portrait chrome; Android `GimbalCluster.kt` lockstep. |
| Gimbal mode / speed / ramp / A·B·C | `GimbalControl`, `GimbalProgram`, `GimbalMoveEngine` | iOS `LiveGimbalControls` + `CameraSession`; Android `LiveGimbalChrome` + `DjiCameraSession`. Direction Lock sends the verified world-facing lock command; joystick-hold Lock Gimbal remains paused ([gimbal controls](gimbal-controls.md)). Motion Control sends one native timed target per short leg (long arcs use timed native sub-moves), or streams a timed Bézier fillet from the background transport scheduler using direct feedback when Smoothness is nonzero. There is no artificial speed ceiling. Deadline/feedback failures are explicit. See [Motion Control takes](programmed-moves.md). `GimbalAxisObserver` stays HeadTrack-only. |
| Screen-relative gimbal stick | `GimbalStickMapping` (invert pan on rotate-180 at settle, not joystick 180; extra-mirror = TT180 && Selfie Flip off; MIRROR assist XORs). Expo analog throw after deadzone (`GimbalStick.analogCurve`). Stick notify `0x04/0x01` at 25 Hz on the UDP ACK queue (`GimbalStick.streamInterval`); not MainActor `sendUntracked`. | iOS `DatalinkDriver.tickGimbalStick`; Android `DatalinkDriver.tickGimbalStick` on the ACK thread (`noteGimbalStick` / `restGimbalStick`) |
| Gimbal limit pulse | `GimbalLimitWatch` (stall ~300 ms after motion grace; skip pan during `FE 09` settle; rising-edge only) | iOS `CameraSession` + `GimbalGamepadBridge`; Android `DjiCameraSession` + `GimbalGamepadDriver` |
| Gamepad operator map | `GamepadOperator` (discussion #159: A record, B recenter, X 180, Y track, L1/R1 zoom chip, D-pad ISO/shutter). L2/R2 analog zoom is shell. | iOS `GimbalGamepadBridge` (`GCController`); Android `GimbalGamepadDriver` (`KeyEvent` / hat / `InputManager`) |
| AirPods look-at gimbal | `HeadTrackNative` (shared-forward native targets), `GimbalNativeTargetStream` (bounded UDP mailbox), `HeadTrack.look` (quaternion geometry) | iOS `HeadphoneMotionBridge` and session ownership tokens. Native targets drain on the ACK queue; stale samples and inactive scenes stop control. Roll readout only. Android: no IMU — PARITY exception. See [head tracking](head-tracking.md). |
| Drop storm, bounded reconnect | `SessionRecovery` | platform BLE rescan + SoftAP rejoin |
| Link score → 0–4 bars | `CameraLinkHealth` + `LinkSignalBars` | top-bar FPS chip (delivery health, not RSSI) |
| Camera SET mailbox, retransmit, settle | `CameraSetMailbox` | iOS `fireCamera`. Android still uses local `inflight` / `inflightPending`, `fireKind` and `finishInflight`; migration to the shared mailbox remains pending. See [stress/refactor follow-up](connection-stress-testing.md#turn-failures-into-refactors). |
| Diagnostics redaction and report shape | `PrivacyRedactor`, `DiagnosticReport` | iOS `DiagnosticCenter` (os.Logger, MetricKit, screenshot paste); Android `diagnostics/DiagnosticCenter` (logcat + share) |
| Live-picture ND meter (stops / ND32 / ND 0.3 to balance the frame) | `MonitorNDFilterRecommendation` | iOS/Android **ND** HUD chip (Kotlin lockstep). Starts centered until placed; directly draggable within the fixed-control boundaries. Long-press switches notation. Suggestion only, not a SET. Shares the LIGHTS/HISTO scope tap when the chip is on. |
| Watcher relay (Bonjour second-screen) | `WatcherRelayProtocol`, framing, join, bitrate ladder, `WatcherRelayEncodePolicy` admission/keyframe cooldown, `WatcherRelayRecovery` deadlines/backoff, frame freshness, fitted `WatcherFocusPoint`, control lease | iOS `WatcherRelayHost` (observable state), `WatcherRelayTransport` (socket queue), `WatcherRelayEncoder`, `WatcherRelayBrowser` / `WatcherRelayClient` (shared camera Wi-Fi only; `WatcherRelayNetwork` disables peer-to-peer everywhere). Android: PARITY exception — Sharing stays Coming soon. |

Platform shells own sockets, BLE, SoftAP join, permissions, lifecycle, rendering,
storage, and UI. Do not import SwiftUI, UIKit, Android, or Compose into the core.

See [`live-session.md`](live-session.md), [`feed-watchdog.md`](feed-watchdog.md),
[`connection-reliability.md`](connection-reliability.md),
[`PARITY.md`](PARITY.md), [`PERFORMANCE.md`](PERFORMANCE.md), [`UX.md`](UX.md),
and [`ANDROID.md`](../ANDROID.md).

See the [protocol handbook](https://opencapture.org/openpocketcine/docs/) for wire-level detail
(Markdown source in `handbook/src/content/docs/`; stub at [`protocol-notes.md`](protocol-notes.md)).

## Apple subject tracking ownership

`DjiAppleSubjectTracking` in OpenCineDJIApple owns ActiveTrack request IDs, pending
box admission, camera push/poll interpretation, smoothing and the single polling
lifetime. CameraSession projects the committed snapshot through its existing
search/subject/tracking properties. Native face detection and focus presentation,
operator gimbal cancellation and the actual control exchange stay with the host.

The owner captures the real datalink and control generation before acknowledgements
and polling suspension. Native face preparation rechecks the same publication
authority between synchronous host mutations. Retiring tracking never sends a
camera command; the operator clear path retains its existing conditional CLEAR.
The original 500ms polling, six idle ticks and clear/silence policies remain in use.
This Apple integration increment does not replace the remaining session facade,
watch/relay/motion ownership or Android's existing DJI scheduler.

## Apple serialized camera settings

`DjiAppleCameraSettings` owns the actual FIFO camera request chain: audio channel,
vocal boost, mandatory DSP GET/patch/SET, audio/focus/ISO-limit refresh, focus-track
SET and glamour GET/disable. Its typed output returns captured rollback facts and
actual pin identity; the host keeps editor pins, optimistic status and diagnostics.
The owner captures native driver/control identity and request generation across
suspension; retired operations cannot publish rollback or write into a successor.
The existing native request/response primitive and protocol math stay unchanged.
There is no app enqueue callback, shadow audio catalog or synthesized DSP blob.

## Apple tap-focus sequence candidate

The proposed `DjiAppleTapFocus` owns one independent four-write tap sequence and its local
cancellation. The actual session supplies its datalink identity/control generation, untracked
PREPARE write and existing request primitive. PREPARE has no ACK wait; the point, hint and
commit keep the original 800 ms deadlines. A refused point stops the sequence, while a
refused hint still permits commit. Retiring or replacing the captured control source cannot
authorize a later write or cancel a successor sequence.

The app keeps actual point clamping, reticle/face presentation, tracking cancellation and
diagnostic copy. This source-only Apple proposal changes no Android workflow; native
first-picture format poke and zoom/color restoration remain distinct integration work.
No physical camera qualification or full session checkpoint closure is claimed.

## Apple gimbal control ownership

`DjiAppleGimbalControl` in OpenCineDJIApple owns the stick stream, mode/speed pins, pose
mapping, limit watch, world level, head-track tokens and programmed moves. CameraSession
is its `DjiAppleGimbalHost`: it keeps the observable gimbal state the views read
(`gimbalMode`, `gimbalProgram`, `gimbalMoveRunning`, ...), applies the pose view flip to
the decoder, retires manual zoom for a zoom take and journals through `ControlLiveLog`.
Views call actions on `session.gimbal`. Wire traffic, pins and timings are unchanged.
