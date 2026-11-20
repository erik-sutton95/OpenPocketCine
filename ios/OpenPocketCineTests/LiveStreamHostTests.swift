import OpenCineDJI
import OpenCineStreaming
import XCTest

@testable import OpenPocketCine

/// Live streaming's host values: eligibility comes from the active connection setup, never from a
/// camera command. SIMULATED session (no camera).
@MainActor
final class LiveStreamHostTests: XCTestCase {
    func testOnlyTheCamerasOwnWiFiBlocksStreaming() {
        XCTAssertEqual(
            StreamConnectionRoute(CameraConnectionSetup.cameraWiFi.routeKind), .cameraWiFi)
        XCTAssertEqual(StreamConnectionRoute(CameraConnectionSetup.wifi.routeKind), .sharedWiFi)
        XCTAssertEqual(
            StreamConnectionRoute(CameraConnectionSetup.phoneHotspot.routeKind), .deviceHotspot)
    }

    func testRouteAndSourceFollowTheLivePicture() {
        let session = CameraSession(borrowing: HevcDecoder())
        let model = AppModel(session: session)
        XCTAssertNil(
            model.liveStreamRoute, "No live picture: no route, so Go live says to connect a camera")
        XCTAssertNil(model.liveStreamSource)
        session.connectionSetup = .phoneHotspot
        session.phase = .live
        XCTAssertEqual(model.liveStreamRoute, .deviceHotspot)
        XCTAssertEqual(
            model.liveStreamSource, StreamSourceFormat(width: 1280, height: 720, frameRate: nil))
        session.connectionSetup = .cameraWiFi
        XCTAssertEqual(model.liveStreamRoute, .cameraWiFi)
    }

    func testOnlyTheAppsRootModelStreams() {
        XCTAssertNil(AppModel(session: CameraSession(borrowing: HevcDecoder())).liveStream)
    }
}
