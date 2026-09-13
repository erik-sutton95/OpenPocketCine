import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class CaptureQuickSnapshotTests: XCTestCase {
    func testStartingRecordingInvalidatesAnInFlightShootingModeAdjustment() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        let standby = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertTrue(standby.enabled)
        status.isRecording = true
        let recording = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertFalse(recording.enabled)
        XCTAssertNotEqual(standby, recording)
        XCTAssertNil(standby.changedValue(translation: -56, current: recording))
        XCTAssertNil(recording.changedValue(translation: -56, current: recording))
    }

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

    func testFormatColorAndModeSnapshotsMatchTheFullPickerPrimaryDrum() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps24)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24),
            VideoFormat(resolution: .p4K, frameRate: .fps30),
            VideoFormat(resolution: .p1080, frameRate: .fps24),
        ]
        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.options, ["24p", "30p"])
        XCTAssertEqual(format.selection, "24p")
        XCTAssertEqual(format.changedValue(translation: -56, current: format), "30p")
        XCTAssertNil(format.changedValue(translation: 0, current: format))

        status.availableVideoFormats = [VideoFormat(resolution: .p4K, frameRate: .fps24)]
        let narrowed = CaptureQuickSnapshot.primary(.resolution, status: status)
        XCTAssertNil(format.changedValue(translation: -56, current: narrowed))

        status.colorMode = .normal
        status.availableColorModes = [.normal, .hdr, .dLog]
        let color = try XCTUnwrap(CaptureQuickSnapshot.primary(.color, status: status))
        XCTAssertEqual(color.options, ["Normal", "HDR", "D-Log"])
        XCTAssertEqual(color.selection, "Normal")
        XCTAssertEqual(color.changedValue(translation: -56, current: color), "HDR")

        status.availableColorModes = [.normal]
        let colorChanged = CaptureQuickSnapshot.primary(.color, status: status)
        XCTAssertNil(color.changedValue(translation: -56, current: colorChanged))

        status.shootingMode = Int(ShootingMode.video.rawValue)
        let mode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertEqual(mode.options, ShootingMode.allCases.map(\.label))
        XCTAssertEqual(mode.selection, "Video")
        XCTAssertNil(mode.changedValue(translation: 0, current: mode))
        XCTAssertEqual(mode.changedValue(translation: -56, current: mode), "TimeLapse")

        status.shootingMode = Int(ShootingMode.photo.rawValue)
        let photo = CaptureQuickSnapshot.primary(.mode, status: status)
        XCTAssertNil(mode.changedValue(translation: -56, current: photo))

        status.shootingMode = -1
        let unknown = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertEqual(unknown.selection, "")
        XCTAssertNil(unknown.changedValue(translation: 0, current: unknown))
    }

    func testTopFullPickerSwitchesDirectlyToLowerControlAndViceVersa() {
        XCTAssertTrue(
            CaptureReadoutAdmission.canBegin(
                locked: false, sessionLocked: false, sceneActive: true, operatorPanel: false))
        XCTAssertFalse(
            CaptureReadoutAdmission.canBegin(
                locked: true, sessionLocked: false, sceneActive: true, operatorPanel: false))
        XCTAssertTrue(CaptureReadoutAdmission.canCommit(canBegin: true, captureSheet: nil))
        XCTAssertFalse(
            CaptureReadoutAdmission.canCommit(canBegin: true, captureSheet: .resolution),
            "A delayed SET cannot outlive a still-open persistent picker")
        XCTAssertEqual(CaptureReadoutAdmission.replacing(nil, with: .resolution), .resolution)
        XCTAssertEqual(
            CaptureReadoutAdmission.replacing(.resolution, with: .iso), .iso,
            "FORMAT details yield to a lower ISO tap")
        XCTAssertEqual(
            CaptureReadoutAdmission.replacing(.iso, with: .color), .color,
            "A lower picker yields to a top COLOR tap")
        XCTAssertNil(CaptureReadoutAdmission.replacing(.iso, with: .iso))
        XCTAssertFalse(
            CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: .resolution, drum: nil))
        XCTAssertFalse(
            CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: nil, drum: .color))
        XCTAssertTrue(CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: .iso, drum: nil))
        XCTAssertTrue(CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: nil, drum: .wb))
    }
}
