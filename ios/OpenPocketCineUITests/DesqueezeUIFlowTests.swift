import UIKit
import XCTest

/// Exercises the production assist controls with simulator presentation fixtures.
/// Screenshots remain in the local xcresult; this does not qualify camera performance.
final class DesqueezeUIFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let presets = ["1.1×", "1.2×", "1.33×", "1.5×", "1.6×", "1.8×", "2.0×"]

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
            throw XCTSkip("Presentation fixtures are simulator-only")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        if let clip = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"] {
            app.launchEnvironment["OPV_SIM_FEED_CLIP"] = clip
        }
    }

    override func tearDown() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testLivePresetsCustomFactorAndDirectionSurviveRotation() throws {
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(.landscapeLeft)
        let chip = try revealDesqueeze()
        let initial = try XCTUnwrap(chip.value as? String)
        chip.tap()
        waitForValue(chip, initial == "On" ? "Off" : "On")
        chip.tap()
        waitForValue(chip, initial)
        chip.press(forDuration: 0.6)
        let close = app.buttons["Close Anamorphic Desqueeze"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))

        for title in presets {
            let preset = app.buttons[title].firstMatch
            XCTAssertTrue(preset.isHittable, title)
            preset.tap()
            waitForSelection(preset)
            XCTAssertFalse(app.sliders["Custom squeeze factor"].exists)
        }

        app.buttons["Custom"].firstMatch.tap()
        let slider = app.sliders["Custom squeeze factor"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.57)
        let readout = app.staticTexts["desqueeze.factor"]
        let customValue = try XCTUnwrap(
            Double(readout.label.replacingOccurrences(of: "×", with: "")))
        XCTAssertEqual(customValue, 1.57, accuracy: 0.04)
        XCTAssertEqual(customValue * 100, (customValue * 100).rounded(), accuracy: 0.0001)
        XCTAssertEqual(slider.value as? String, readout.label)
        let remembered = readout.label
        app.buttons["1.33×"].firstMatch.tap()
        app.buttons["Custom"].firstMatch.tap()
        XCTAssertEqual(readout.label, remembered, "Custom must retain its own factor")

        for title in ["Horizontal", "Vertical"] {
            let direction = app.buttons[title].firstMatch
            revealOption(direction)
            direction.tap()
            waitForSelection(direction)
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeRight, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            waitForOrientation(orientation)
            XCTAssertTrue(close.isHittable)
            let vertical = app.buttons["Vertical"].firstMatch
            revealOption(vertical)
            XCTAssertTrue(vertical.isSelected)
            capture("desqueeze-custom-\(orientation.rawValue)")
        }
        close.tap()
        waitForValue(chip, initial)
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        chip.press(forDuration: 0.6)
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        revealOption(readout)
        XCTAssertEqual(readout.label, remembered)
        XCTAssertTrue(app.buttons["Custom"].firstMatch.isSelected)
        close.tap()
    }

    func testCachedPlaybackExposesTheSameDesqueezeOptions() throws {
        guard let clip = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"],
            FileManager.default.fileExists(atPath: clip)
        else { throw XCTSkip("Pass OPV_SIM_FEED_CLIP pointing to a generated review video") }
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "playback"
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(.landscapeLeft)
        XCTAssertTrue(app.buttons["Back to media"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["monitor.review.cacheError"].exists)
        let chip = try revealDesqueeze()
        if chip.value as? String == "Off" { chip.tap() }
        waitForValue(chip, "On")
        chip.press(forDuration: 0.6)
        let close = app.buttons["Close Anamorphic Desqueeze"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        for title in presets + ["Custom"] { XCTAssertTrue(app.buttons[title].firstMatch.exists) }
        app.buttons["2.0×"].firstMatch.tap()
        let horizontal = app.buttons["Horizontal"].firstMatch
        revealOption(horizontal)
        horizontal.tap()
        waitForSelection(horizontal)
        capture("desqueeze-playback-options")
        close.tap()
        waitForValue(chip, "On")
        XCTAssertTrue(app.buttons["Back to media"].isHittable)
        XCTAssertTrue(app.buttons["Clip information"].isHittable)
        capture("desqueeze-playback-horizontal-2x")
        chip.tap()
        waitForValue(chip, "Off")
    }

    private func revealDesqueeze() throws -> XCUIElement {
        let expand = app.buttons["monitor.assists.expand"]
        if expand.waitForExistence(timeout: 10) { expand.tap() }
        let chip = app.buttons["monitor.assist.DE-SQ"]
        for _ in 0..<5 where !chip.isHittable {
            let palette = app.scrollViews.allElementsBoundByIndex.first {
                $0.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'monitor.assist.'"))
                    .count > 0
            }
            try XCTUnwrap(palette, "View Assist palette must be scrollable").swipeLeft()
        }
        XCTAssertTrue(chip.isHittable)
        return chip
    }

    private func revealOption(_ element: XCUIElement) {
        let inspector = app.otherElements["monitor.inspector"]
        for _ in 0..<3 where !element.isHittable { inspector.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func waitForSelection(_ element: XCUIElement) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 3), .completed)
    }

    private func waitForOrientation(_ orientation: UIDeviceOrientation) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                orientation == .portrait
                    ? self.app.frame.height > self.app.frame.width
                    : self.app.frame.width > self.app.frame.height
            }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
