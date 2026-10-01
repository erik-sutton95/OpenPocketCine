// swift-tools-version: 6.0
import PackageDescription

// The portable, UI-free, I/O-free core for OpenPocketCine: DUML framing, UDP datalink
// byte math, BLE advert decode, command builders, status decode, and saved-camera
// records. Pure Foundation, so it builds and tests natively on macOS (`swift test`)
// without a device. The iOS app (ios/) imports this and supplies CoreBluetooth /
// Network / Hotspot I/O. Android consumes the same target via a JNI facade
// (`just android-core`) — keep this module UI-free and platform-agnostic.
// Shared UI (MonitorPresentation, MonitorUI) comes from the OpenCineUI package,
// consumed by ios/project.yml, not from this manifest.
let package = Package(
    name: "OpenPocketViewCore",
    // macOS 13: OpenCineCore's minimum (host `swift test` only; no macOS app ships).
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
    products: [
        .library(name: "OpenPocketViewCore", targets: ["OpenPocketViewCore"]),
        // JNI facade consumed by the Android app (`just android-core`). The JNI
        // shims are `#if os(Android)`-gated; on Darwin only the wire helpers
        // compile, so iOS/macOS behavior is unchanged.
        .library(
            name: "OpenPocketCineAndroid", type: .dynamic, targets: ["OpenPocketCineAndroidFacade"]),
    ],
    dependencies: [
        // Portable media math (OpenCineMedia). Sibling checkout until OpenCineCore is published.
        .package(path: "../OpenCineCore")
    ],
    targets: [
        .target(
            name: "OpenPocketViewCore",
            dependencies: [.product(name: "OpenCineMedia", package: "OpenCineCore")]
        ),
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
