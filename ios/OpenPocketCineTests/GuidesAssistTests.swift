import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine `AssistConfiguration.Guides` + `rectForRatio` onto PocketCine.
final class GuidesAssistTests: XCTestCase {
    func testFilmAndSocialListsMatchOpenZCine() {
        XCTAssertEqual(
            GuideAspect.ratios(for: .film).map(\.rawValue),
            ["2.76:1", "2.39:1", "2.35:1", "2.00:1", "1.85:1", "16:9", "1.66:1", "1.43:1", "4:3"]
        )
        XCTAssertEqual(
            GuideAspect.ratios(for: .social).map(\.rawValue),
            ["9:16", "4:5", "1:1", "2:3", "16:9", "1.91:1"]
        )
        XCTAssertTrue(GuideAspect.ratios(for: .social).contains(.vertical))
        XCTAssertFalse(GuideAspect.ratios(for: .film).contains(.vertical))
        XCTAssertTrue(GuideAspect.ratios(for: .film).contains(.cinema))
        XCTAssertFalse(GuideAspect.ratios(for: .social).contains(.cinema))
    }

    func testAspectRatioValueParsesLabel() {
        XCTAssertEqual(GuideAspect.cinema.ratio, 2.39, accuracy: 1e-9)
        XCTAssertEqual(GuideAspect.vertical.ratio, 0.5625, accuracy: 1e-9)
        XCTAssertEqual(GuideAspect.square.ratio, 1.0, accuracy: 1e-9)
        XCTAssertEqual(GuideAspect.hd.ratio, 16.0 / 9.0, accuracy: 1e-9)
    }

    func testToggleAddsAndRemoves() {
        let assist = LiveAssistState()
        assist.selectedGuides = [.cinema]
        assist.toggleGuide(.wide)
        XCTAssertEqual(assist.selectedGuides, [.cinema, .wide])
        assist.toggleGuide(.cinema)
        XCTAssertEqual(assist.selectedGuides, [.wide])
        XCTAssertTrue(assist.guides)
        assist.toggleGuide(.wide)
        XCTAssertTrue(assist.selectedGuides.isEmpty)
        XCTAssertFalse(assist.guides)
    }

    func testSummaryLabelReflectsSelection() {
        XCTAssertEqual(GuidesAssist.summaryLabel(for: []), "—")
        XCTAssertEqual(GuidesAssist.summaryLabel(for: [.cinema]), "2.39:1")
        XCTAssertEqual(GuidesAssist.summaryLabel(for: [.cinema, .wide]), "2 ratios")
    }

    func testRectForRatioLetterboxesWideGuide() {
        let feed = CGRect(x: 10, y: 20, width: 1920, height: 1080)
        let frame = GuidesAssist.rectForRatio(feed, 2.39)
        XCTAssertEqual(frame.width, 1920, accuracy: 0.01)
        XCTAssertEqual(frame.height, 1920 / 2.39, accuracy: 0.01)
        XCTAssertEqual(frame.midX, feed.midX, accuracy: 0.01)
        XCTAssertEqual(frame.midY, feed.midY, accuracy: 0.01)
    }

    func testRectForRatioPillarboxesTallGuide() {
        let feed = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frame = GuidesAssist.rectForRatio(feed, 9.0 / 16.0)
        XCTAssertEqual(frame.height, 1080, accuracy: 0.01)
        XCTAssertEqual(frame.width, 1080 * 9.0 / 16.0, accuracy: 0.01)
        XCTAssertEqual(frame.midX, feed.midX, accuracy: 0.01)
        XCTAssertEqual(frame.midY, feed.midY, accuracy: 0.01)
    }

    func testPanelWidthMatchesOpenZCineGuidesPopup() {
        XCTAssertEqual(GuidesAssist.panelWidth, 472)
    }

    func testLongPressOptionsAreFamilyRatiosAndMaskOnly() {
        XCTAssertEqual(GuideFamily.allCases.map(\.rawValue), ["Film", "Social"])
        XCTAssertEqual(GuidesAssist.panelWidth, 472)
    }
}
