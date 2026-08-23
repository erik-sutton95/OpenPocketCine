import XCTest

@testable import OpenPocketCine

/// OpenZCine `MonitorExperience.zoomGesturesTail` and Android `FocusFeedGesturesTest`.
final class LiveDispSwipeTests: XCTestCase {
    func testDownBecomesClean() {
        XCTAssertEqual(LiveDispSwipe.wantsClean(translation: CGSize(width: 0, height: 45)), true)
    }

    func testUpBecomesLive() {
        XCTAssertEqual(LiveDispSwipe.wantsClean(translation: CGSize(width: 0, height: -45)), false)
    }

    func testExactlyFortyFourPointsIsNotEnough() {
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 0, height: 44)))
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 0, height: -44)))
    }

    func testVerticalDominanceNeedsEightPointMargin() {
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 37, height: 45)))
        XCTAssertEqual(LiveDispSwipe.wantsClean(translation: CGSize(width: 36, height: 44.1)), true)
    }

    func testHorizontalDragIsIgnored() {
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 80, height: 10)))
    }

    func testDiagonalFlickIsNotASwipe() {
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 50, height: 50)))
        XCTAssertNil(LiveDispSwipe.wantsClean(translation: CGSize(width: 50, height: -50)))
    }
}
