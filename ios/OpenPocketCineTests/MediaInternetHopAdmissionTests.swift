import XCTest

@testable import OpenPocketCine

/// SIMULATED disconnected sources have no SSID or credentials, so the DJI joiner never leaves
/// a network here. These exercise Pocket's route admission over the shared hop owner (A2-16).
@MainActor final class MediaInternetHopAdmissionTests: XCTestCase {
    func testASecondHopIsRefusedWhileOneRuns() {
        let model = AppModel()
        defer { model.session.disconnect() }
        let first = model.internetHop.begin(model.hopRoute)
        XCTAssertNotNil(first)
        XCTAssertNil(model.internetHop.begin(model.hopRoute))
        if let first { _ = model.internetHop.end(first) }
        XCTAssertFalse(model.internetHop.isActive)
    }

    func testTheReturnBelongsOnlyToTheSessionThatLeft() {
        let model = AppModel(), session = model.session
        defer { session.disconnect() }
        let route = model.hopRoute
        XCTAssertTrue(route.session === session)
        XCTAssertEqual(route.sessionID, session.control.id)
        session.disconnect()
        XCTAssertTrue(model.session === session)
        XCTAssertNotEqual(session.control.id, route.sessionID, "A retired control source is a new session")
    }
}
