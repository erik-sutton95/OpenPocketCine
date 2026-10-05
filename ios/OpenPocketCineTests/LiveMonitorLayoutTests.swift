import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Shell-side layout helpers. Live chrome geometry is `FieldMonitorLayout` (core tests).
final class LiveMonitorLayoutTests: XCTestCase {
    func testTrackingCancelSitsOnTheSubjectCorner() {
        let feed = CGRect(x: 59, y: 0, width: 402 * 16 / 9, height: 402)
        let box = TrackingBox(x: 0.20, y: 0.20, width: 0.40, height: 0.40)
        let cancel = LiveTrackingChrome.cancelRect(box: box, feed: feed, mirrored: false)
        XCTAssertEqual(cancel.width, LiveTrackingChrome.cancelHitSize, accuracy: 0.05)
        XCTAssertEqual(cancel.height, LiveTrackingChrome.cancelHitSize, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(cancel.width, 44)
        let subject = CGRect(
            x: feed.minX + 0.20 * feed.width,
            y: feed.minY + 0.20 * feed.height,
            width: 0.40 * feed.width,
            height: 0.40 * feed.height
        )
        XCTAssertEqual(cancel.midX, subject.maxX, accuracy: 0.5)
        XCTAssertEqual(cancel.midY, subject.minY, accuracy: 0.5)
    }

    /// OpenZCine `fullScreenPanelSafeArea` / standalone Operator Setup host.
    func testOperatorSetupLandscapeZerosCleanEdge() {
        let leadingIsland = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0)
        let liveLeading = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: leadingIsland, isPortrait: false, mirrored: false)
        XCTAssertEqual(liveLeading.leading, 59)
        XCTAssertEqual(liveLeading.trailing, 0)
        XCTAssertEqual(OperatorPanelMetrics.leadingPadding(safeArea: liveLeading), 65)
        XCTAssertEqual(OperatorPanelMetrics.trailingPadding(safeArea: liveLeading), 16)
        XCTAssertEqual(OperatorPanelMetrics.closeButtonClearance(safeArea: liveLeading), 0)

        let trailingIsland = EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 59)
        let liveTrailing = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: trailingIsland, isPortrait: false, mirrored: true)
        XCTAssertEqual(liveTrailing.leading, 0)
        XCTAssertEqual(liveTrailing.trailing, 59)
        XCTAssertEqual(OperatorPanelMetrics.leadingPadding(safeArea: liveTrailing), 16)
        XCTAssertEqual(OperatorPanelMetrics.trailingPadding(safeArea: liveTrailing), 65)
        XCTAssertEqual(OperatorPanelMetrics.closeButtonClearance(safeArea: liveTrailing), 45)

        let bothSides = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        let standalone = OperatorPanelMetrics.standalonePanelSafeArea(from: bothSides)
        XCTAssertEqual(standalone.leading, 59)
        XCTAssertEqual(standalone.trailing, 0)

        let portrait = OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            mirrored: false
        )
        XCTAssertEqual(portrait.top, 59)
        XCTAssertEqual(portrait.leading, 0)
        XCTAssertEqual(OperatorPanelMetrics.settingsTopPadding(safeArea: EdgeInsets()), 14)
        XCTAssertEqual(OperatorPanelMetrics.closeTopPadding(safeArea: portrait), 65)
    }

    func testTrackingBracketLeavesGapsOnEachSide() {
        let width: CGFloat = 200
        let height: CGFloat = 120
        let armX = LiveTrackingChrome.bracketArm(along: width)
        let armY = LiveTrackingChrome.bracketArm(along: height)
        XCTAssertGreaterThan(width - 2 * armX, width * 0.25)
        XCTAssertGreaterThan(height - 2 * armY, height * 0.25)
        XCTAssertGreaterThan(armX, 10)
        XCTAssertGreaterThan(armY, 10)
        let path = LiveTrackingChrome.bracketPath(in: CGSize(width: width, height: height))
        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingRect.maxX, width, accuracy: 0.5)
        XCTAssertEqual(path.boundingRect.maxY, height, accuracy: 0.5)
    }
}
