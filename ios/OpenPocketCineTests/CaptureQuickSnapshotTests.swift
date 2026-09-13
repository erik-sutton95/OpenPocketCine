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

    func testHeldFocusIncludesTheSameTrackingChoicesAndNativeSelectionAsTap() throws {
        var status = CameraStatus()
        for option in FocusOption.allCases {
            status.focusMode = option.focusMode
            status.focusTrack = option.track
            let snapshot = try XCTUnwrap(
                CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
            XCTAssertEqual(snapshot.options, ["AF-S", "AF-C", "Showcase", "Lock", "Priority"])
            XCTAssertEqual(snapshot.selection, CaptureLists.focusOption(from: status)?.chip)
            XCTAssertEqual(snapshot.options[snapshot.index], option.chip)
        }
    }

    func testPreviewOfUnknownValueOnlySelectsAfterCrossingADetentAndCanReturnToUnknown() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        let snapshot = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        var preview = CaptureDrumPresentation(
            id: UUID(), sheet: .shutter, snapshot: snapshot, position: Double(snapshot.index))
        XCTAssertEqual(preview.selection, "")
        for travel in [0.0, -3, -56, 0] {
            preview.position = MonitorDrumSelection.position(
                origin: snapshot.index, translation: travel, count: snapshot.options.count)
            XCTAssertEqual(preview.selection, travel == -56 ? "+0.3" : "")
            XCTAssertEqual(
                snapshot.changedValue(translation: travel, current: snapshot),
                travel == -56 ? "+0.3" : nil)
        }
        XCTAssertEqual(snapshot.selection, "", "A preview cannot become camera truth")
    }

    func testLiftRejectsAChangedSourceOrCapabilityAndUsesOnlyTheFinalDetent() throws {
        var status = CameraStatus()
        status.focusMode = .continuous
        status.focusTrack = .default
        let initial = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
        XCTAssertEqual(initial.changedValue(translation: -56, current: initial), "Showcase")
        XCTAssertNil(initial.changedValue(translation: 0, current: initial))

        status.focusTrack = .subjectLock
        let changed = CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true)
        XCTAssertNil(initial.changedValue(translation: -56, current: changed))
        XCTAssertNil(initial.changedValue(translation: -56, current: nil))

        status.expoMode = .auto
        status.evComp = .zero
        let ev = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        let automatic = CaptureQuickSnapshot.primary(
            .shutter, status: status, facePriorityExposureEnabled: true)
        XCTAssertNil(ev.changedValue(translation: -56, current: automatic))
        XCTAssertNil(automatic?.changedValue(translation: -56, current: automatic))
    }
}
