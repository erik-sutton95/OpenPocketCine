import XCTest

@testable import OpenPocketCine

final class LiveFeedFocusGestureTests: XCTestCase {
    func testShortDragIsTap() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 4, height: -3)),
            .tap
        )
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: .zero),
            .tap
        )
    }

    func testUnarmedDragNeverTracks() {
        XCTAssertNotEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 30, height: 8)),
            .track
        )
        XCTAssertNotEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: -20, height: -20)),
            .track
        )
        XCTAssertNotEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 50, height: 50)),
            .track
        )
        XCTAssertNotEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 40, height: 20)),
            .track
        )
    }

    func testUnarmedLongDragThatIsNotASwipeDoesNothing() {
        XCTAssertNil(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 30, height: 8))
        )
        XCTAssertNil(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 50, height: 50))
        )
    }

    func testArmedDragTracks() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 30, height: 8), armed: true),
            .track
        )
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: -20, height: -20), armed: true),
            .track
        )
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 30, height: 30), armed: true),
            .track
        )
    }

    func testArmedWithoutEnoughDragIsTap() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 4, height: 3), armed: true),
            .tap
        )
    }

    func testVerticalSwipeStillSwitchesDisp() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 0, height: 45)),
            .dispClean
        )
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 0, height: -45)),
            .dispLive
        )
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 36, height: 44.1)),
            .dispClean
        )
    }

    func testPinchSuppressesTheDrag() {
        XCTAssertNil(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 80, height: 10),
                pinched: true
            )
        )
        XCTAssertNil(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 40, height: 30),
                pinched: true,
                armed: true
            )
        )
    }

    func testDispWinsOverTrackSizedVertical() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 10, height: 80)),
            .dispClean
        )
    }

    func testVerticalSwipeInProgressIsNotTrack() {
        XCTAssertNil(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 0, height: 30))
        )
        XCTAssertNil(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 8, height: 30))
        )
        XCTAssertNil(
            LiveFeedFocusGesture.classify(translation: CGSize(width: -6, height: -32))
        )
    }

    func testVerticalNudgeShorterThanTrackFloorIsStillTap() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(translation: CGSize(width: 4, height: 20)),
            .tap
        )
    }

    func testHoldThenVerticalDragStillTracks() {
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 10, height: 80), armed: true),
            .track
        )
    }
}
