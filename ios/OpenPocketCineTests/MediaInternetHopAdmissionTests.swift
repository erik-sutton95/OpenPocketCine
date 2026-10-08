import Observation
import OpenCineFrameIO
import XCTest

@testable import OpenPocketCine

@MainActor private final class InternetHopObservation {
    var successor: FrameioInternetHop.Token?
}

/// SIMULATED disconnected sources have no SSID or credentials. These exercise the
/// shipping route/source admission without entering an OS network operation.
@MainActor final class MediaInternetHopAdmissionTests: XCTestCase {
    func testBeginPublicationKeepsSynchronouslyStartedSuccessor() throws {
        let model = AppModel(), observation = InternetHopObservation()
        defer { model.session.disconnect() }
        withObservationTracking { _ = model.internetHop.token } onChange: {
            MainActor.assumeIsolated { observation.successor = model.beginInternetHop() }
        }
        let outgoing = model.beginInternetHop()
        let successor = try XCTUnwrap(observation.successor)
        XCTAssertNotEqual(outgoing, successor)
        XCTAssertFalse(model.internetHop.owns(outgoing))
        XCTAssertTrue(model.internetHop.owns(successor))
        model.endInternetHop(outgoing)
        XCTAssertTrue(model.internetHop.owns(successor))
        model.endInternetHop(successor)
        XCTAssertTrue(model.consumeInternetHopReturn(successor, session: model.session))
        XCTAssertFalse(model.consumeInternetHopReturn(successor, session: model.session))
    }

    func testEndPublicationCannotConsumeSynchronousSuccessorReturn() throws {
        let model = AppModel(), observation = InternetHopObservation()
        defer { model.session.disconnect() }
        let outgoing = model.beginInternetHop()
        withObservationTracking { _ = model.internetHop.token } onChange: {
            MainActor.assumeIsolated {
                let successor = model.beginInternetHop()
                observation.successor = successor
                model.endInternetHop(successor)
            }
        }
        model.endInternetHop(outgoing)
        let successor = try XCTUnwrap(observation.successor)
        XCTAssertFalse(model.internetHopActive)
        XCTAssertFalse(model.consumeInternetHopReturn(outgoing, session: model.session))
        XCTAssertTrue(model.consumeInternetHopReturn(successor, session: model.session))
        XCTAssertFalse(model.consumeInternetHopReturn(successor, session: model.session))
    }

    func testNilRouteAfterSuccessorEndsCannotReviveOldReturn() {
        let model = AppModel()
        defer { model.session.disconnect() }
        let outgoing = model.beginInternetHop()
        model.endInternetHop(outgoing)
        let successor = model.beginInternetHop()
        model.endInternetHop(successor)
        XCTAssertFalse(model.internetHopActive)
        XCTAssertFalse(model.consumeInternetHopReturn(outgoing, session: model.session))
        XCTAssertTrue(model.consumeInternetHopReturn(successor, session: model.session))
    }

    func testRetiredControlSourceCannotReviveReturnOnSameSessionObject() {
        let model = AppModel(), session = model.session
        defer { session.disconnect() }
        let outgoing = model.beginInternetHop(), identity = session.control.id
        model.endInternetHop(outgoing)
        session.disconnect()
        XCTAssertTrue(model.session === session)
        XCTAssertNotEqual(session.control.id, identity)
        XCTAssertFalse(model.consumeInternetHopReturn(outgoing, session: session))
    }
}
