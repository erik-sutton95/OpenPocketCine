# Android — sharing Swift the OpenZCine way

OpenPocketCine’s Android app lives in this repository (`Apps/Android/`,
`Sources/OpenPocketCineAndroidFacade/`). It is **not on Google Play yet**. The
closed-beta waitlist is on [openpocketcine.app](https://openpocketcine.app/). iOS
is the daily driver.

Business logic stays in **`OpenPocketViewCore`** (UI-free, I/O-free Foundation).
Android follows the public [OpenZCine](https://github.com/erik-sutton95/OpenZCine)
pattern rather than Skip/SKIE/an xcframework.

Operator-visible behavior lives in [`docs/PARITY.md`](docs/PARITY.md). Live UDP
and decoder invariants live in [`docs/live-session.md`](docs/live-session.md).
This file is the Android build and I/O notes that implement those rows.

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

## Android I/O notes

How this shell implements [`docs/PARITY.md`](docs/PARITY.md). Contract language stays there.

### Connection

`bindProcessToNetwork` then UDP `0.0.0.0:0` after `Network.bindSocket`. MediaCodec
uses wall-clock PTS and `KEY_LOW_LATENCY`; do not pace at 30 fps. Cached Wi-Fi
creds sit in private prefs, not saved-camera JSON. `holdsMonitor` must not latch
a forever skip after a SoftAP flap.

### Live picture

Vulkan (`libopc_vulkan.so`) when init succeeds: MediaCodec → `ImageReader`
AHardwareBuffer → YCbCr blit at the feed well. GLES `FeedEffectsGlProgram` on
`GL_TEXTURE_EXTERNAL_OES` is the fallback.

### HUD glass

Kyant `AndroidLiquidGlass` on API 33+ / ≥4 GB devices that are not
`isLowRamDevice`. FULL stays FULL (no frame-budget demote). Kyant cannot sample
a SurfaceView, so FULL glass PixelCopies the feed well at ~20 Hz. Pairing,
Operator Setup, and media list rows stay solid fills.

### Assists GPU

Assists-off is one YCbCr blit of the MediaCodec AHB (hardware `c2.qti` / Exynos
HEVC, not `c2.android`). LUT / FALSE / ZEBRA add the grade pass. WAVE / PARADE /
VECTOR / HISTO tap a 200-wide downsample (213×120 on 720p) at 25 Hz
(10 Hz with three or more scopes) and paint in Compose Canvas.
WAVE / PARADE accumulate into a 250×153 bitmap off the UI thread; VECTOR uses
the 128-bin raster.

### Media decode

Playback grades the 720p LRF/XRF proxy in GLES (ExoPlayer → OES → TextureView).
Share / Save to Photos caches the original (`MediaHTTP.deliveryPath`).

## OpenZCine Android patterns adopted

Not Nikon PTP/USB/Wear/OCR:

- Keystore AES/GCM Wi-Fi password store (`CameraWifiCredentialStore`)
- `WIFI_MODE_FULL_LOW_LATENCY` lock while live
- In-app-gated operator haptics
- AAR `compileSdk` 37 metadata gate disabled so the project stays on SDK 36
- Shared `CubeLUT` packer (`LUTLibraryWire`) for GLES-ready RGBA cubes
- GLES ES2 feed-effect shaders under `assets/shaders/`
- Media cache complete-at-exact-length + `noBackupFilesDir`
- Sticky `ACTION_BATTERY_CHANGED` readout instead of a 1 Hz poll
