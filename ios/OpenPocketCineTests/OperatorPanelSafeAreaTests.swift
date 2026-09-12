import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class OperatorPanelSafeAreaTests: XCTestCase {
    func testIgnoredPortraitInsetsRecoverCameraIslandAndHomeIndicator() {
        let resolved = OperatorPanelMetrics.resolvedDeviceSafeArea(
            EdgeInsets(), window: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(resolved.top, 62)
        XCTAssertEqual(resolved.bottom, 34)
        XCTAssertEqual(resolved.leading, 0)
        XCTAssertEqual(resolved.trailing, 0)
    }

    func testLandscapeResolutionPreservesBothPhysicalAndHostClearance() {
        let resolved = OperatorPanelMetrics.resolvedDeviceSafeArea(
            EdgeInsets(top: 0, leading: 0, bottom: 28, trailing: 12),
            window: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 0))
        XCTAssertEqual(resolved.top, 0)
        XCTAssertEqual(resolved.leading, 62)
        XCTAssertEqual(resolved.bottom, 28)
        XCTAssertEqual(resolved.trailing, 12)
    }
}
