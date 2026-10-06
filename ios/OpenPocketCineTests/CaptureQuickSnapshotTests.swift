import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class CaptureQuickSnapshotTests: XCTestCase {
    func testRecordingConfirmationIsBoundToOriginalCameraState() {
        let request = RecordConfirmationContext(
            mode: 1, recording: false, locked: false, busy: false, phase: .live)
        XCTAssertTrue(request.canConfirm)
        let changedStates = [
            RecordConfirmationContext(
                mode: 0, recording: false, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: true, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: true, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: true, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: false, phase: .idle),
        ]
        // Mirrors the LiveRecordButton confirm guard: `pending == current && current.canConfirm`.
        let confirms = { (current: RecordConfirmationContext) in
            request == current && current.canConfirm
        }
        XCTAssertTrue(confirms(request))
        for changed in changedStates {
            XCTAssertNotEqual(
                changed, request, "every captured field must bind the confirmation: \(changed)")
            XCTAssertFalse(confirms(changed), "stale confirmation must not fire after \(changed)")
        }
        for photo in [0x05, 0x17] {
            XCTAssertFalse(
                RecordConfirmationContext(
                    mode: photo, recording: false, locked: false, busy: false, phase: .live
                ).canConfirm)
        }
    }
}
