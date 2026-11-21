import OpenCineApple
import OpenCineCore
import OpenCineDJI
import OpenCineDJIApple
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

    private func source(
        _ model: String?, networks: [SharedNetworkStore.Network] = []
    ) -> PocketCameraStreamSource {
        let camera = model.map { DjiAppleSighting(id: UUID(), name: $0, model: CameraModel(name: $0), modelId: nil) }
        return PocketCameraStreamSource(
            camera: { camera }, savedNetworks: { networks }, hostPath: SharedWiFiPath(),
            release: {}, resume: {})
    }

    func testCameraSourceNeedsADeclaredBody() {
        XCTAssertEqual(source("Osmo Pocket 4 Pro").publishing?.width, 1920)
        XCTAssertEqual(source("Osmo Pocket 4 Pro").publishing?.preferredCodec, .hevc)
        XCTAssertNil(source("Osmo Nano").publishing, "No livestream mode on Nano")
        XCTAssertNil(
            source("Osmo Pocket 3").publishing,
            "Experimental bodies wait for their hardware pass (no experimental switch here yet)")
        XCTAssertNil(source(nil).publishing, "No camera, no choice")
    }

    func testNetworksListTheHotspotFirst() {
        let networks = source(
            "Osmo Pocket 4 Pro",
            networks: [
                SharedNetworkStore.Network(ssid: "Mouse House", password: "a", hotspot: false),
                SharedNetworkStore.Network(ssid: "es_iphone16", password: "b", hotspot: true),
            ]
        ).networks
        XCTAssertEqual(networks.map(\.id), ["es_iphone16|hotspot", "Mouse House|wifi"])
        XCTAssertEqual(networks.map(\.isHotspot), [true, false])
        XCTAssertEqual(networks.first?.name, "es_iphone16")
    }

    func testOnlyTheAppsRootModelStreams() {
        XCTAssertNil(AppModel(session: CameraSession(borrowing: HevcDecoder())).liveStream)
    }
}
