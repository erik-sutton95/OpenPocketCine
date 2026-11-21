import OpenCineApple
import OpenCineAppKitApple
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
            camera: { camera }, savedNetworks: { networks }, hostPath: FakeHostPath(),
            release: { true }, resume: {}, confirmHotspot: { _ in false }, settle: Self.noSettle)
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

    /// The phone's side of a shared network, without a radio.
    private final class FakeHostPath: StationHostPath {
        var hotspotAddress: String?
        var wifiAddress: String?
        var joined: String?
        func address(hotspot: Bool) -> String? { hotspot ? hotspotAddress : wifiAddress }
        func netmask(hotspot: Bool) -> String? { nil }
        func join(_ network: StationNetwork) async throws -> String? { joined }
    }

    /// What the camera source asked of the app.
    private final class Calls {
        var releases = 0
        var resumes = 0
        var questions: [String] = []
        var takesCamera = true
        var answer = false
    }

    private static let hotspot = SharedNetworkStore.Network(ssid: "es_iphone16", password: "b", hotspot: true)
    private static let router = SharedNetworkStore.Network(ssid: "Mouse House", password: "a", hotspot: false)

    private static func noSettle() async throws {}

    private func streamSource(_ path: FakeHostPath, _ calls: Calls) -> PocketCameraStreamSource {
        let camera = DjiAppleSighting(
            id: UUID(), name: "Osmo Pocket 4 Pro", model: CameraModel(name: "Osmo Pocket 4 Pro"), modelId: nil)
        return PocketCameraStreamSource(
            camera: { camera }, savedNetworks: { [Self.hotspot, Self.router] }, hostPath: path,
            release: {
                calls.releases += 1
                return calls.takesCamera
            },
            resume: { calls.resumes += 1 },
            confirmHotspot: { network in
                calls.questions.append(network)
                return calls.answer
            },
            settle: Self.noSettle)
    }

    private func network(_ saved: SharedNetworkStore.Network) -> LiveStreamNetwork {
        LiveStreamNetwork(
            id: "\(saved.ssid)|\(saved.hotspot ? "hotspot" : "wifi")", name: saved.ssid, isHotspot: saved.hotspot)
    }

    private func refusal(_ work: () async throws -> String) async -> LiveStreamCameraError? {
        do {
            _ = try await work()
            return nil
        } catch {
            return error as? LiveStreamCameraError
        }
    }

    func testANilJoinIsARefusalEvenOnAnotherWiFi() async {
        let path = FakeHostPath()
        path.wifiAddress = "192.168.2.20"  // still on the camera's own Wi-Fi, not the router
        let source = streamSource(path, Calls())
        let error = await refusal { try await source.prepare(self.network(Self.router)) }
        XCTAssertEqual(error, .refused("phone not on Mouse House"))
    }

    func testAJoinedRouterGivesItsAddress() async throws {
        let path = FakeHostPath()
        path.joined = "192.168.1.40"
        let address = try await streamSource(path, Calls()).prepare(network(Self.router))
        XCTAssertEqual(address, "192.168.1.40")
    }

    func testTheCameraIsReleasedOncePerRunAndResumedOnce() async throws {
        let path = FakeHostPath()
        path.hotspotAddress = "172.20.10.1"
        let calls = Calls()
        let source = streamSource(path, calls)
        _ = try await source.prepare(network(Self.hotspot))
        _ = try await source.prepare(network(Self.hotspot))
        XCTAssertEqual(calls.releases, 1, "A retry keeps the camera it already took")
        source.finished()
        XCTAssertEqual(calls.resumes, 1)
        _ = try await source.prepare(network(Self.hotspot))
        XCTAssertEqual(calls.releases, 2, "The next run takes the camera again")
    }

    func testACameraTheAppCannotTakeIsARefusal() async {
        let path = FakeHostPath()
        path.hotspotAddress = "172.20.10.1"
        let calls = Calls()
        calls.takesCamera = false
        let source = streamSource(path, calls)
        let error = await refusal { try await source.prepare(self.network(Self.hotspot)) }
        XCTAssertEqual(error, .refused("camera busy"))
    }

    func testAHotspotThatIsOnIsNotAskedAbout() async throws {
        let path = FakeHostPath()
        path.hotspotAddress = "172.20.10.1"
        let calls = Calls()
        let address = try await streamSource(path, calls).prepare(network(Self.hotspot))
        XCTAssertEqual(address, "172.20.10.1")
        XCTAssertEqual(calls.questions, [])
    }

    func testAHotspotThatIsOffIsAskedAboutBeforeTheCameraIsTaken() async throws {
        let path = FakeHostPath()
        let calls = Calls()
        calls.answer = true
        let source = streamSource(path, calls)
        let address = try await source.prepare(network(Self.hotspot))
        XCTAssertEqual(calls.questions, ["es_iphone16"])
        XCTAssertEqual(address, "172.20.10.1", "iOS always serves its hotspot here")
        _ = try await source.prepare(network(Self.hotspot))
        XCTAssertEqual(calls.questions, ["es_iphone16"], "A retry does not ask again")
    }

    func testADeclinedHotspotIsARefusalForTheWholeRun() async {
        let path = FakeHostPath()
        let calls = Calls()
        let source = streamSource(path, calls)
        let first = await refusal { try await source.prepare(self.network(Self.hotspot)) }
        XCTAssertEqual(first, .refused("hotspot off"))
        XCTAssertEqual(calls.releases, 0, "The camera stays with monitoring")
        let retry = await refusal { try await source.prepare(self.network(Self.hotspot)) }
        XCTAssertEqual(retry, .refused("hotspot off"))
        XCTAssertEqual(calls.questions.count, 1, "The retry does not ask a second time")
        source.finished()
        _ = await refusal { try await source.prepare(self.network(Self.hotspot)) }
        XCTAssertEqual(calls.questions.count, 2, "The next Go live asks again")
    }

    func testTheCameraMonitorStaysUpWhileARunsEndNoticeIsPending() {
        var presence = CameraMonitorPresence()
        presence.update(active: false, endPending: true)
        XCTAssertFalse(presence.shown, "A notice from a normal stream stays on the normal monitor")
        presence.update(active: true, endPending: false)
        XCTAssertTrue(presence.shown)
        presence.update(active: true, endPending: true)
        presence.update(active: false, endPending: true)
        XCTAssertTrue(presence.shown, "The camera is back but the notice is still to be read")
        presence.update(active: false, endPending: false)
        XCTAssertFalse(presence.shown, "Dismissed: back to the app")
        presence.update(active: true, endPending: false)
        presence.update(active: false, endPending: false)
        XCTAssertFalse(presence.shown, "A stop by the operator leaves no notice")
    }

    func testOnlyTheAppsRootModelStreams() {
        XCTAssertNil(AppModel(session: CameraSession(borrowing: HevcDecoder())).liveStream)
    }
}
