import UIKit
import XCTest

/// Opt-in device proof using the existing connection and cached media. Never
/// records, moves a camera, deletes media, exports, or downloads an uncached file.
final class PhysicalDesqueezeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Run the opted-in physical UI recipe with an attached iPhone")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS_LIMIT_S"] = "600"
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testConnectedLiveDesqueezeKeepsPresenting() throws {
        guard app.buttons["monitor.system.record"].waitForExistence(timeout: 45) else {
            capture("desqueeze-live-unavailable")
            throw XCTSkip("No connected camera is presenting a live monitor")
        }
        try exerciseOptions(chip: revealDesqueeze(), name: "live") {
            let before = Int(self.snapshot()["pres"] ?? "0") ?? 0
            let progress = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    (Int(self.snapshot()["pres"] ?? "0") ?? 0) > before + 20
                }, object: self.app)
            XCTAssertEqual(
                XCTWaiter.wait(for: [progress], timeout: 5), .completed,
                "An enabled correction must keep presenting camera frames")
            let counters = XCTAttachment(
                string: self.snapshot().sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            counters.name = "desqueeze-live-counters"
            counters.lifetime = .keepAlways
            self.add(counters)
        }
    }

    func testCachedVideoDesqueezeOptions() throws {
        try openCachedMedia(category: "Videos")
        XCTAssertTrue(app.buttons["Back to media"].waitForExistence(timeout: 15))
        try exerciseOptions(chip: revealDesqueeze(), name: "cached-video") {
            XCTAssertTrue(self.app.buttons["Clip information"].isHittable)
            XCTAssertTrue(self.app.buttons["Back to media"].isHittable)
        }
    }

    func testCachedPhotoDesqueezeOptions() throws {
        try openCachedMedia(category: "Photos")
        let chip = app.descendants(matching: .any)["photo.desqueeze"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        try exerciseOptions(chip: chip, name: "cached-photo") {}
    }

    private func exerciseOptions(
        chip: XCUIElement, name: String, verifySource: () -> Void
    ) throws {
        let originalEnabled = try XCTUnwrap(chip.value as? String)
        chip.press(forDuration: 0.6)
        let close = app.buttons["Close Anamorphic Desqueeze"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let choices = ["1.1×", "1.2×", "1.33×", "1.5×", "1.6×", "1.8×", "2.0×", "Custom"]
        let originalChoice = try XCTUnwrap(choices.first { app.buttons[$0].firstMatch.isSelected })
        let originalDirection =
            app.buttons["Horizontal"].firstMatch.isSelected ? "Horizontal" : "Vertical"
        defer {
            if !close.exists { chip.press(forDuration: 0.6) }
            if close.waitForExistence(timeout: 5) {
                let original = app.buttons[originalChoice].firstMatch
                revealOption(original, upward: false)
                original.tap()
                let direction = app.buttons[originalDirection].firstMatch
                revealOption(direction)
                direction.tap()
                close.tap()
            }
            if chip.value as? String != originalEnabled { chip.tap() }
        }
        for title in choices { XCTAssertTrue(app.buttons[title].firstMatch.exists, title) }
        app.buttons["2.0×"].firstMatch.tap()
        let horizontal = app.buttons["Horizontal"].firstMatch
        revealOption(horizontal)
        horizontal.tap()
        XCTAssertTrue(horizontal.isSelected)
        capture("desqueeze-\(name)-options")
        close.tap()
        XCTAssertEqual(chip.value as? String, originalEnabled, "Holding must not toggle the assist")
        if originalEnabled == "Off" { chip.tap() }
        XCTAssertEqual(chip.value as? String, "On")
        verifySource()
        capture("desqueeze-\(name)-horizontal-2x")

        chip.press(forDuration: 0.6)
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let vertical = app.buttons["Vertical"].firstMatch
        revealOption(vertical)
        vertical.tap()
        XCTAssertTrue(vertical.isSelected)
        close.tap()
        verifySource()
        capture("desqueeze-\(name)-vertical-2x")
        chip.tap()
        XCTAssertEqual(chip.value as? String, "Off")
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

    private func openCachedMedia(category: String) throws {
        let home = app.buttons["cameras.media"]
        let live = app.buttons["monitor.system.media"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in home.isHittable || live.isHittable }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        (live.isHittable ? live : home).tap()
        let filter = app.buttons.containing(.staticText, identifier: category).firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        let clips = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'monitor.media.clip.'"))
        var cached: XCUIElement?
        for _ in 0..<4 {
            cached = clips.allElementsBoundByIndex.first {
                $0.isHittable
                    && ($0.staticTexts["ON PHONE"].exists || $0.staticTexts["PROXY"].exists)
            }
            if cached != nil { break }
            app.swipeUp()
        }
        guard let cached else {
            capture("desqueeze-cached-\(category.lowercased())-unavailable")
            throw XCTSkip("No cached \(category.lowercased()) are available on this device")
        }
        cached.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
    }

    private func revealOption(_ element: XCUIElement, upward: Bool = true) {
        let inspector = app.otherElements["monitor.inspector"]
        for _ in 0..<3 where !element.isHittable {
            if upward { inspector.swipeUp() } else { inspector.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func snapshot() -> [String: String] {
        let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
        guard probe.exists, let value = probe.value as? String else { return [:] }
        return Dictionary(
            value.split(separator: " ").compactMap { token in
                let parts = token.split(separator: "=", maxSplits: 1)
                return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
            }, uniquingKeysWith: { _, new in new })
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
