import SwiftUI
import XCTest

@testable import OpenPocketCine

final class AssistBarChromeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LiveChromeMetrics.scale = 1
    }

    func testToolbarOmitsLevelAndDesqueeze() {
        XCTAssertEqual(
            LiveAssistTool.toolbarCases,
            [
                .lut, .peaking, .falseColor, .zebra, .waveform, .parade, .histogram,
                .vectorscope, .trafficLights, .guides, .grid, .crosshair, .mirror,
            ]
        )
        XCTAssertFalse(LiveAssistTool.toolbarCases.contains(.level))
        XCTAssertFalse(LiveAssistTool.toolbarCases.contains(.desqueeze))
        XCTAssertFalse(LiveAssistTool.settingsCases.contains(.level))
        XCTAssertFalse(LiveAssistTool.settingsCases.contains(.desqueeze))
        XCTAssertEqual(LiveAssistTool.settingsCases.last, .audioMeters)
    }

    func testLongPressEnabledForRemainingTools() {
        let tapOnly: Set<LiveAssistTool> = [.audioMeters, .mirror]
        for tool in LiveAssistTool.settingsCases where !tapOnly.contains(tool) {
            XCTAssertTrue(tool.hasConfiguration, "\(tool.rawValue) should open options")
        }
        // OpenZCine AUDIO / MIRROR are tap-only — no channel picker, no H/V flip.
        XCTAssertFalse(LiveAssistTool.audioMeters.hasConfiguration)
        XCTAssertFalse(LiveAssistTool.mirror.hasConfiguration)
        XCTAssertFalse(LiveAssistTool.level.hasConfiguration)
        XCTAssertFalse(LiveAssistTool.desqueeze.hasConfiguration)
    }

    func testPopupParksAboveIconWhenThereIsRoom() {
        let origin = AssistLongPressChrome.panelOrigin(
            viewport: CGSize(width: 874, height: 402),
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: 400, height: 180)
        )
        XCTAssertEqual(origin.x, 16, accuracy: 0.05)
        XCTAssertEqual(origin.y, 330 - 10 - 180, accuracy: 0.05)
    }

    func testTallPopupCapsAboveToolbarBelowTopDeck() {
        let box = AssistLongPressChrome.panelBox(
            viewport: CGSize(width: 874, height: 402),
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: 400, height: 400),
            toolbar: CGRect(x: 16, y: 330, width: 276, height: 58),
            safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0),
            ceilingY: 60 + 8
        )
        XCTAssertEqual(box.width, 400, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(box.x, 59 + 4)
        XCTAssertEqual(box.y, 68, accuracy: 0.05)
        XCTAssertEqual(box.maxHeight, 330 - 10 - 68, accuracy: 0.05)
        XCTAssertLessThan(box.maxHeight, 400)
        XCTAssertLessThanOrEqual(box.y + box.maxHeight, 330 - 10 + 0.05)
    }

    func testFPSHoldIgnoresHundredthTick() {
        XCTAssertEqual(LiveChromeReadout.holdFPS("25.13", displayed: "25.00"), "25.00")
        XCTAssertEqual(LiveChromeReadout.holdFPS("24.70", displayed: "25.00"), "25.00")
        XCTAssertEqual(LiveChromeReadout.holdFPS("25.50", displayed: "25.00"), "25.50")
        XCTAssertEqual(LiveChromeReadout.holdFPS("RECOV", displayed: "25.00"), "RECOV")
        XCTAssertEqual(LiveChromeReadout.holdFPS("25.00", displayed: "LINK"), "25.00")
        XCTAssertEqual(LiveChromeReadout.holdFPS("—", displayed: "25.00"), "—")
    }

    func testZoomLabelHoldIgnoresTenthJitter() {
        XCTAssertFalse(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.08, pinching: false))
        XCTAssertTrue(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.2, pinching: false))
        XCTAssertTrue(LiveZoomLabelHold.shouldReplace(held: 1.0, next: 1.08, pinching: true))
    }

    func testPopupFollowsIconWhenLandscapeFlips() {
        let viewport = CGSize(width: 874, height: 402)
        let panel = CGSize(width: 400, height: 180)
        let leftIcon = CGRect(x: 80, y: 330, width: 48, height: 58)
        let rightIcon = CGRect(x: viewport.width - 80 - 48, y: 330, width: 48, height: 58)
        let leftBar = CGRect(x: 16, y: 330, width: 276, height: 58)
        let rightBar = CGRect(
            x: viewport.width - 16 - 276, y: 330, width: 276, height: 58)
        let leading = AssistLongPressChrome.panelBox(
            viewport: viewport, anchor: leftIcon, panel: panel, toolbar: leftBar)
        let trailing = AssistLongPressChrome.panelBox(
            viewport: viewport, anchor: rightIcon, panel: panel, toolbar: rightBar)
        XCTAssertLessThan(leading.x + leading.width / 2, viewport.width / 2)
        XCTAssertGreaterThan(trailing.x + trailing.width / 2, viewport.width / 2)
        XCTAssertGreaterThan(abs(trailing.x - leading.x), 200)
    }

    func testPeakingMenuFitsTheLandscapeWellWithoutAScrollGuess() {
        let well = AssistLongPressChrome.panelBox(
            viewport: CGSize(width: 874, height: 402),
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: 400, height: 220),
            toolbar: CGRect(x: 16, y: 330, width: 276, height: 58),
            ceilingY: 68
        )
        XCTAssertGreaterThan(well.maxHeight, 220)
        XCTAssertEqual(well.y + 220, 330 - 10, accuracy: 0.05)
    }

    func testGuidesPopupIsWider() {
        XCTAssertEqual(AssistLongPressChrome.preferredWidth(for: .guides), 472)
        XCTAssertEqual(AssistLongPressChrome.preferredWidth(for: .peaking), 400)
        XCTAssertEqual(AssistLongPressChrome.preferredWidth(for: .lut), 400)
    }

    func testLUTPopupKeepsTrailingGlassInsideViewport() {
        let viewport = CGSize(width: 874, height: 402)
        let box = AssistLongPressChrome.panelBox(
            viewport: viewport,
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: LUTAssist.longPressPanelWidth, height: 280),
            toolbar: CGRect(x: 16, y: 330, width: 276, height: 58),
            safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0),
            ceilingY: 60 + 8
        )
        XCTAssertEqual(box.width, LUTAssist.longPressPanelWidth, accuracy: 0.05)
        XCTAssertGreaterThanOrEqual(box.x, 59 + 4)
        XCTAssertLessThanOrEqual(
            box.x + box.width,
            viewport.width - LiveChromeMetrics.chromeTrailing + 0.05
        )
    }

    func testLUTLandscapeWellKeepsPinnedSplitComparisonOnScreen() {
        // Header + pad + 50/50 stay outside the catalog scroll. The landscape
        // well must still have room for the catalog above that pinned chrome.
        let well = AssistLongPressChrome.panelBox(
            viewport: CGSize(width: 874, height: 402),
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: LUTAssist.longPressPanelWidth, height: 400),
            toolbar: CGRect(x: 16, y: 330, width: 276, height: 58),
            safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0),
            ceilingY: 60 + 8
        )
        // Header + pad + one footer row (exposure stepper inline with 50/50).
        let pinnedChrome: CGFloat = 16 + 32 + 14 + 40 + 16
        XCTAssertGreaterThan(
            well.maxHeight - pinnedChrome, 100,
            "catalog well must still show a drum row above the pinned exposure / 50/50 footer")
        XCTAssertLessThanOrEqual(well.y + well.maxHeight, 330 - 10 + 0.05)
    }

    func testTallLUTPopupStartsBelowTopDeck() {
        let ceiling: CGFloat = 60 + 8
        let box = AssistLongPressChrome.panelBox(
            viewport: CGSize(width: 874, height: 402),
            anchor: CGRect(x: 80, y: 330, width: 48, height: 58),
            panel: CGSize(width: LUTAssist.longPressPanelWidth, height: 360),
            toolbar: CGRect(x: 16, y: 330, width: 276, height: 58),
            safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 0),
            ceilingY: ceiling
        )
        XCTAssertGreaterThanOrEqual(box.y, ceiling)
        XCTAssertLessThan(box.maxHeight, 360)
        XCTAssertLessThanOrEqual(box.y + box.maxHeight, 330 - 10 + 0.05)
    }
}
