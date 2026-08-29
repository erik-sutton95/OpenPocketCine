import CoreMedia
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class EncoderFormatChangeTests: XCTestCase {
    func testSameRasterSpsDoesNotHoldIDR() {
        let decoder = HevcDecoder()
        var fired = 0
        decoder.onParameterSetsChanged = { fired += 1 }

        _ = decoder.decode(accessUnit: Self.annexB([Self.vps, Self.sps, Self.pps]))
        XCTAssertEqual(fired, 0)
        XCTAssertTrue(decoder.hasFormat)
        XCTAssertGreaterThan(decoder.pictureSize.width, 1)

        var flippedSPS = Self.sps
        flippedSPS[flippedSPS.count - 1] ^= 0x01
        _ = decoder.decode(accessUnit: Self.annexB([Self.vps, flippedSPS, Self.pps]))
        XCTAssertEqual(
            fired, 0, "same-raster SPS is zoom/FORMAT — not a GOP reset")
        XCTAssertFalse(
            decoder.awaitingIDR,
            "holding IDR without 0x09/0xa8 blacks the well while HUD/gimbal stay up")
    }

    func testIdenticalParameterSetsDoNotRetrigger() {
        let decoder = HevcDecoder()
        var fired = 0
        decoder.onParameterSetsChanged = { fired += 1 }
        let au = Self.annexB([Self.vps, Self.sps, Self.pps])
        _ = decoder.decode(accessUnit: au)
        _ = decoder.decode(accessUnit: au)
        XCTAssertEqual(fired, 0)
    }

    func testNewParameterSetsWithIDRDoNotRequestEnable() {
        let decoder = HevcDecoder()
        var fired = 0
        decoder.onParameterSetsChanged = { fired += 1 }
        _ = decoder.decode(accessUnit: Self.annexB([Self.vps, Self.sps, Self.pps]))

        var flippedSPS = Self.sps
        flippedSPS[flippedSPS.count - 1] ^= 0x01
        // Pocket IDR_N_LP (type 20) — the camera already cut this GOP.
        let idr: [UInt8] = [0x28, 0x01]
        _ = decoder.decode(accessUnit: Self.annexB([Self.vps, flippedSPS, Self.pps, idr]))
        XCTAssertEqual(fired, 0, "second 0x09/0xa8 on an IDR AU hangs the hold")
    }

    func testLivePresentTimingDoesNotPaceAtThirtyFps() {
        let timing = LiveViewPresentTiming.sampleTiming(frameIndex: 1)
        XCTAssertEqual(timing.duration.timescale, 60_000)
        XCTAssertEqual(timing.presentationTimeStamp.timescale, 60_000)
        XCTAssertNotEqual(timing.duration.timescale, 30)
        let seconds = CMTimeGetSeconds(timing.duration)
        XCTAssertLessThan(seconds, 1.0 / 50.0)
    }

    private static func annexB(_ nals: [[UInt8]]) -> [UInt8] {
        nals.flatMap { [0, 0, 1] + $0 }
    }

    // Real Pocket live-view sets from `HevcTests`.
    private static let vps = hex(
        "40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
    private static let sps = hex(
        "42010121600000030000030000030000030096a00280802d17aeedc9ae5d4d404040410000030001000003001908"
    )
    private static let pps = hex("4401c17312240890")
}

private func hex(_ s: String) -> [UInt8] {
    var out = [UInt8]()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}
