// swift-tools-version: 6.0
import PackageDescription

// The portable, UI-free, I/O-free core for OpenPocketCine: motion math, feed health and
// incidents, relay framing and saved-camera records. DUML framing, datalink byte math, BLE
// advert decode, command builders and status decode live in the OpenCineDJI package, which
// this module re-exports. Pure Foundation, so it builds and tests natively on macOS
// (`swift test`) without a device. The iOS app (ios/) imports this and supplies
// CoreBluetooth / Network / Hotspot I/O. Android consumes the same target via a JNI facade
// (`just android-core`); keep this module UI-free and platform-agnostic.
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
        .package(path: "../OpenCineCore"),
        // DJI protocol, wire and session code. Sibling checkout until OpenCineDJI is published.
        .package(path: "../OpenCineDJI"),
    ],
    targets: [
        .target(
            name: "OpenPocketViewCore",
            dependencies: [
                .product(name: "OpenCineMedia", package: "OpenCineCore"),
                .product(name: "OpenCineDJI", package: "OpenCineDJI"),
            ]
        ),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            dependencies: ["OpenPocketViewCore"]
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
