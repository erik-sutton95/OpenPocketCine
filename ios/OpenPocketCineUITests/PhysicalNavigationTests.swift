import XCTest

/// Opt-in real-device navigation. This does not manufacture telemetry, start a
/// recording, or move a camera. Live-camera and thermal proof remain separate.
final class PhysicalNavigationTests: XCTestCase {
    func testPhysicalAssistTabsWithConnectedCamera() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Run just ios-physical-ui-test with a connected test device")
        }
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        let expand = app.buttons["monitor.assists.expand"]
        guard expand.waitForExistence(timeout: 15) else {
            throw XCTSkip("No connected camera is presenting a live monitor")
        }
        expand.tap()
        app.buttons["monitor.assist.PEAK"].press(forDuration: 0.55)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let frame = inspector.frame
        for _ in 0..<15 {
            for title in ["False Color", "Zebra", "Peaking"] {
                app.buttons[title].firstMatch.tap()
                XCTAssertEqual(app.state, .runningForeground)
                XCTAssertTrue(app.buttons["Close \(title)"].exists)
                XCTAssertEqual(inspector.frame.width, frame.width, accuracy: 1)
                XCTAssertEqual(inspector.frame.height, frame.height, accuracy: 1)
            }
        }
        attach(app, "physical-assist-tab-stress")
        app.buttons["Close Peaking"].tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
    }

    func testPhysicalSettingsAndMediaNavigation() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Run just ios-physical-ui-test with a connected test device")
        }
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        let homeSettings = app.buttons["cameras.settings"]
        let liveSettings = app.buttons["monitor.system.settings"]
        let ready = NSPredicate { _, _ in homeSettings.exists || liveSettings.exists }
        expectation(for: ready, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        let wasLive = liveSettings.exists
        (wasLive ? liveSettings : homeSettings).tap()
        XCTAssertTrue(app.staticTexts["Operator Setup"].firstMatch.waitForExistence(timeout: 10))
        attach(app, "physical-settings")
        let back = app.buttons[wasLive ? "Back to live" : "Your cameras"].firstMatch
        if back.exists { back.tap() } else { app.buttons["Close"].firstMatch.tap() }
        let media = app.buttons[wasLive ? "monitor.system.media" : "cameras.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 10))
        media.tap()
        XCTAssertTrue(app.staticTexts["Media"].firstMatch.waitForExistence(timeout: 10))
        attach(app, "physical-media")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
