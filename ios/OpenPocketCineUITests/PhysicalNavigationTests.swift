import XCTest

/// Opt-in real-device navigation. This does not manufacture telemetry, start a
/// recording, or move a camera. Live-camera and thermal proof remain separate.
final class PhysicalNavigationTests: XCTestCase {
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
