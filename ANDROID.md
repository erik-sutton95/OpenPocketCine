# Android — sharing Swift the OpenZCine way

OpenPocketCine’s Android app lives in this repository (`Apps/Android/`,
`Sources/OpenPocketCineAndroidFacade/`). It is **not on Google Play yet**. iOS is
the daily driver.

Business logic stays in **`OpenPocketViewCore`** (UI-free, I/O-free Foundation).
Android follows the public [OpenZCine](https://github.com/erik-sutton95/OpenZCine)
pattern rather than Skip/SKIE/an xcframework.

## How the Android build is structured

Source: the public [OpenZCine](https://github.com/erik-sutton95/OpenZCine) repository.

1. **Portable Swift core** — `Sources/OpenPocketViewCore/` never imports SwiftUI, UIKit, or Android.
2. **Android JNI facade** — `Sources/OpenPocketCineAndroidFacade/` owns the session that talks to the camera on Android, plus hand-written `@_cdecl` JNI shims (`SwiftCoreJNI.swift`). A header-only `CJNI` target exposes NDK `<jni.h>` on Android only.
3. **Cross-compile, don’t SPM-link** — Gradle task `:app:stageSwiftCore` (`just android-core`, `scripts/android-stage-swift-core.sh`) builds `aarch64-unknown-linux-android29` and stages `libOpenPocketCineAndroid.so` plus the Swift runtime `.so` closure into generated jniLibs. **arm64-v8a only.** Toolchain pin: Swift **6.3.3** + `swift-6.3.3-RELEASE_android`.
4. **Kotlin seam** — `Apps/Android/core-api` defines `CameraSession` / `CameraIdentity` interfaces. The Compose app implements them with `SwiftCoreCameraSession` over JNI. Kotlin does not pack protocol bytes.
5. **Same applicationId as iOS bundle** (`com.opencapture.openpocketcine`). Design tokens are duplicated as floats in `Theme.kt` / `pairing/StartupDesign.kt` so connection screens match.

iOS links the core via Swift Package Manager. Android does **not** consume that SPM product at runtime — only the cross-compiled `.so`.

## Pocket mapping

| Piece | OpenPocketCine |
| --- | --- |
| Portable Swift core | `OpenPocketViewCore` (DUML, HEVC depacketizer, saved-camera records, connection phase) |
| JNI facade | `OpenPocketCineAndroidFacade`: BLE/Wi-Fi/UDP session that calls the core, JNI surface for scan/connect/live-frame callbacks |
| `core-api` | Kotlin `CameraSession` wrapping the facade |
| Compose shell | Splash + saved cameras + Osmo connection wizard using the same `StartupColors` / `BrandColors` floats as iOS |
| Saved cameras | `SharedPreferences` file `openpocketcine.saved-cameras`, key `records-json`. Wi-Fi passwords stay out of prefs (re-read over BLE, same as iOS) |
| applicationId | `com.opencapture.openpocketcine` on iOS and Android |

## Do not copy from OpenZCine Android

Nikon PTP-IP, AccessorySetupKit / `NIKON_ZR_*` SSIDs, multi-setup path chips, OCR SSID scanner, USB-C/HDMI paths, monitor assist tools.

## First Android milestone

Done in-tree (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)):

1. Same Swift Android SDK pin OpenZCine uses (6.3.3).
2. `OpenPocketCineAndroidFacade` + `CJNI` in `Package.swift` (`#if os(Android)` JNI).
3. Gradle `:app:stageSwiftCore` stages `libOpenPocketCineAndroid.so`.
4. Compose splash → empty-store wizard / saved list → live HEVC (MediaCodec) using enable-once + ACK pump.

## Operator parity (iOS baseline)

The Compose shell now tracks the iOS operator surface, with Apple-only pieces skipped:

- **Connection:** BLE → SoftAP → UDP datalink, FeedWatchdog-style enable policy (never 1 Hz `0x09/0xa8`). Bind UDP `0.0.0.0:0` (ephemeral local port, like iOS/Mimo) then connect `192.168.2.1:9004` — a local `:9004` bind accepted handshake + `0x01` and dropped HEVC. Arm HEVC ingest on the enable write like iOS/Mimo — do not wait for a DUML ACK (that 200 ms window dropped the VPS). Do not send gallery `0x02/0x0c` to start live view — only when status says playback. First-picture recover stays armed after a SoftAP flap (`holdsMonitor` must not latch a forever skip). Session recovery holds the last frame. Disconnect disposes the UDP driver (callbacks, executors, sockets) and joins the MediaCodec output thread so a reconnect does not inherit a half-dead live session — force-stopping the app was the only reliable reset. Stale `open()` after cancel is ignored. Nano AVC + Pocket HEVC via MediaCodec 720p at the body's live rate (wall-clock PTS, `KEY_LOW_LATENCY`; do not pace at 30 fps). Cached Wi-Fi creds in private prefs (not saved-camera JSON).
- **Live chrome:** landscape/portrait layout metrics matching iOS (`LiveDesign`). Portrait Fill center-crops the 16:9 picture into the taller well (iOS `fillCrop`) — it does not stretch. Pocket screen flip (taller HEVC SPS) rebuilds MediaCodec and pillarboxes 9:16 in the cinema 16:9 well (`LiveMonitorLayout.pictureFrame`, iOS `pictureAspect`) — zoom/gimbal stay on the well. DISP 1/2 maps, chrome editor, record confirmation as a bottom action sheet (not a centred dialog), zoom chip, gimbal stick with the iOS 1–5 sensitivity gain (`GimbalStick.encode` / `SwiftCore.gimbalStickEncode`), rec lamp calling `pressShutter` (photo / SuperNight still; video start/stop otherwise). Capture, format/color, and assist long-press popups use `liveChromeGlass` (same ND plate as the HUD) plus the circular glass close — not an opaque black card with a text ✕. Every View Assist options sheet and capture picker (ISO / shutter / WB drums) uses the LUT chrome: 27 dp close, 12 dp pad / 8 dp gap, 0.12/0.88 drum fade with 27/20 pt faces, and a well from a 12 dp top margin down to the bar (short menus hug; ISO / shutter / WB drums fill so neighbours peek). FORMAT and COLOR hang 8 dp under the top-deck chips at 340 dp (iOS `LiveTopPickerHost`) and hug — they do not fill to the assist bar. Storage toggles GB·% vs remaining minutes. LUT drum faces 27/20 pt with 0.12/0.88 fade so neighbours peek, and 50/50 stays pinned. Picker / assist cards add a 0.20 black ND on HUD glass so they read a tad denser than the bars, and sample the scene backdrop so liquid glass blurs chrome under the sheet. Capture sheets reseat ISO/shutter drums only on the iOS `onChange` keys (available ISO list, color mode, shutter list, fps, expo mode) so opening Manual or scrolling a wheel does not snap back to the first option.
- **Assists:** toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR). Long-press options use the same settings rows, capsule switches, percent sliders, and number fields as iOS `AssistLongPressChrome`. WAVE hold-without-drag opens options (iOS `WaveformAssist.shouldPresentOptions`). Scope panels copy iOS `ScopeMiniChrome` (0.72 rounded plate, hairline, 16 dp corner, 16 dp shadow) and `WaveformMovablePanel` (0.3 s hold then drag, L-corner 2 dp outside the clip, scale 0.6…1.6). WAVE / PARADE / VECTOR / HISTO paint the plate and traces in one Compose Canvas (iOS `plusLighter` on a `compositingGroup`) — no plot hole, no Kyant on the plates, no lagged Vulkan overlay. WAVE / PARADE density-accumulate into a 250×153 bitmap off the UI thread; VECTOR uses the 128-bin raster; Compose blits. Vulkan grades the picture and downsamples a 213×120 tap on the 10–15 Hz sample tick (not every HEVC frame). Last touched or moved panel stacks on top. Scopes sit above the feed and the focus / tracking box, under the top deck, View Assist bar, and camera-value strip. Feed PixelCopy for HUD Kyant is ~20 Hz. The pinch well is the feed rectangle *under* the panels so a hold on HISTO is not stolen by pinch. Histogram gutters are 17.5 dp (traffic lamps + 0 / 100), not 17.5 px. Zebra 0–255 shows encoded codes via `ScopeDisplayScale.signalNative`; stored thresholds stay 0–100 IRE. PStops reference ruler paints EV-domain bands + Min/−3/18%/Skin/+2/Max markers, not IRE labels. Canvas paints guides/grid/crosshair and scope chrome. Live picture runs on Vulkan (`libopc_vulkan.so`): MediaCodec writes an `ImageReader` AHB. Assists off: one YCbCr blit of the MediaCodec AHB into the well (hardware `c2.qti` / Exynos HEVC, not `c2.android`). LUT / FALSE / ZEBRA add the grade pass; WAVE / HISTO tap at 10–15 Hz. Tools-off no longer histograms 1280×720 or readbacks every frame. Rounded 0.72 plates are Compose `ScopeMiniChrome`. Live HUD liquid glass is Kyant [`AndroidLiquidGlass`](https://github.com/Kyant0/AndroidLiquidGlass) (`io.github.kyant0:backdrop`) when the hardware gate allows it (API 33+ and ≥4 GB RAM, not `isLowRamDevice`). There is no frame-budget demote — FULL stays FULL. Kyant cannot sample a SurfaceView, so FULL glass PixelCopies the feed well into the recorded Compose layer. Older / low-RAM devices stay on solid frost. GLES `FeedEffectsGlProgram` remains the decode fallback when Vulkan cannot init.
- **Operator Setup:** seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System), DJI Black, Sora + IBM Plex, NOTICE legal page. Frame.io is **Not configured** (optional on iOS too).
- **Media:** camera catalog + SoftAP HTTP cache + ExoPlayer/photo viewer + system share. Share / Save to Photos caches the original camera file (`MediaHTTP.deliveryPath`). Playback opens the 720p LRF/XRF sidecar even when the 4K original is already cached. Playback chrome is an 82% DJI-black plate (no Kyant); the top row is back + filename + star, not a bar. LUT / PEAK / FALSE / ZEBRA grade the proxy in GLES (ExoPlayer writes an OES surface; TextureView is only the window). WAVE / HISTO tap that GL copy. Overlay assists sit above the player. Live HEVC is held while the library covers the monitor. Playback View Assist rail is independent of live. No Frame.io hop.

- **Camera SETs:** same mailbox as iOS `fireCamera` / `CameraSetMailbox`. ISO, shutter, WB, focus, FORMAT, COLOR, EV, record, tracking fire-and-forget with 300 ms retransmit and a 2 s settle — a missed ACK is not `"Color timed out"` and does not revert the HUD. Native ISO hops D-Log 400 ↔ D-Log2 1600 immediately after the color SET (toggle on the ISO sheet). Audio blobs and tap-focus stay true round-trips (`requestCamera`, 800 ms tap burst) and keep timeouts off the HUD.
- **Zoom:** chip cycles 1× → 3× → 6× → 12× → 1× on slider `0x02/0xB8` `0A 4E` + lens 217 / 651 / 1302 / 2604. The chip number is `CamFov` hybrid (lens `@14`, else inverted `cam_fov` `@0`) — never `@0 / 1024` (12287 is 1×, not 12×). Pinch writes every distinct lens tick at 20 Hz without waiting for ACK (transparent hit well over the Vulkan SurfaceView, iOS `LiveZoomPinchWell`); D-Log2 hops to D-Log on the first step off 1× and restores only when parked back at 1×.
- **Tracking:** long-press then drag on the feed draws a search box and SETs `0x02/0xA6` (centre+size). AF-C face brackets come from a 40 ms RGB tap of the live picture (`android.media.FaceDetector`, iOS Vision). Tap a bracket to start ActiveTrack. The camera pushes the locked subject on `0x02/0x89`; we poll `0xA5` until idle. Green cancel X and focus-reset match iOS.

Skip / later: VideoToolbox, MetalFX super-res, iOS 26 Liquid Glass API, Frame.io OAuth, LEVEL/De-SQ/MAG.

OpenZCine Android patterns adopted (not Nikon PTP/USB/Wear/OCR):

- Keystore AES/GCM Wi-Fi password store (`CameraWifiCredentialStore`)
- `WIFI_MODE_FULL_LOW_LATENCY` lock while live
- In-app-gated operator haptics
- AAR `compileSdk` 37 metadata gate disabled so the project stays on SDK 36
- Shared `CubeLUT` packer (`LUTLibraryWire`) for GLES-ready RGBA cubes
- GLES ES2 feed-effect shaders under `assets/shaders/`. MediaCodec writes an OES `SurfaceTexture`; `LiveFeedEffectsSession` blits to 2D and runs `FeedEffectsGlProgram` into the TextureView (Kyant can still sample the picture).
- Media cache complete-at-exact-length + `noBackupFilesDir`
- Sticky `ACTION_BATTERY_CHANGED` readout instead of a 1 Hz poll
