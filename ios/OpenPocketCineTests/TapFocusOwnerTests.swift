import CoreGraphics
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual native presentation with absent transport; no camera report synthesized.
@MainActor
final class TapFocusOwnerTests: XCTestCase {
    func testActualUnconnectedTapKeepsClampedReticleAndUnknownCameraFocus() {
        let session = CameraSession()
        XCTAssertTrue(session.supportsTapFocus)
        XCTAssertEqual(session.focusPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(session.status.focusMode)
        session.markFocus(at: CGPoint(x: -0.2, y: 1.4))
        XCTAssertEqual(session.focusPoint, CGPoint(x: 0, y: 1))
        XCTAssertNil(session.status.focusMode)
        XCTAssertFalse(session.controlLinkReady)
        XCTAssertNil(session.searchBox)
        XCTAssertNil(session.subjectBox)
    }
}
