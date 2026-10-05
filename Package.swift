// swift-tools-version: 6.0
import PackageDescription

// The portable, UI-free, I/O-free core for OpenPocketCine: motion math, feed health and
// incidents, relay framing and saved-camera records. DUML framing, datalink byte math, BLE
// advert decode, command builders and status decode live in the OpenCineDJI package, which
// this module re-exports. Pure Foundation, so it builds and tests natively on macOS
// (`swift test`) without a device. The iOS app (ios/) imports this and supplies
// CoreBluetooth / Network / Hotspot I/O. Android consumes the same target via a JNI facade
// (`just android-core`); keep this module UI-free and platform-agnostic.
// Shared UI (MonitorPresentation, MonitorUI) comes from the OpenCine package,
// consumed by ios/project.yml, not from this manifest.
let package = Package(
    name: "OpenPocketViewCore",
    // macOS 13: OpenCine's minimum (host `swift test` only; no macOS app ships).
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
        // The OpenCine platform package: portable media math (OpenCineMedia), shared gimbal
        // motion (OpenCineMotion), the second-screen relay wire (OpenCineRelay) and the DJI
        // protocol, wire and session code (OpenCineDJI). Sibling checkout pinned in
        // opencine-pins.txt until OpenCine is published.
        .package(path: "../OpenCine"),
    ],
    targets: [
        .target(
            name: "OpenPocketViewCore",
            dependencies: [
                .product(name: "OpenCineMedia", package: "OpenCine"),
                .product(name: "OpenCineMotion", package: "OpenCine"),
                .product(name: "OpenCineRelay", package: "OpenCine"),
                .product(name: "OpenCineDJI", package: "OpenCine"),
                // Saved-camera values (`SavedCamera`) the Wi-Fi guards read (SHELL-02).
                .product(name: "OpenCineCore", package: "OpenCine"),
                // Live chrome layout policy (`MonitorLayoutRegion`, `GimbalCluster`).
                .product(name: "MonitorPresentation", package: "OpenCine"),
            ]
        ),
        .testTarget(
            name: "OpenPocketViewCoreTests",
            dependencies: ["OpenPocketViewCore"]
        ),
        .target(
            name: "OpenPocketCineAndroidFacade",
            dependencies: [
                "OpenPocketViewCore",
                .product(name: "OpenCineCameraVocabulary", package: "OpenCine"),
                .product(name: "OpenCineJNISupport", package: "OpenCine"),
                // The DJI wire natives behind OpenCine's Kotlin DjiNative (linked into this .so).
                .product(name: "OpenCineDJIAndroid", package: "OpenCine"),
            ]
        ),
        .testTarget(
            name: "OpenPocketCineAndroidFacadeTests",
            dependencies: [
                "OpenPocketCineAndroidFacade", "OpenPocketViewCore",
                .product(name: "OpenCineCameraVocabulary", package: "OpenCine"),
            ]
        ),
    ]
)
