import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class CaptureQuickSnapshotTests: XCTestCase {
    func testUnknownCameraValuesStayUnknownAndStationaryHoldCannotSelectTheirFallback() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        let ev = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        let wb = try XCTUnwrap(CaptureQuickSnapshot.primary(.wb, status: status))
        let focus = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
        for snapshot in [ev, wb, focus] {
            XCTAssertEqual(snapshot.selection, "")
            XCTAssertNil(
                MonitorDrumSelection.changedIndex(
                    origin: snapshot.index, translation: 0, count: snapshot.options.count))
            XCTAssertNil(
                MonitorDrumSelection.changedIndex(
                    origin: snapshot.index, translation: -3, count: snapshot.options.count))
        }
        XCTAssertEqual(ev.options[ev.index], "0.0", "A visual fallback is not camera truth")
        XCTAssertEqual(wb.options[wb.index], "Auto")
        XCTAssertEqual(focus.options[focus.index], "AF-S")
    }

    func testKnownValuesAndFocusCapabilityRemainAuthoritative() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        status.evComp = .zero
        status.focusMode = .continuous
        status.whiteBalance = .auto
        XCTAssertEqual(CaptureQuickSnapshot.primary(.shutter, status: status)?.selection, "0.0")
        XCTAssertEqual(CaptureQuickSnapshot.primary(.wb, status: status)?.selection, "Auto")
        XCTAssertEqual(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true)?
                .selection,
            "AF-C")
        XCTAssertNil(CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: false))
        let automatic = try XCTUnwrap(
            CaptureQuickSnapshot.primary(
                .shutter, status: status, facePriorityExposureEnabled: true))
        XCTAssertFalse(automatic.enabled)
    }
}
