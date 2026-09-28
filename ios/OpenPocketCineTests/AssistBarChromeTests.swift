import SwiftUI
import XCTest

@testable import OpenPocketCine

final class AssistBarChromeTests: XCTestCase {
    func testLongPressEnabledForRemainingTools() {
        let tapOnly: Set<LiveAssistTool> = [.evMeter, .level]
        for tool in LiveAssistTool.settingsCases where !tapOnly.contains(tool) {
            XCTAssertTrue(tool.hasConfiguration, "\(tool.rawValue) should open options")
        }
        // Audio has local presentation options; mirror picks its flip axes.
        XCTAssertTrue(LiveAssistTool.audioMeters.hasConfiguration)
        XCTAssertTrue(LiveAssistTool.mirror.hasConfiguration)
        XCTAssertFalse(LiveAssistTool.level.hasConfiguration)
        XCTAssertTrue(LiveAssistTool.desqueeze.hasConfiguration)
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
}
