import UIKit
import XCTest

/// Presentation and interaction proof only; camera metering needs a physical camera.
final class EVMeterUIFlowTests: XCTestCase {
    func testPhysicalMeterHasAReadingAndKeepsPresenting() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires an attached iPhone and available camera")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS_LIMIT_S"] = "180"
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        guard app.buttons["monitor.system.record"].waitForExistence(timeout: 45) else {
            throw XCTSkip("No connected camera is presenting a live monitor")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let expand = app.buttons["monitor.assists.expand"]
        if expand.waitForExistence(timeout: 10) { expand.tap() }
        let chip = app.buttons["monitor.assist.EV"]
        for _ in 0..<5 where !chip.isHittable {
            let palette = app.scrollViews.allElementsBoundByIndex.first {
                $0.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'monitor.assist.'")).count > 0
            }
            try XCTUnwrap(palette).swipeLeft()
        }
        let wasEnabled = chip.value as? String == "On"
        if !wasEnabled { chip.tap() }
        defer { if !wasEnabled, chip.isHittable { chip.tap() } }
        let meter = app.otherElements["monitor.ev.meter"]
        let valid = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard meter.exists, let value = meter.value as? String else { return false }
            return !value.contains("Unavailable")
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [valid], timeout: 15), .completed)
        func snapshot() -> String {
            let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
            return probe.exists ? probe.value as? String ?? "" : ""
        }
        func presented() -> Int {
            let token = snapshot().split(separator: " ").first { $0.hasPrefix("pres=") }
            return token.flatMap { Int($0.dropFirst(5)) } ?? 0
        }
        let readingAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        readingAttachment.name = "ev-meter-physical-reading"
        readingAttachment.lifetime = .keepAlways
        add(readingAttachment)
        if snapshot().contains("halt=thermal") {
            throw XCTSkip("EV reading observed; phone thermal state prevents cadence qualification")
        }
        meter.tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let before = presented()
            let progress = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in presented() > before + 20 }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [progress], timeout: 5), .completed)
            XCTAssertTrue(app.frame.contains(meter.frame))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "ev-meter-physical-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testUnavailableMeterMovesResizesAndOpensHelp() throws {
        #if !targetEnvironment(simulator)
            throw XCTSkip("Presentation fixtures are simulator-only")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        expand.tap()
        let chip = app.buttons["monitor.assist.EV"]
        for _ in 0..<5 where !chip.isHittable {
            let palette = app.scrollViews.allElementsBoundByIndex.first {
                $0.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'monitor.assist.'"))
                    .count > 0
            }
            try XCTUnwrap(palette).swipeLeft()
        }
        XCTAssertTrue(chip.isHittable)
        chip.tap()
        let meter = app.otherElements["monitor.ev.meter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        XCTAssertTrue((meter.value as? String)?.contains("Unavailable") == true)
        // The expanded palette's dismiss plane intentionally sits above scopes.
        meter.tap()
        let start = meter.frame
        let center = meter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: -80, dy: -35)))
        XCTAssertLessThan(meter.frame.midX, start.midX - 30)
        let beforeResize = meter.frame
        let grip = meter.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
        grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 50, dy: 20)))
        XCTAssertGreaterThan(meter.frame.width, beforeResize.width + 15)
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.frame.contains(meter.frame))
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "ev-meter-unavailable-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        if expand.isHittable { expand.tap() }
        chip.press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["Close EV Meter"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Measures median picture brightness'")
            ).firstMatch.exists)
    }
}
