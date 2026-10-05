import CoreGraphics
import Observation
import OpenCineDJI
import OpenCineDJIApple
import XCTest

@testable import OpenPocketCine

/// SIMULATED native host without a driver; no camera readiness or catalog is manufactured.
@MainActor
final class SubjectTrackingOwnerTests: XCTestCase {
    func testActualSessionKeepsLocalSearchAndClearWithUnknownTransport() {
        let session = CameraSession()
        let box = TrackingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3)
        session.startTracking(box)
        XCTAssertEqual(session.searchBox, box)
        XCTAssertNil(session.subjectBox)
        XCTAssertFalse(session.isTracking)
        XCTAssertFalse(session.controlLinkReady)
        session.cancelSubjectTracking()
        XCTAssertNil(session.searchBox)
        XCTAssertNil(session.subjectBox)
        XCTAssertFalse(session.isTracking)
        XCTAssertFalse(session.controlLinkReady)
    }

    func testActualSessionTrackingObservationSeesCommittedClear() {
        let session = CameraSession()
        let box = TrackingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3)
        session.startTracking(box)
        let observed = TrackingObservation()
        withObservationTracking {
            _ = session.searchBox
        } onChange: {
            MainActor.assumeIsolated {
                observed.fired = true
                XCTAssertNil(session.searchBox)
                XCTAssertNil(session.subjectBox)
                XCTAssertFalse(session.isTracking)
            }
        }
        session.cancelSubjectTracking()
        XCTAssertTrue(observed.fired)
    }

    func testActualSessionSynchronousTrackingReplacementKeepsSuccessor() {
        let session = CameraSession()
        let first = TrackingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3)
        let outgoing = TrackingBox(x: 0.5, y: 0.2, width: 0.15, height: 0.2)
        let successor = TrackingBox(x: 0.7, y: 0.2, width: 0.15, height: 0.2)
        session.startTracking(first)
        withObservationTracking {
            _ = session.searchBox
        } onChange: {
            MainActor.assumeIsolated { session.startTracking(successor) }
        }
        session.startTracking(outgoing)
        XCTAssertEqual(session.searchBox, successor)
        XCTAssertNil(session.subjectBox)
        XCTAssertFalse(session.isTracking)
        XCTAssertFalse(session.controlLinkReady)
        session.cancelSubjectTracking()
    }

    func testActualSessionTooSmallPublicationCannotClearSynchronousSuccessor() {
        let session = CameraSession()
        let first = TrackingBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3)
        let successor = TrackingBox(x: 0.7, y: 0.2, width: 0.15, height: 0.2)
        session.startTracking(first)
        withObservationTracking {
            _ = session.searchBox
        } onChange: {
            MainActor.assumeIsolated { session.startTracking(successor) }
        }
        session.startTracking(.init(x: 0.2, y: 0.2, width: 0.02, height: 0.02))
        XCTAssertEqual(session.searchBox, successor)
        XCTAssertNil(session.subjectBox)
        XCTAssertFalse(session.isTracking)
        XCTAssertNil(session.controlNote)
        XCTAssertFalse(session.controlLinkReady)
        session.cancelSubjectTracking()
    }

}

@MainActor private final class TrackingObservation {
    var fired = false
}
