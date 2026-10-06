import Foundation
import Observation
import OpenCineDJI
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// SIMULATED actual borrowed native host; unopened real driver, no socket or hardware.
@MainActor
final class ZoomGestureOwnerTests: XCTestCase {
    @MainActor private final class Reentry { var value = false }
    private func borrowed() -> CameraSession {
        let session = CameraSession(borrowing: HevcDecoder())
        let driver = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        let camera = DjiAppleSighting(
            id: UUID(), name: "OsmoPocket3-Test",
            model: CameraModel.resolve(modelId: nil, name: "OsmoPocket3-Test"), modelId: nil)
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoResolution = .p1080
        status.colorMode = .dLog
        status.zoomFactorRaw = CamFov.rawAt1x
        session.updateMultiview(camera: camera, driver: driver, status: status)
        return session
    }
    func testActualBorrowedPinchKeepsAnchorAcrossLiveStatusThenLiftProjectsLastStop() {
        let session = borrowed()
        defer { session.releaseMultiview() }
        session.updateZoomPinch(magnification: 2)
        XCTAssertEqual(session.zoomPinchPreview, 2)
        session.status.zoomFactorRaw = CamFov.rawAt3x
        session.updateZoomPinch(magnification: 3)
        XCTAssertEqual(session.zoomPinchPreview, 3)
        XCTAssertEqual(session.zoomDialReadout, 3)
        session.endZoomPinch()
        XCTAssertNil(session.zoomPinchPreview)
        XCTAssertEqual(session.zoomStop, 3)
    }
    func testActualBorrowedChipPublishesOptimisticProjectionWithoutCameraConfirmation() {
        let session = borrowed()
        defer { session.releaseMultiview() }
        session.setZoom(3)
        XCTAssertEqual(session.zoomOptimistic, 3)
        XCTAssertEqual(session.zoomReadout, 3)
        XCTAssertEqual(session.status.zoomFactor, 1)
        XCTAssertEqual(session.zoomStop, 3)
    }
    func testActualMissingCameraRefusesChipAndPinchWithoutManufacturingProjection() {
        let session = CameraSession()
        var notSent = 0
        session.setZoom(3, onStage: { if case .notSent = $0 { notSent += 1 } })
        session.updateZoomPinch(magnification: 3)
        XCTAssertEqual(notSent, 1)
        XCTAssertNil(session.zoomPinchPreview)
        XCTAssertNil(session.zoomOptimistic)
        XCTAssertNil(session.status.zoomFactor)
        XCTAssertEqual(session.zoomStop, 1)
    }
    func testActualCommittedPreviewObserverReentryPreservesSuccessorChipProjection() {
        let session = borrowed()
        defer { session.releaseMultiview() }
        let reentered = Reentry()
        withObservationTracking {
            _ = session.zoomPinchPreview
        } onChange: {
            MainActor.assumeIsolated {
                guard !reentered.value else { return }
                XCTAssertEqual(session.zoomPinchPreview, 2)
                reentered.value = true
                session.setZoom(6)
            }
        }
        session.updateZoomPinch(magnification: 2)
        XCTAssertTrue(reentered.value)
        XCTAssertNil(session.zoomPinchPreview)
        XCTAssertEqual(session.zoomOptimistic, 6)
        XCTAssertEqual(session.zoomReadout, 6)
        XCTAssertEqual(session.status.zoomFactor, 1)
    }
}
