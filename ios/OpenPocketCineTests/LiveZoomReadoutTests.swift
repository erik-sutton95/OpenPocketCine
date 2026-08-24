import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Chip copy: operator 1×/3×/12× from the labeled Mimo pinch. Tele at 3.0×.
final class LiveZoomReadoutTests: XCTestCase {
    func testCamFov12287IsOneX() {
        XCTAssertEqual(CamFov.factor(raw: 12_287), 1, accuracy: 0.01)
        XCTAssertEqual(CamFov.displayLabel(raw: 12_287), "1×")
        XCTAssertEqual(
            CamFov.displayLabel(
                factor: CamFov.readout(live: CamFov.factor(raw: 12_287), preview: nil, fallback: 12)
            ),
            "1×"
        )
        var status = CameraStatus()
        status.zoomFactorRaw = 12_287
        XCTAssertEqual(status.zoomFactor ?? 0, 1, accuracy: 0.01)
    }

    func testChipFollowsCamFovTenths() {
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 2.29, preview: nil, fallback: 1)),
            "2.3×")
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 5.36, preview: nil, fallback: 1)),
            "5.4×")
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 2.9, preview: nil, fallback: 1)),
            "2.9×")
    }

    func testPinchPreviewWinsUntilLift() {
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 2.29, preview: 5.3, fallback: 1)),
            "5.3×")
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 2.29, preview: nil, fallback: 1)),
            "2.3×")
    }

    func testChipIsCameraTruthNotOptimisticGuess() {
        XCTAssertEqual(CamFov.readout(live: 1, preview: nil, fallback: 12), 1)
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 8, preview: nil, fallback: 1)), "8×")
        XCTAssertEqual(
            CamFov.displayLabel(factor: CamFov.readout(live: 1, preview: nil, fallback: 3)), "1×")
    }

    func testWideJustUnderTeleStillCyclesToThree() {
        XCTAssertEqual(CamFov.nextJump(from: 2.89), 3)
        XCTAssertEqual(CamFov.nextJump(from: 2.9), 3)
        XCTAssertEqual(CamFov.nextJump(from: 3), 6)
        XCTAssertEqual(CamFov.nextJump(from: 6), 12)
    }

    func testChipWritesNativeStops() {
        XCTAssertEqual(CamFov.chipWrite(forJump: 1), .lens(CamFov.lens1x))
        XCTAssertEqual(CamFov.chipWrite(forJump: 3), .lens(CamFov.lens3x))
        XCTAssertEqual(CamFov.chipWrite(forJump: 6), .lens(CamFov.lens6x))
        XCTAssertEqual(CamFov.chipWrite(forJump: 12), .lens(CamFov.lens12x))
        XCTAssertEqual(Commands.setZoomLens(CamFov.lens6x).payload, [0x0A, 0x4E, 0x16, 0x05])
        XCTAssertEqual(Commands.setZoomSlew(CamFov.slewTele).payload, [0x03, 0x00, 0x64, 0x00])
        XCTAssertEqual(Commands.setZoomSlew(CamFov.slewWide).payload, [0x03, 0x00, 0x2C, 0x01])
        XCTAssertEqual(Commands.setZoomLens(CamFov.lens1x).payload, [0x0A, 0x4E, 0xD9, 0x00])
        XCTAssertEqual(Commands.setZoomLens(CamFov.lens3x).payload, [0x0A, 0x4E, 0x8B, 0x02])
        XCTAssertEqual(Commands.setZoomLens(CamFov.lens12x).payload, [0x0A, 0x4E, 0x2C, 0x0A])
    }

    func testPinchSliderTargetsHybridTenths() {
        XCTAssertEqual(CamFov.pinchLens(for: 2.2), 477)
        XCTAssertEqual(CamFov.pinchLens(for: 6.7), 1454)
        XCTAssertEqual(CamFov.pinchFactor(anchor: 2.3, magnification: 1.1), 2.53, accuracy: 0.001)
        XCTAssertEqual(CamFov.pinchPreview(anchor: 2.3, magnification: 1.1), 2.5)
        XCTAssertNotEqual(CamFov.pinchLens(for: 2.53), CamFov.pinchLens(for: 2.5))
        XCTAssertNotEqual(CamFov.pinchLens(for: 2.15), CamFov.pinchLens(for: 2.16))
        XCTAssertEqual(Commands.setZoom(factor: 2.2).payload, [0x0A, 0x4E, 0xDD, 0x01])
        XCTAssertEqual(Commands.setZoom(factor: 6.7).payload, [0x0A, 0x4E, 0xAE, 0x05])
        XCTAssertEqual(CamFov.displayTenths(2.16), 2.2)
        XCTAssertEqual(CamFov.displayTenths(6.74), 6.7)
    }

    func testTeleEngagesAtThreeNotTwoNine() {
        XCTAssertEqual(CamFov.snapHybrid(2.89), 2.89, accuracy: 0.001)
        XCTAssertEqual(CamFov.snapHybrid(2.9), 2.9, accuracy: 0.001)
        XCTAssertEqual(CamFov.displayTenths(2.9), 2.9)
        XCTAssertEqual(CamFov.displayLabel(factor: 2.9), "2.9×")
        XCTAssertTrue(CamFov.usesTelephoto(3))
        XCTAssertFalse(CamFov.usesTelephoto(2.9))
        XCTAssertFalse(CamFov.usesTelephoto(2.89))
        XCTAssertEqual(CamFov.colorMode(forZoom: 1.1, current: .dLog2), .dLog)
        XCTAssertEqual(CamFov.colorMode(forZoom: 2.9, current: .dLog2), .dLog)
        XCTAssertEqual(CamFov.colorMode(forZoom: 3, current: .dLog2), .dLog)
        XCTAssertNil(CamFov.colorMode(forZoom: 1, current: .dLog2))
        XCTAssertTrue(
            CamFov.zoomNeedsColorHopWhileRecording(
                factor: 3, current: .dLog2, isRecording: true))
        XCTAssertFalse(
            CamFov.zoomNeedsColorHopWhileRecording(
                factor: 3, current: .dLog, isRecording: true))
        XCTAssertFalse(
            CamFov.zoomNeedsColorHopWhileRecording(
                factor: 3, current: .dLog2, isRecording: false))
        XCTAssertTrue(CamFov.shouldRestoreDLog2(factor: 1))
        XCTAssertFalse(CamFov.shouldRestoreDLog2(factor: 2.9))
    }

    func testPinchSendsDistinctTenthsThroughTele() {
        XCTAssertEqual(CamFov.pinchPreview(anchor: 1, magnification: 2.9), 2.9)
        XCTAssertEqual(CamFov.pinchPreview(anchor: 1, magnification: 3), 3)
        XCTAssertEqual(CamFov.pinchPreview(anchor: 1, magnification: 3.1), 3.1)
        XCTAssertNotEqual(CamFov.pinchLens(for: 2.9), CamFov.pinchLens(for: 3))
        var last: UInt16?
        for tenth in 10...120 {
            let factor = Double(tenth) / 10
            let lens = CamFov.pinchLens(for: factor)
            if let last {
                XCTAssertGreaterThan(lens, last, "\(factor)× lens must advance toward 12×")
            }
            last = lens
        }
    }

    func testPinchUsesSliderBelowDetentAndSlewAbove() {
        XCTAssertEqual(
            CamFov.pinchCommand(live: 2.3, preview: 4.1, slewing: nil),
            .slider(CamFov.pinchLens(for: 4.1))
        )
        XCTAssertEqual(
            CamFov.pinchCommand(live: 12, preview: 10.2, slewing: nil),
            .slider(CamFov.pinchLens(for: 10.2))
        )
        XCTAssertEqual(
            CamFov.pinchCommand(live: 9.2, preview: 11.5, slewing: nil),
            .slider(CamFov.pinchLens(for: 11.5))
        )
    }
}
