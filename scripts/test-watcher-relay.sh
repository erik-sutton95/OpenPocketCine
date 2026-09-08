#!/usr/bin/env bash
# Compile the actual Apple relay shell on macOS for deterministic transport load tests.
set -euo pipefail
relay_root="$(cd "$(dirname "$0")/.." && pwd)"
relay_harness="$relay_root/.build/watcher-relay-tests"
mkdir -p "$relay_harness/Sources/WatcherRelayShell" "$relay_harness/Tests"
for source in "$relay_root"/ios/OpenPocketCine/WatcherRelay{Host,Encoder,Reader}.swift; do
    ln -sf "$source" "$relay_harness/Sources/WatcherRelayShell/$(basename "$source")"
done
ln -sfn "$relay_root/Tests/WatcherRelayShellTests" "$relay_harness/Tests/WatcherRelayShellTests"
cat > "$relay_harness/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WatcherRelayHarness", platforms: [.macOS(.v14)],
    dependencies: [.package(name: "PocketCore", path: "../..")],
    targets: [
        .target(name: "WatcherRelayShell", dependencies: [
            .product(name: "OpenPocketViewCore", package: "PocketCore")]),
        .testTarget(name: "WatcherRelayShellTests", dependencies: ["WatcherRelayShell"])
    ], swiftLanguageModes: [.v5])
PACKAGE
swift test --package-path "$relay_harness"
