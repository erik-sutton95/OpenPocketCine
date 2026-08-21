// swift-tools-version: 6.0
import PackageDescription

// The portable, UI-free, I/O-free core for OpenPocketCine: DUML framing, UDP datalink
// byte math, BLE advert decode, command builders, status decode, and saved-camera
// records. Pure Foundation, so it builds and tests natively on macOS (`swift test`)
// without a device. The iOS app (ios/) imports this and supplies CoreBluetooth /
// Network / Hotspot I/O. Android consumes the same target via a JNI facade
// (`just android-core`) — keep this module UI-free and platform-agnostic.
let package = Package(
    name: "OpenPocketViewCore",
    platforms: [.iOS(.v17), .macOS(.v12)],
    products: [
        .library(name: "OpenPocketViewCore", targets: ["OpenPocketViewCore"]),
        // JNI facade consumed by the Android app (`just android-core`). The JNI
        // shims are `#if os(Android)`-gated; on Darwin only the wire helpers
        // compile, so iOS/macOS behavior is unchanged.
        .library(
            name: "OpenPocketCineAndroid", type: .dynamic, targets: ["OpenPocketCineAndroidFacade"]),
    ],
    targets: [
        .target(name: "OpenPocketViewCore"),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            dependencies: ["OpenPocketViewCore"],
            exclude: ["Fixtures"]
        ),
        // Header-only shim exposing the NDK's <jni.h> to Swift; empty on Darwin.
        .target(name: "CJNI"),
        .target(
            name: "OpenPocketCineAndroidFacade",
            dependencies: ["OpenPocketViewCore", "CJNI"]
        ),
        .testTarget(
            name: "OpenPocketCineAndroidFacadeTests",
            dependencies: ["OpenPocketCineAndroidFacade", "OpenPocketViewCore"]
        ),
    ]
)
