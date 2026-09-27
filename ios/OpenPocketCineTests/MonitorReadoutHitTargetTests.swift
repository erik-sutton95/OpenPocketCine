import SwiftUI
import XCTest

@testable import OpenPocketCine

final class MonitorReadoutHitTargetTests: XCTestCase {
    func testPaddingMatchesTheZcTapTargetMinimumWithoutGrowingLargerControls() {
        XCTAssertEqual(MonitorReadoutHitTarget.minimumSize, 44)
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: .zero), .zero,
            "Unmeasured labels must not pad on the first layout pass")
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: CGSize(width: 40, height: 16)),
            CGSize(width: 2, height: 14))
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: CGSize(width: 78, height: 12)),
            CGSize(width: 0, height: 16),
            "Portrait REC SETUP stays intrinsically wide and only grows the 44pt height")
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: CGSize(width: 52, height: 19)),
            CGSize(width: 0, height: 12.5),
            "Landscape FORMAT/COLOR/MODE keep their glyph width")
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: CGSize(width: 80, height: 50)), .zero)
        XCTAssertEqual(
            MonitorReadoutHitTarget.padding(for: CGSize(width: 44, height: 44)), .zero)
    }
}
