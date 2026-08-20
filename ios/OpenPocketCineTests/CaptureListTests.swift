import XCTest
@testable import OpenPocketCine
import OpenPocketViewCore

final class CaptureListTests: XCTestCase {
    func testShutterWheelUsesCameraListNotHardcoded24pTable() {
        var status = CameraStatus()
        status.fps = 60
        status.shutterDenom = 50
        status.availableShutterDenoms = CamCapShutter.parseDenoms(Self.shutter60p)

        let denoms = CaptureLists.shutterDenoms(from: status)
        XCTAssertTrue(denoms.contains(50), "4K 60p payload includes 1/50")
        XCTAssertFalse(denoms.contains(25), "60p payload does not offer 1/25")
        XCTAssertEqual(denoms, status.availableShutterDenoms)
        XCTAssertFalse(denoms.contains(13), "wheel cannot invent a 24p-only stop")
    }

    func testShutterWheelOmitsSpeedsMissingFromPayload() {
        var status = CameraStatus()
        status.fps = 25
        status.shutterDenom = 50
        status.availableShutterDenoms = CamCapShutter.parseDenoms(Self.shutter25p)

        let denoms = CaptureLists.shutterDenoms(from: status)
        let other = CamCapShutter.parseDenoms(Self.shutter60p)
        XCTAssertNotEqual(denoms, other)
        XCTAssertTrue(denoms.contains(25))
        XCTAssertTrue(denoms.contains(50))
        for extra in [13, 15, 20, 125, 250, 10_000, 13_000] {
            XCTAssertFalse(denoms.contains(extra), "do not offer 1/\(extra) — not in payload")
        }
    }

    func testIsoWheelUsesCamcapAndStarsBaseForTransfer() {
        var dlog2 = CameraStatus()
        dlog2.colorMode = .dLog2
        dlog2.availableIsoIndices = CamCapIso.parseIndices(Self.isoDLog2)
        XCTAssertEqual(
            CaptureLists.isoDrumLabels(from: dlog2),
            ["100", "200", "400", "800", "1600", "3200"])
        XCTAssertEqual(CaptureLists.isoDrumLabels(from: dlog2), dlog2.availableIsoIndices.map(\.label))
        XCTAssertEqual(CaptureLists.isoMarkedLabels(from: dlog2), ["1600"])
        XCTAssertEqual(dlog2.monitorTransfer, .dlog2)

        var dlog = CameraStatus()
        dlog.colorMode = .dLog
        dlog.availableIsoIndices = CamCapIso.parseIndices(Self.isoDLog)
        XCTAssertEqual(CaptureLists.isoDrumLabels(from: dlog), dlog.availableIsoIndices.filter { $0 != .auto }.map(\.label))
        XCTAssertEqual(CaptureLists.isoMarkedLabels(from: dlog), ["400"])
        XCTAssertFalse(CaptureLists.isoMarkedLabels(from: dlog).contains("1600"))

        var rec709 = CameraStatus()
        rec709.colorMode = .normal
        rec709.availableIsoIndices = dlog2.availableIsoIndices
        XCTAssertTrue(CaptureLists.isoMarkedLabels(from: rec709).isEmpty)
        XCTAssertEqual(CaptureLists.isoDrumLabels(from: rec709), CaptureLists.isoDrumLabels(from: dlog2))
    }

    func testIsoStarFollowsStatusTransferNotTeleHopGuess() {
        var status = CameraStatus()
        status.colorMode = .dLog2
        XCTAssertEqual(CaptureLists.isoMarkedLabels(from: status), ["1600"])
        status.colorMode = .dLog
        XCTAssertEqual(
            CaptureLists.isoMarkedLabels(from: status), ["400"],
            "star follows status.monitorTransfer after the body reports D-Log")
        XCTAssertEqual(CamFov.colorMode(forZoom: 3, current: .dLog2), .dLog)
        status.colorMode = .dLog2
        XCTAssertEqual(
            CaptureLists.isoMarkedLabels(from: status), ["1600"],
            "zoom tele hop guess must not flip the star while status is still D-Log2")
    }

    func testNativeIsoHopCopy() {
        XCTAssertEqual(CaptureLists.nativeIsoHopTitle, "Auto Native ISO")
        XCTAssertFalse(CaptureLists.nativeIsoHopHelp.isEmpty)
        XCTAssertFalse(CaptureLists.nativeIsoHopHelp.contains("400 ↔ 1600"))
    }

    func testDLog2HasNoIsoAuto() {
        var status = CameraStatus()
        status.colorMode = .dLog2
        XCTAssertFalse(ColorMode.dLog2.offersIsoAuto)
        XCTAssertTrue(ColorMode.dLog2.isoAutoLimits.isEmpty)
        XCTAssertTrue(ColorMode.dLog2.isoAutoLabels.isEmpty)
        XCTAssertFalse(ColorMode.dLog2.isoIndices.contains(.auto))
        XCTAssertFalse(CaptureLists.offersIsoAuto(from: status))
        XCTAssertTrue(CaptureLists.isoAutoLabels(from: status).isEmpty)
    }

    func testDLogIsoAutoRanges() {
        var status = CameraStatus()
        status.colorMode = .dLog
        XCTAssertEqual(
            CaptureLists.isoAutoLabels(from: status),
            ["400–800", "400–1600", "400–3200", "400–6400"])
        XCTAssertEqual(ColorMode.dLog.isoAutoLimits.map(\.rawValue), [0x04, 0x05, 0x06, 0x07])
        XCTAssertEqual(CaptureLists.isoLimit(from: "400–1600", status: status), .max1600)
        XCTAssertTrue(CaptureLists.offersIsoAuto(from: status))
    }

    func testNormalAndHdrIsoAutoRanges() {
        let expected = [
            "100–200", "100–400", "100–800", "100–1600",
            "100–3200", "100–6400", "100–12800", "100–25600",
        ]
        var normal = CameraStatus()
        normal.colorMode = .normal
        var hdr = CameraStatus()
        hdr.colorMode = .hdr
        XCTAssertEqual(CaptureLists.isoAutoLabels(from: normal), expected)
        XCTAssertEqual(CaptureLists.isoAutoLabels(from: hdr), expected)
        XCTAssertEqual(CaptureLists.isoLimit(from: "100–800", status: normal), .max800)
        XCTAssertEqual(CaptureLists.isoLimit(from: "100–25600", status: hdr), .max25600)
        XCTAssertEqual(IsoLimit.max200.rawValue, 0x02)
        XCTAssertEqual(IsoLimit.max400.rawValue, 0x03)
        XCTAssertEqual(IsoLimit.max3200.rawValue, 0x06)
        XCTAssertEqual(IsoLimit.max12800.rawValue, 0x08)
    }

    func testEvLabelsThirdStopsFromMinus3ToPlus3() {
        let labels = CaptureLists.evLabels
        XCTAssertEqual(labels.count, 19)
        XCTAssertEqual(labels.first, "\(EvComp.minusSign)3.0")
        XCTAssertEqual(labels.last, "+3.0")
        XCTAssertTrue(labels.contains("0.0"))
        XCTAssertTrue(labels.contains("\(EvComp.minusSign)1.3"))
        XCTAssertTrue(labels.contains("+0.7"))
        XCTAssertTrue(labels.contains("+1.0"))
        XCTAssertEqual(EvComp(label: "\(EvComp.minusSign)3.0")?.rawValue, 0x07)
        XCTAssertEqual(EvComp(label: "0.0")?.rawValue, 0x10)
        XCTAssertEqual(EvComp(label: "+3.0")?.rawValue, 0x19)
        XCTAssertEqual(labels, [
            "\(EvComp.minusSign)3.0", "\(EvComp.minusSign)2.7", "\(EvComp.minusSign)2.3",
            "\(EvComp.minusSign)2.0", "\(EvComp.minusSign)1.7", "\(EvComp.minusSign)1.3",
            "\(EvComp.minusSign)1.0", "\(EvComp.minusSign)0.7", "\(EvComp.minusSign)0.3",
            "0.0",
            "+0.3", "+0.7", "+1.0", "+1.3", "+1.7", "+2.0", "+2.3", "+2.7", "+3.0",
        ])
    }

    func testShutterAngleLadderIsCalculatedNotCaptured() {
        XCTAssertEqual(ShutterAngle.labels.first, "5.6°")
        XCTAssertEqual(ShutterAngle.labels.last, "360°")
        XCTAssertEqual(ShutterAngle.denom(degrees: 180, fps: 24), 48)
        XCTAssertEqual(ShutterAngle.denom(degrees: 180, fps: 24, available: [25, 50, 100]), 50)
        XCTAssertEqual(ShutterAngle.nearestLabel(denom: 48, fps: 24), "180°")
    }

    func testEmptyCapListShowsOnlyCurrent() {
        var status = CameraStatus()
        status.shutterDenom = 80
        XCTAssertEqual(CaptureLists.shutterDenoms(from: status), [80])
        XCTAssertEqual(CaptureLists.shutterLabels(from: status), ["1/80"])
    }

    private static let shutter25p = hex(
        "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
    )
    private static let shutter60p = hex(
        "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"
    )
    private static let isoDLog2: [UInt8] = [0x01, 0x08, 0x00, 0x00, 0x06, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    private static let isoDLog: [UInt8] = [0x01, 0x08, 0x00, 0x00, 0x06, 0x00, 0x05, 0x06, 0x07, 0x08, 0x09]

    private static func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map {
            let i = s.index(s.startIndex, offsetBy: $0)
            return UInt8(s[i..<s.index(i, offsetBy: 2)], radix: 16)!
        }
    }
}
