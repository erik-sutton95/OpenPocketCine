import OpenCineDJIApple
import OpenCineMedia
import XCTest

@testable import OpenPocketCine

/// SIMULATED native donor admission, with genuine connection/recovery slot facts.
@MainActor final class PocketMediaPortTests: XCTestCase {
    func testCapturedActualIdentitySurvivesNilDriverRecoveryWithoutCatalogPermission() async {
        let session = CameraSession()
        let peer = ConnectionDonorPeer(cached: true)
        defer {
            session.disconnect()
            session.decoder.close()
            withExtendedLifetime(peer) {}
        }
        guard await peer.admitExistingConnection(session) else { return }
        guard let camera = session.connectedCamera,
            let snapshot = await session.control.currentSnapshot()
        else {
            XCTFail("Admitted actual connection must expose its source snapshot")
            return
        }
        let port = PocketMediaPort(
            session: session, snapshot: snapshot,
            target: session.control.target, cameraID: camera.id.uuidString)
        var negotiation: CheckedContinuation<Void, Never>?
        guard
            session.startFeedRecovery({ _ in
                await withCheckedContinuation { negotiation = $0 }
            })
        else {
            XCTFail("Actual recovery owner must admit the nil-driver negotiation")
            return
        }
        while negotiation == nil { await Task.yield() }
        XCTAssertNil(session.datalink)
        let facts = port.mediaFacts
        XCTAssertEqual(facts?.identity.session, snapshot.session)
        XCTAssertEqual(facts?.identity.epoch, snapshot.epoch)
        XCTAssertEqual(facts?.identity.cameraID, camera.id.uuidString)
        XCTAssertEqual(facts?.canQuery, false)
        negotiation?.resume()
        session.disconnect()
        XCTAssertNil(
            port.mediaFacts, "Retirement removes authority rather than fabricating readiness")
    }

    func testActualConnectionCreatesUsableProducerWithAbsentUnadoptedOperations() async {
        let session = CameraSession()
        let peer = ConnectionDonorPeer(cached: true)
        defer {
            session.disconnect()
            session.decoder.close()
            withExtendedLifetime(peer) {}
        }
        guard await peer.admitExistingConnection(session) else { return }
        guard let service = await session.connectedMediaService() else {
            XCTFail("Actual admitted source must create its concrete media producer")
            return
        }
        XCTAssertEqual(service.sessionID, session.control.id)
        XCTAssertTrue(session.cameraMedia.mediaService === service)
        XCTAssertNotNil(session.cameraMedia.mediaPort)
        do {
            _ = try await service.openBrowse()
            XCTFail("A producer registered without an actual driver cannot list")
        } catch {
            XCTAssertEqual(error as? MediaServiceError, .unavailable)
        }
    }
}
