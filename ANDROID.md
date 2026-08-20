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
