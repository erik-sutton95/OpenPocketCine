import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Pins GRID to OpenZCine `AssistConfiguration.Grid` + `FeedGridView` (no fourths).
final class GridAssistTests: XCTestCase {
    func testLongPressOptionsMatchOpenZCine() {
        XCTAssertEqual(
            GridAssist.Option.allCases.map(\.rawValue),
            ["Thirds", "Phi Grid", "Diagonal"]
        )
    }

    func testThirdsAndPhiFractionsMatchOpenZCine() {
        XCTAssertEqual(GridAssist.thirdsFractions, [1.0 / 3, 2.0 / 3])
        XCTAssertEqual(GridAssist.phiFractions, [0.382, 0.618])
        XCTAssertEqual(GridAssist.strokeOpacity, 0.22, accuracy: 0.0001)
        XCTAssertEqual(GridAssist.strokeWidth, 1)
    }

    func testThirdsSegmentsCrossTheFeed() {
        let feed = CGRect(x: 10, y: 20, width: 900, height: 600)
        let lines = GridAssist.segments(in: feed, thirds: true, phi: false, diagonal: false)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].from, CGPoint(x: 310, y: 20))
        XCTAssertEqual(lines[0].to, CGPoint(x: 310, y: 620))
        XCTAssertEqual(lines[1].from, CGPoint(x: 10, y: 220))
        XCTAssertEqual(lines[1].to, CGPoint(x: 910, y: 220))
        XCTAssertEqual(lines[2].from, CGPoint(x: 610, y: 20))
        XCTAssertEqual(lines[2].to, CGPoint(x: 610, y: 620))
        XCTAssertEqual(lines[3].from, CGPoint(x: 10, y: 420))
        XCTAssertEqual(lines[3].to, CGPoint(x: 910, y: 420))
    }

    func testPhiSegmentsUseOpenZCineLiterals() {
        let feed = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let lines = GridAssist.segments(in: feed, thirds: false, phi: true, diagonal: false)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0].from.x, 382, accuracy: 0.001)
        XCTAssertEqual(lines[2].from.x, 618, accuracy: 0.001)
    }

    func testDiagonalIsBothFeedCorners() {
        let feed = CGRect(x: 0, y: 0, width: 100, height: 50)
        let lines = GridAssist.segments(in: feed, thirds: false, phi: false, diagonal: true)
        XCTAssertEqual(
            lines,
            [
                GridSegment(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50)),
                GridSegment(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 0, y: 50)),
            ]
        )
    }

    func testEmptySelectionDrawsNothing() {
        let feed = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(
            GridAssist.segments(in: feed, thirds: false, phi: false, diagonal: false).isEmpty
        )
    }

    func testPlaybackGridStaysInsideTheLetterboxedFeed() {
        let screen = CGRect(x: 0, y: 0, width: 844, height: 390)
        let feed = PlaybackVideoLayout.aspectFitRect(
            videoSize: CGSize(width: 3840, height: 2160), in: screen)
        XCTAssertLessThan(feed.width, screen.width)
        let lines = GridAssist.segments(in: feed, thirds: true, phi: true, diagonal: true)
        XCTAssertFalse(lines.isEmpty)
        for segment in lines {
            XCTAssertGreaterThanOrEqual(segment.from.x, feed.minX - 0.01)
            XCTAssertLessThanOrEqual(segment.from.x, feed.maxX + 0.01)
            XCTAssertGreaterThanOrEqual(segment.from.y, feed.minY - 0.01)
            XCTAssertLessThanOrEqual(segment.from.y, feed.maxY + 0.01)
            XCTAssertGreaterThanOrEqual(segment.to.x, feed.minX - 0.01)
            XCTAssertLessThanOrEqual(segment.to.x, feed.maxX + 0.01)
            XCTAssertGreaterThanOrEqual(segment.to.y, feed.minY - 0.01)
            XCTAssertLessThanOrEqual(segment.to.y, feed.maxY + 0.01)
        }
    }
}
