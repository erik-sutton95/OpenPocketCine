# Android next — sharing Swift the OpenZCine way

OpenPocketCine’s iOS pass keeps business logic in **`OpenPocketViewCore`** (UI-free, I/O-free Foundation). Android is **not** in this pass. When it is, copy OpenZCine’s pattern rather than Skip/SKIE/an xcframework.

## What OpenZCine actually does

Source: the public [OpenZCine](https://github.com/erik-sutton95/OpenZCine) repository.

1. **Portable Swift core** — `Sources/OpenZCineCore/` never imports SwiftUI, UIKit, or Android.
2. **Android JNI facade** — `Sources/OpenZCineAndroidFacade/` owns the session that talks to the camera on Android, plus hand-written `@_cdecl` JNI shims (`SwiftCoreJNI.swift`). A header-only `CJNI` target exposes NDK `<jni.h>` on Android only.
3. **Cross-compile, don’t SPM-link** — Gradle task `:app:stageSwiftCore` (`just android-core`, `scripts/android-stage-swift-core.sh`) builds `aarch64-unknown-linux-android29` and stages `libOpenZCineAndroid.so` plus the Swift runtime `.so` closure into generated jniLibs. **arm64-v8a only.** Toolchain pin: Swift **6.3.3** + `swift-6.3.3-RELEASE_android`.
4. **Kotlin seam** — `Apps/Android/core-api` defines `CameraSession` / `CameraIdentity` interfaces. The Compose app implements them with `SwiftCoreCameraSession` over JNI. Kotlin does not pack protocol bytes.
5. **Same applicationId as iOS bundle** on OpenZCine (`com.opencapture.openzcine`). Design tokens are duplicated as floats in `Theme.kt` / `pairing/StartupDesign.kt` so connection screens match.

iOS links the core via Swift Package Manager. Android does **not** consume that SPM product at runtime — only the cross-compiled `.so`.

## What we will copy for OpenPocketCine

| Piece | Pocket equivalent |
| --- | --- |
| `OpenZCineCore` | Keep `OpenPocketViewCore` (DUML, HEVC depacketizer, saved-camera records, connection phase). Rename the module later if we want `OpenPocketCineCore`. |
| `OpenZCineAndroidFacade` | New `OpenPocketCineAndroidFacade`: BLE/Wi-Fi/UDP session that calls the core, JNI surface for scan/connect/live-frame callbacks. |
| `core-api` | Kotlin `CameraSession` wrapping the facade. |
| Compose shell | Splash + saved cameras + OSMO connection wizard using the **same** `StartupColors` / `BrandColors` floats as iOS. |
| Saved cameras | `SharedPreferences` file `openpocketcine.saved-cameras`, key `records-json`. Wi-Fi passwords stay out of prefs (re-read over BLE, same as iOS this pass). |
| applicationId | `com.opencapture.openpocketcine` on iOS and Android (OpenZCine’s `com.opencapture.openzcine` pattern). |

## Do not copy from OpenZCine Android

Nikon PTP-IP, AccessorySetupKit / `NIKON_ZR_*` SSIDs, multi-setup path chips, OCR SSID scanner, USB-C/HDMI paths, monitor assist tools.

## First Android milestone

Done in-tree (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)):

1. Same Swift Android SDK pin OpenZCine uses (6.3.3).
2. `OpenPocketCineAndroidFacade` + `CJNI` in `Package.swift` (`#if os(Android)` JNI).
3. Gradle `:app:stageSwiftCore` stages `libOpenPocketCineAndroid.so`.
4. Compose splash → empty-store wizard / saved list → live HEVC (MediaCodec) using enable-once + ACK pump.
