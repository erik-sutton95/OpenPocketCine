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
        let display = app.buttons["monitor.system.display"]
        if (display.value as? String)?.contains("DISP 2") == true { display.tap() }
        let chip = try revealEV(in: app)
        if chip.value as? String != "On" { chip.tap() }
        app.buttons["monitor.assists.collapse"].tap()
        let meter = app.otherElements["monitor.ev.meter"]
        let valid = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
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
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let before = presented()
            let progress = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in presented() > before + 20 }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [progress], timeout: 5), .completed)
            XCTAssertTrue(app.frame.contains(meter.frame))
            assertMeterClearsToolbar(meter, in: app)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "ev-meter-physical-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCameraMeterIsFixedAndOnlyVisibleInDispOne() throws {
        #if !targetEnvironment(simulator)
            throw XCTSkip("Presentation fixtures are simulator-only")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_METERED_EV"] = "14"
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let meter = app.otherElements["monitor.ev.meter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 15))
        XCTAssertEqual(meter.value as? String, "Camera exposure −0.7 EV")
        XCUIDevice.shared.orientation = .landscapeLeft
        let chip = try revealEV(in: app)
        XCTAssertEqual(chip.value as? String, "On")
        chip.tap()
        XCTAssertFalse(meter.exists)
        chip.tap()
        XCTAssertTrue(meter.waitForExistence(timeout: 3))
        assertMeterClearsToolbar(meter, in: app)
        let toolbar = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        toolbar.name = "camera-ev-toolbar"
        toolbar.lifetime = .keepAlways
        add(toolbar)
        app.buttons["monitor.assists.collapse"].tap()
        XCTAssertFalse(app.otherElements["monitor.ev.resize"].exists)
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(app.frame.contains(meter.frame))
            XCTAssertEqual(meter.frame.width, 28, accuracy: 1)
            XCTAssertGreaterThan(meter.frame.height, meter.frame.width * 1.5)
            XCTAssertLessThan(meter.frame.midX, app.frame.midX)
            assertMeterClearsToolbar(meter, in: app)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "camera-ev-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let display = app.buttons["monitor.system.display"]
        display.tap()
        XCTAssertEqual(display.value as? String, "DISP 2 clean")
        XCTAssertFalse(meter.exists)
        display.tap()
        XCTAssertTrue(meter.waitForExistence(timeout: 3))
        XCTAssertEqual(meter.value as? String, "Camera exposure −0.7 EV")
    }

    private func assertMeterClearsToolbar(_ meter: XCUIElement, in app: XCUIApplication) {
        for button in app.buttons.allElementsBoundByIndex
        where button.identifier.hasPrefix("monitor.assist") && button.isHittable {
            XCTAssertFalse(meter.frame.intersects(button.frame), button.identifier)
        }
    }

    private func revealEV(in app: XCUIApplication) throws -> XCUIElement {
        let expand = app.buttons["monitor.assists.expand"]
        if expand.waitForExistence(timeout: 5) { expand.tap() }
        let chip = app.buttons["monitor.assist.EV"]
        for _ in 0..<5 where !chip.isHittable {
            let palette = app.scrollViews.allElementsBoundByIndex.first {
                $0.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'monitor.assist.'"))
                    .count > 0
            }
            try XCTUnwrap(palette).swipeLeft()
        }
        XCTAssertTrue(chip.isHittable)
        return chip
    }

    func testMissingCameraEVShowsUnavailable() throws {
        #if !targetEnvironment(simulator)
            throw XCTSkip("Presentation fixtures are simulator-only")
        #endif
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launch()
        defer { app.terminate() }
        let meter = app.otherElements["monitor.ev.meter"]
        XCTAssertTrue(meter.waitForExistence(timeout: 15))
        XCTAssertEqual(meter.value as? String, "Unavailable, waiting for camera EV")
    }
}
