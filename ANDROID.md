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

- **Connection:** BLE → SoftAP → UDP datalink, FeedWatchdog-style enable policy (never 1 Hz `0x09/0xa8`), session recovery that holds the last frame, Nano AVC + Pocket HEVC via MediaCodec 720p, cached Wi-Fi creds in private prefs (not saved-camera JSON).
- **Live chrome:** landscape/portrait layout metrics matching iOS (`LiveDesign`), DISP 1/2 maps, chrome editor, record confirmation, zoom chip, gimbal recenter/flip, capture sheets (ISO/shutter angle/EV/WB/focus/audio/format/color).
- **Assists:** toolbar 1:1 (LUT, PEAK, FALSE, ZEBRA, WAVE, PARADE, HISTO, VECTOR, LIGHTS, AUDIO, GUIDES, GRID, CROSS, MIRROR). Canvas paints guides/grid/crosshair/scope panels. LUT / PEAK / FALSE / ZEBRA paint on the live HEVC picture through GLES (`FeedEffectsGlProgram` on `GL_TEXTURE_EXTERNAL_OES`); 50/50 split follows `assist.splitComparison`. WAVE / PARADE / HISTO / VECTOR / LIGHTS traces still wait on JNI LiveColorScience samples.
- **Operator Setup:** seven tabs (Link, Sharing, View Assist, Controls, Display, Storage, System), DJI Black, Sora + IBM Plex, NOTICE legal page. Frame.io is **Not configured** (optional on iOS too).
- **Media:** camera catalog + SoftAP HTTP cache + ExoPlayer/photo viewer + system share. Playback View Assist rail (independent of live) and HFR conform preview; GPU LUT/peaking/zebra on the clip is still AGSL follow-up. No Frame.io hop.

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
