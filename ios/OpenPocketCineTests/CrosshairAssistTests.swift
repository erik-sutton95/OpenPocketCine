import XCTest

@testable import OpenPocketCine

final class CrosshairAssistTests: XCTestCase {
    func testOpenZCineHasNoStyleColorOrCenterMark() {
        XCTAssertEqual(CrosshairAssist.longPressPanelWidth, 400)
        XCTAssertEqual(
            CrosshairAssist.helpCopy,
            "Tap the toolbar button to show or hide the centre crosshair.")
        XCTAssertEqual(CrosshairAssist.armLength, 40)
        XCTAssertEqual(CrosshairAssist.strokeWidth, 1.4)
        XCTAssertEqual(CrosshairAssist.opacity, 0.65)
    }

    func testOverlayCentresOnFeed() {
        let feed = CGRect(x: 10, y: 20, width: 200, height: 100)
        let view = CrosshairAssist.overlay(feed: feed)
        XCTAssertEqual(view.feed, feed)
        XCTAssertEqual(view.feed.midX, 110)
        XCTAssertEqual(view.feed.midY, 70)
    }
}
