import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class OperatorPanelSafeAreaTests: XCTestCase {
    func testResolvedDeviceSafeAreaKeepsTheLargerInsetPerEdge() {
        let cases: [(String, reported: EdgeInsets, window: EdgeInsets, expected: EdgeInsets)] = [
            (
                "ignored portrait insets recover the camera island and home indicator",
                EdgeInsets(), EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
                EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
            ),
            (
                "landscape keeps both physical and host clearance",
                EdgeInsets(top: 0, leading: 0, bottom: 28, trailing: 12),
                EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 0),
                EdgeInsets(top: 0, leading: 62, bottom: 28, trailing: 12)
            ),
        ]
        for (name, reported, window, expected) in cases {
            let resolved = OperatorPanelMetrics.resolvedDeviceSafeArea(reported, window: window)
            XCTAssertEqual(resolved.top, expected.top, "\(name): top")
            XCTAssertEqual(resolved.leading, expected.leading, "\(name): leading")
            XCTAssertEqual(resolved.bottom, expected.bottom, "\(name): bottom")
            XCTAssertEqual(resolved.trailing, expected.trailing, "\(name): trailing")
        }
    }
}
