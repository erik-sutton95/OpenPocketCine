#!/usr/bin/env bash
# Host-only synthetic measurement of the production Android status JSON.
# That codec is DjiNativeWire in the sibling OpenCine package.
# Timing is informational: this does not measure JNI, Kotlin, UI, or phone energy.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
opencine="$(cd "$repo_root/../OpenCine" && pwd)"
if [[ ! -f "$opencine/Package.swift" ]]; then
    printf 'PROBE missing sibling OpenCine at %s\n' "$opencine" >&2
    exit 1
fi
probe_root="$(mktemp -d "${TMPDIR:-/tmp}/opc-status-probe.XXXXXX")"
trap 'rm -rf "$probe_root"' EXIT

mkdir -p "$probe_root/Tests/ProbeTests"

cat > "$probe_root/Package.swift" <<SWIFT
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusProbe",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "$opencine"),
    ],
    targets: [
        .testTarget(
            name: "ProbeTests",
            dependencies: [
                .product(name: "OpenCineDJI", package: "OpenCine"),
                .product(name: "OpenCineDJIAndroid", package: "OpenCine"),
            ]
        ),
    ]
)
SWIFT

cat > "$probe_root/Tests/ProbeTests/ProbeTests.swift" <<'SWIFT'
import Foundation
import XCTest
import OpenCineDJI
import OpenCineDJIAndroid

final class ProbeTests: XCTestCase {
    func testStatusCost() {
        let iterations = 3_000
        let samples = 7
        var initial = CameraStatus()
        initial.batteryPercent = 80
        initial.batteryMilliVolts = 4_100
        initial.storageTotalMb = 128_000
        initial.storageFreeMb = 96_000
        initial.fps = 25
        initial.iso = 100
        initial.shutterDenom = 50
        initial.timecode = "01:02:03:04"
        let json = DjiNativeWire.statusJSON(initial)
        var payload = [UInt8](repeating: 0, count: 34)
        payload[20] = 81
        let battery = Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0,
            cmdSet: 0x0D, cmdId: 0x02, payload: payload)
        let unknown = Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0,
            cmdSet: 0xFE, cmdId: 0xFE, payload: [])

        let restored = DjiNativeWire.status(fromJSON: json)
        XCTAssertEqual(restored.batteryPercent, initial.batteryPercent)
        XCTAssertEqual(restored.storageFreeMb, initial.storageFreeMb)
        XCTAssertEqual(restored.iso, initial.iso)
        XCTAssertEqual(restored.timecode, initial.timecode)
        var recognized = restored
        XCTAssertTrue(CameraStatusDecoder.apply(battery, to: &recognized))
        XCTAssertEqual(recognized.batteryPercent, 81)
        XCTAssertEqual(recognized.storageFreeMb, initial.storageFreeMb)
        var rejected = restored
        XCTAssertFalse(CameraStatusDecoder.apply(unknown, to: &rejected))
        XCTAssertEqual(rejected, restored)

        var sink = 0
        func bench(_ name: String, _ body: () -> Int) {
            for _ in 0..<100 { sink &+= body() }
            var times: [Double] = []
            for _ in 0..<samples {
                let begin = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<iterations { sink &+= body() }
                let elapsed = DispatchTime.now().uptimeNanoseconds - begin
                times.append(Double(elapsed) / Double(iterations) / 1_000)
            }
            let sorted = times.sorted()
            print(
                "PROBE \(name) microseconds_per_op"
                    + " median=\(String(format: "%.3f", sorted[samples / 2]))"
                    + " min=\(String(format: "%.3f", sorted.first!))"
                    + " max=\(String(format: "%.3f", sorted.last!))"
                    + " n=\(iterations) samples=\(samples)")
        }
        print(
            "PROBE platform=\(ProcessInfo.processInfo.operatingSystemVersionString)"
                + " json_utf8_bytes=\(json.utf8.count) mode=Release host_only=true"
                + " excludes_JNI_Kotlin_UI_phone_energy=true")
        bench("pure_status_apply") {
            var state = initial
            CameraStatusDecoder.apply(battery, to: &state)
            return state.batteryPercent
        }
        bench("facade_status_parse") {
            DjiNativeWire.status(fromJSON: json).batteryPercent
        }
        bench("facade_status_serialize") {
            DjiNativeWire.statusJSON(initial).utf8.count
        }
        bench("facade_status_parse_apply_serialize") {
            var state = DjiNativeWire.status(fromJSON: json)
            CameraStatusDecoder.apply(battery, to: &state)
            return DjiNativeWire.statusJSON(state).utf8.count
        }
        bench("unrecognized_parse_before_reject") {
            var state = DjiNativeWire.status(fromJSON: json)
            return CameraStatusDecoder.apply(unknown, to: &state) ? 1 : state.batteryPercent
        }
        // Keep timed results observable without using timing as a pass/fail gate.
        print("PROBE sink=\(sink)")
    }
}
SWIFT

cd "$repo_root"
printf 'PROBE source_commit=%s architecture=%s\n' "$(git -C "$opencine" rev-parse HEAD)" "$(uname -m)"
printf 'PROBE pocket_commit=%s\n' "$(git -C "$repo_root" rev-parse HEAD)"
if git -C "$opencine" diff --quiet HEAD -- \
    Sources/OpenCineDJIAndroid/DjiNativeWire.swift \
    Sources/OpenCineDJI/CameraStatus+DJIWire.swift \
    Sources/OpenCineCameraVocabulary/CameraStatus.swift
then
    printf 'PROBE production_sources_dirty=false\n'
else
    printf 'PROBE production_sources_dirty=true\n'
fi
swift --version
# Keep the quoted path here: forwarding it through just's variadic swift-test
# recipe would expand a temporary directory containing spaces as shell words.
swift test --package-path "$probe_root" --configuration release \
    --filter ProbeTests/testStatusCost
