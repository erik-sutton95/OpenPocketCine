import OpenCineDJI
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual native host composition and nil transport; no camera fact fabricated.
@MainActor
final class ImageControlOwnerTests: XCTestCase {
    func testActualUnconnectedDLog2SliderRetainsPendingStageUntilGestureEnds() {
        let session = CameraSession()
        session.status.colorMode = .dLog2
        var notSent = 0
        session.setZoomSlider(
            3,
            onStage: { value in
                if case .notSent = value { notSent += 1 }
            })
        XCTAssertFalse(session.controlLinkReady)
        XCTAssertEqual(session.status.colorMode, .dLog2)
        XCTAssertFalse(session.zoomColorHopPending)
        XCTAssertNil(session.status.zoomFactor)
        XCTAssertNil(session.status.isoIndex)
        XCTAssertEqual(notSent, 0)
        session.endZoomPinch()
        XCTAssertEqual(notSent, 1)
        session.endZoomPinch()
        XCTAssertEqual(notSent, 1)
    }

    func testActualRecordingRefusesColorHopAndAccountsSliderWithoutChangingCameraFacts() {
        let session = CameraSession()
        session.status.colorMode = .dLog2
        session.status.isRecording = true
        var notSent = 0
        session.setZoomSlider(
            3,
            onStage: { value in
                if case .notSent = value { notSent += 1 }
            })
        XCTAssertEqual(notSent, 1)
        XCTAssertFalse(session.zoomColorHopPending)
        XCTAssertEqual(session.controlNote, ControlHud.recordingColorLockNote)
        XCTAssertEqual(session.status.colorMode, .dLog2)
        XCTAssertTrue(session.status.isRecording)
        XCTAssertNil(session.status.zoomFactor)
        XCTAssertNil(session.status.isoIndex)
    }

    func testActualDisconnectRetiresCapturedPendingStageExactlyOnceWithoutSourceReadiness() {
        let session = CameraSession()
        session.status.colorMode = .dLog2
        var notSent = 0
        session.setZoomSlider(
            3,
            onStage: { value in
                if case .notSent = value { notSent += 1 }
            })
        XCTAssertEqual(notSent, 0)
        session.disconnect()
        XCTAssertEqual(notSent, 1)
        XCTAssertFalse(session.zoomColorHopPending)
        XCTAssertFalse(session.controlLinkReady)
        XCTAssertNil(session.status.colorMode)
        XCTAssertNil(session.status.zoomFactor)
        session.disconnect()
        XCTAssertEqual(notSent, 1)
    }

    func testActualGestureEndStageCallbackCannotRetireSuccessorPendingSlider() {
        let session = CameraSession()
        session.status.colorMode = .dLog2
        var outgoing = 0
        var incoming = 0
        session.setZoomSlider(
            2,
            onStage: { value in
                if case .notSent = value {
                    outgoing += 1
                    session.setZoomSlider(
                        4,
                        onStage: { value in
                            if case .notSent = value { incoming += 1 }
                        })
                }
            })
        session.endZoomPinch()
        XCTAssertEqual(outgoing, 1)
        XCTAssertEqual(incoming, 0)
        XCTAssertEqual(session.status.colorMode, .dLog2)
        session.endZoomPinch()
        XCTAssertEqual(outgoing, 1)
        XCTAssertEqual(incoming, 1)
    }

}
