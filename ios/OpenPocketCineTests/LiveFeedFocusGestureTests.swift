import XCTest

@testable import OpenPocketCine

/// Feed drag classification plus the DISP swipe it defers to. Mirrors OpenZCine
/// `MonitorExperience.zoomGesturesTail` and Android `FocusFeedGesturesTest`.
final class LiveFeedFocusGestureTests: XCTestCase {
    func testDragClassification() {
        typealias Kind = LiveFeedFocusGesture.Kind
        let cases: [(String, CGSize, armed: Bool, pinched: Bool, Kind?)] = [
            ("short drag is a tap", CGSize(width: 4, height: -3), false, false, .tap),
            ("no movement is a tap", .zero, false, false, .tap),
            ("unarmed long drag that is not a swipe does nothing", CGSize(width: 30, height: 8),
             false, false, nil),
            ("unarmed diagonal does nothing", CGSize(width: 50, height: 50), false, false, nil),
            ("armed drag tracks", CGSize(width: 30, height: 8), true, false, .track),
            ("armed up-left drag tracks", CGSize(width: -20, height: -20), true, false, .track),
            ("armed diagonal tracks", CGSize(width: 30, height: 30), true, false, .track),
            ("armed without enough drag is a tap", CGSize(width: 4, height: 3), true, false, .tap),
            ("down swipe switches to clean", CGSize(width: 0, height: 45), false, false,
             .dispClean),
            ("up swipe switches to live", CGSize(width: 0, height: -45), false, false, .dispLive),
            ("vertical swipe at the dominance margin", CGSize(width: 36, height: 44.1), false,
             false, .dispClean),
            ("pinch suppresses the drag", CGSize(width: 80, height: 10), false, true, nil),
            ("pinch suppresses an armed drag", CGSize(width: 40, height: 30), true, true, nil),
            ("DISP wins over a track-sized vertical", CGSize(width: 10, height: 80), false, false,
             .dispClean),
            ("vertical swipe in progress is not track", CGSize(width: 0, height: 30), false,
             false, nil),
            ("slanted vertical swipe in progress", CGSize(width: 8, height: 30), false, false, nil),
            ("upward swipe in progress", CGSize(width: -6, height: -32), false, false, nil),
            ("vertical nudge under the track floor is a tap", CGSize(width: 4, height: 20), false,
             false, .tap),
            ("hold then vertical drag still tracks", CGSize(width: 10, height: 80), true, false,
             .track),
        ]
        for (name, translation, armed, pinched, expected) in cases {
            XCTAssertEqual(
                LiveFeedFocusGesture.classify(
                    translation: translation, pinched: pinched, armed: armed),
                expected, name)
        }
        // A still long press locks AE; dragging after it still draws a track box.
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 4, height: 3), armed: true, aeLockHeld: true), .aeLock)
        XCTAssertEqual(
            LiveFeedFocusGesture.classify(
                translation: CGSize(width: 30, height: 8), armed: true, aeLockHeld: true), .track)
        // An unarmed drag must never start tracking, whatever else it becomes.
        for translation in [
            CGSize(width: 30, height: 8), CGSize(width: -20, height: -20),
            CGSize(width: 50, height: 50), CGSize(width: 40, height: 20),
        ] {
            XCTAssertNotEqual(
                LiveFeedFocusGesture.classify(translation: translation), .track,
                "unarmed \(translation) must not track")
        }
    }

    func testDispSwipe() {
        let cases: [(String, CGSize, Bool?)] = [
            ("down becomes clean", CGSize(width: 0, height: 45), true),
            ("up becomes live", CGSize(width: 0, height: -45), false),
            ("exactly 44 pt down is not enough", CGSize(width: 0, height: 44), nil),
            ("exactly 44 pt up is not enough", CGSize(width: 0, height: -44), nil),
            ("vertical dominance needs an 8 pt margin", CGSize(width: 37, height: 45), nil),
            ("just inside the dominance margin", CGSize(width: 36, height: 44.1), true),
            ("horizontal drag is ignored", CGSize(width: 80, height: 10), nil),
            ("diagonal down flick is not a swipe", CGSize(width: 50, height: 50), nil),
            ("diagonal up flick is not a swipe", CGSize(width: 50, height: -50), nil),
        ]
        for (name, translation, expected) in cases {
            XCTAssertEqual(LiveDispSwipe.wantsClean(translation: translation), expected, name)
        }
    }

    func testPressOnTheFocusBoxHitsItWithAFingersMargin() {
        let size = CGSize(width: 800, height: 450)  // box side 63 pt, reach 31.5 + 14
        let focus = CGPoint(x: 0.25, y: 0.5)  // (200, 225) on screen
        XCTAssertTrue(LiveFeedFocusGesture.hitsFocusBox(CGPoint(x: 200, y: 225), focus: focus, in: size, mirrored: false))
        XCTAssertTrue(LiveFeedFocusGesture.hitsFocusBox(CGPoint(x: 245, y: 180), focus: focus, in: size, mirrored: false))
        XCTAssertFalse(LiveFeedFocusGesture.hitsFocusBox(CGPoint(x: 247, y: 225), focus: focus, in: size, mirrored: false))
        // Mirrored preview: the box is drawn at 1 - x.
        XCTAssertTrue(LiveFeedFocusGesture.hitsFocusBox(CGPoint(x: 600, y: 225), focus: focus, in: size, mirrored: true))
        XCTAssertFalse(LiveFeedFocusGesture.hitsFocusBox(CGPoint(x: 200, y: 225), focus: focus, in: size, mirrored: true))
        XCTAssertTrue(
            LiveFeedFocusGesture.hitsFocusBox(
                CGPoint(x: 200, y: 450 - 100), focus: CGPoint(x: 0.25, y: 100.0 / 450), in: size,
                mirrored: false, flippedVertically: true))
    }
}
