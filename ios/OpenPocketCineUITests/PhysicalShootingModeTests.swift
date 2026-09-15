import UIKit
import XCTest

/// Opt-in real camera proof. Changes shooting mode, zoom and format; never captures media.
final class PhysicalShootingModeTests: XCTestCase {
    func testPhotoChromeAndTeleSlowMotion200() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires the connected Pocket 4 Pro and an opted-in physical run")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_FEED_STRESS"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS_LIMIT_S"] = "600"
        addUIInterruptionMonitor(withDescription: "Authorized camera connection") { alert in
            for title in ["Join", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        XCUIDevice.shared.orientation = .landscapeRight
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
        let mode = app.buttons["monitor.capture.mode"]
        let connectDeadline = Date().addingTimeInterval(60)
        while !mode.exists && Date() < connectDeadline {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for title in ["Join", "Allow", "OK"] {
                let button = springboard.alerts.buttons[title].firstMatch
                if button.exists { button.tap() }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(mode.exists, "Saved camera must reconnect")
        XCTAssertEqual(snapshot(app)["rec"], "0", "Camera must be idle")
        let initialMode = mode.value as? String ?? "Video"
        defer {
            closePanel(app)
            selectMode(initialMode, app: app)
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }

        selectMode("Photo", app: app)
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)
            XCTAssertFalse(app.buttons["monitor.capture.color"].exists)
            XCTAssertFalse(app.buttons["monitor.capture.audio"].exists)
            XCTAssertTrue(app.buttons["monitor.capture.iso"].exists)
            XCTAssertTrue(app.buttons["monitor.capture.wb"].exists)
            XCTAssertTrue(app.buttons["monitor.capture.shutter"].exists)
            let format = app.buttons["monitor.capture.format"]
            if format.exists {
                XCTAssertFalse(
                    (format.value as? String ?? "").contains("p"), "Photo must not show video fps")
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "photo-mode-\(orientation.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 1)
        selectMode("SlowMo", app: app)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        let zoom = app.buttons["monitor.system.zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 10))
        if !zoom.label.contains("3") { zoom.tap() }
        wait(until: { zoom.label.contains("3") }, "Tele lens must reach 3x")
        Thread.sleep(forTimeInterval: 3)
        app.buttons["monitor.capture.format"].tap()
        let drum = app.descendants(matching: .any)["Value"].firstMatch
        XCTAssertTrue(drum.waitForExistence(timeout: 5))
        for _ in 0..<6 where (drum.value as? String) != "200p" {
            step(drum, direction: 1)
        }
        XCTAssertEqual(drum.value as? String, "200p")
        step(drum, direction: 1)
        XCTAssertEqual(drum.value as? String, "200p", "Tele format list must end at 200p")
        closePanel(app)
        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 1)
        wait(
            until: {
                (app.buttons["monitor.capture.format"].value as? String ?? "").contains("200p")
            }, "Format readout must show 200p after camera confirmation")
        let before = Int(snapshot(app)["pres"] ?? "0") ?? 0
        wait(
            until: { (Int(self.snapshot(app)["pres"] ?? "0") ?? 0) > before },
            "Live picture must keep progressing")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "slow-motion-tele-200p"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        zoom.tap()
        wait(until: { zoom.label.contains("1") }, "Restore wide lens")
        selectMode("Video", app: app)
        XCTAssertTrue(app.buttons["monitor.capture.color"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["monitor.capture.audio"].exists)
    }

    private func selectMode(_ wanted: String, app: XCUIApplication) {
        closePanel(app)
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        let mode = app.buttons["monitor.capture.mode"]
        if mode.exists {
            mode.tap()
        } else {
            let setup = app.buttons["monitor.capture.format"]
            guard setup.waitForExistence(timeout: 5) else {
                XCTFail("Capture setup missing")
                return
            }
            setup.tap()
            let category = app.buttons["Mode"].firstMatch
            guard category.waitForExistence(timeout: 5) else {
                XCTFail("Mode category missing")
                return
            }
            category.tap()
        }
        let drum = app.descendants(matching: .any)["Value"].firstMatch
        guard drum.waitForExistence(timeout: 5) else {
            XCTFail("Mode picker missing")
            return
        }
        let order = ["SlowMo", "Video", "TimeLapse", "Photo", "HyperLapse", "SuperNight"]
        for _ in 0..<8 {
            let current = drum.value as? String ?? ""
            if current == wanted { break }
            guard let from = order.firstIndex(of: current), let to = order.firstIndex(of: wanted)
            else {
                XCTFail("Unexpected mode selection: \(current)")
                return
            }
            step(drum, direction: to > from ? 1 : -1)
        }
        XCTAssertEqual(drum.value as? String, wanted)
        closePanel(app)
        XCUIDevice.shared.orientation = .landscapeRight
        Thread.sleep(forTimeInterval: 1)
        wait(until: { (mode.value as? String) == wanted }, "Camera must report \(wanted)")
    }

    private func step(_ drum: XCUIElement, direction: CGFloat) {
        let center = drum.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(
            forDuration: 0.1,
            thenDragTo: center.withOffset(
                CGVector(dx: -direction * 56, dy: 0)))
        Thread.sleep(forTimeInterval: 1)
    }

    private func closePanel(_ app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() }
    }

    private func wait(until predicate: @escaping () -> Bool, _ message: String) {
        let condition = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 20), .completed, message)
    }

    private func snapshot(_ app: XCUIApplication) -> [String: String] {
        let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
        guard probe.exists, let value = probe.value as? String else { return [:] }
        return Dictionary(
            value.split(separator: " ").compactMap { token in
                let parts = token.split(separator: "=", maxSplits: 1)
                return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
            }, uniquingKeysWith: { _, new in new })
    }
}
