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
        let glyph = CGSize(width: 40, height: 16)
        let pad = MonitorReadoutHitTarget.padding(for: glyph)
        let hit = MonitorReadoutHitTarget.frame(CGRect(origin: .zero, size: glyph))
        XCTAssertEqual(hit.width, glyph.width + pad.width * 2)
        XCTAssertEqual(hit.height, glyph.height + pad.height * 2)
    }

    func testExpandedFrameIsTheSharedGestureAndBackdropRegion() {
        let glyph = CGRect(x: 100, y: 200, width: 40, height: 16)
        let hit = MonitorReadoutHitTarget.frame(glyph)
        XCTAssertEqual(hit, CGRect(x: 98, y: 186, width: 44, height: 44))
        XCTAssertEqual(hit.midX, glyph.midX)
        XCTAssertEqual(hit.midY, glyph.midY)
        XCTAssertTrue(hit.contains(CGPoint(x: glyph.midX, y: glyph.minY - 10)))
        XCTAssertFalse(glyph.contains(CGPoint(x: glyph.midX, y: glyph.minY - 10)))
        XCTAssertEqual(
            MonitorReadoutHitTarget.frame(CGRect(x: 10, y: 20, width: 80, height: 50)),
            CGRect(x: 10, y: 20, width: 80, height: 50))
    }

    func testPaddingTapsStayInsideOneControlWhenAnotherPickerIsOpen() {
        let format = MonitorReadoutHitTarget.frame(CGRect(x: 80, y: 18, width: 52, height: 19))
        let color = MonitorReadoutHitTarget.frame(
            CGRect(x: format.maxX + 24, y: 18, width: 48, height: 19))
        let mode = MonitorReadoutHitTarget.frame(
            CGRect(x: color.maxX + 24, y: 18, width: 44, height: 19))
        XCTAssertGreaterThanOrEqual(format.height, 44)
        XCTAssertGreaterThanOrEqual(color.height, 44)
        XCTAssertGreaterThanOrEqual(mode.height, 44)
        XCTAssertFalse(format.intersects(color))
        XCTAssertFalse(color.intersects(mode))

        let formatPadding = CGPoint(x: format.midX, y: format.minY + 4)
        XCTAssertTrue(format.contains(formatPadding))
        XCTAssertFalse(
            CGRect(x: 80, y: 18, width: 52, height: 19).contains(formatPadding),
            "A 44pt padding tap is outside the glyph and must still belong to FORMAT")
        XCTAssertFalse(color.contains(formatPadding))
        XCTAssertFalse(mode.contains(formatPadding))
    }
}
