import SwiftUI
import XCTest

@testable import OpenPocketCine

final class NDAssistTests: XCTestCase {
    func testChipSizeAndMovableContract() {
        XCTAssertEqual(NDAssist.baseSize, ScopePanelSize.ndMeter)
        XCTAssertEqual(NDAssist.baseSize, CGSize(width: 84, height: 30))
        XCTAssertEqual(NDAssist.scaleRange, 0.6...1.6)
        XCTAssertEqual(NDAssist.panelID, "nd-meter")
        XCTAssertEqual(NDAssist.holdDuration, 0.3, accuracy: 0.001)
        XCTAssertEqual(NDAssist.positionGrid, 4)
        XCTAssertEqual(NDAssist.hapticGrid, 22)
        XCTAssertEqual(NDAssist.gripVisualSize, 14)
        XCTAssertEqual(NDAssist.gripExteriorGap, 2)
        XCTAssertEqual(NDAssist.meterTitle, "ND")
        XCTAssertEqual(NDAssist.accessibilityTitle, "ND Suggestion")
        XCTAssertEqual(NDAssist.panelSize(scale: 1), ScopePanelSize.ndMeter)
        XCTAssertEqual(NDAssist.clampedScale(0.2), 0.6, accuracy: 1e-12)
        XCTAssertEqual(NDAssist.clampedScale(3), 1.6, accuracy: 1e-12)
        XCTAssertEqual(NDAssist.defaultNotation, .factor)
        XCTAssertEqual(NDAssist.notationTitle, "Units")
        XCTAssertEqual(NDAssist.notationOptions, ["Stops", "ND32", "ND 0.3"])
    }

    func testDefaultCenterParksBottomLeadingAboveAssistBar() {
        let bounds = CGRect(x: 0, y: 0, width: 874, height: 402)
        let feed = CGRect(x: 59, y: 0, width: 714.7, height: 402)
        let size = NDAssist.baseSize
        let chrome = EdgeInsets(top: 60, leading: 0, bottom: 72, trailing: 0)
        let center = NDAssist.defaultCenter(
            feed: feed, size: size, bounds: bounds, chromeClearance: chrome)
        XCTAssertEqual(center.x, feed.minX + size.width / 2, accuracy: 0.5)
        XCTAssertLessThanOrEqual(center.y + size.height / 2, bounds.maxY - chrome.bottom + 0.5)
        XCTAssertGreaterThanOrEqual(center.y - size.height / 2, bounds.minY - 0.5)
        XCTAssertGreaterThan(center.y, feed.midY)
        let chipBottom = center.y + size.height / 2
        let assistTop = bounds.maxY - chrome.bottom
        XCTAssertLessThan(chipBottom, assistTop)
        XCTAssertGreaterThan(assistTop - chipBottom, 8)
    }

    func testSnapClampAndStoredCenter() {
        let snapped = NDAssist.snap(CGPoint(x: 11, y: 7))
        XCTAssertEqual(snapped.x, 12)
        XCTAssertEqual(snapped.y, 8)
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let size = NDAssist.baseSize
        let clamped = NDAssist.clamp(CGPoint(x: -40, y: 400), size: size, in: bounds)
        XCTAssertEqual(clamped.x, size.width / 2)
        XCTAssertEqual(clamped.y, bounds.maxY - size.height / 2)
        let center = CGPoint(x: 80, y: 160)
        let stored = NDAssist.StoredCenter(center: center, in: bounds)
        let restored = stored.center(in: bounds)
        XCTAssertEqual(restored.x, center.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.001)
        let session = CGPoint(x: 90, y: 40)
        let resolved = NDAssist.resolvedCenter(
            session: session,
            stored: stored,
            defaultCenter: CGPoint(x: 40, y: 40),
            size: size,
            bounds: bounds)
        XCTAssertEqual(resolved.x, session.x, accuracy: 0.001)
        XCTAssertEqual(resolved.y, session.y, accuracy: 0.001)
    }
}
