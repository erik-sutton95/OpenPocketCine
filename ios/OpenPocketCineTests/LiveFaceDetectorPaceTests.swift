import XCTest

@testable import OpenPocketCine

final class LiveFaceDetectorPaceTests: XCTestCase {
    func testDetectsAtFeedRateUntilASecondWithoutFacesThenIdlesAt10Hz() {
        XCTAssertEqual(LiveFaceDetector.pace(emptyRuns: 0), 0.04)
        XCTAssertEqual(LiveFaceDetector.pace(emptyRuns: 24), 0.04)
        XCTAssertEqual(LiveFaceDetector.pace(emptyRuns: 25), 0.1)
    }
}
