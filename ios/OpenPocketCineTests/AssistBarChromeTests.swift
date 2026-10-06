import SwiftUI
import XCTest

@testable import OpenPocketCine

final class AssistBarChromeTests: XCTestCase {
    func testZoomLabelHoldIgnoresTenthJitter() {
        XCTAssertFalse(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.08, pinching: false))
        XCTAssertTrue(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.2, pinching: false))
        XCTAssertTrue(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.08, pinching: true))
    }
}
