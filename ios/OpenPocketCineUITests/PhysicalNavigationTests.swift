import UIKit
import XCTest

/// Opt-in real-device navigation. This does not manufacture telemetry, start a
/// recording, or move a camera. Live-camera and thermal proof remain separate.
final class PhysicalNavigationTests: XCTestCase {
    func testPhysicalReportProblemBeforePairing() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires the opted-in physical navigation run")
        }
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        app.launchEnvironment["OPV_CONSENT_REVIEW_ID"] = UUID().uuidString
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = originalOrientation
        }
        let decline = app.buttons["reliability.consent.decline"]
        if decline.waitForExistence(timeout: 10) { decline.tap() }
        let report = app.buttons["pair.reportProblem"]
        let pair = app.buttons["cameras.pair"]
        expectation(for: NSPredicate { _, _ in report.exists || pair.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        // The launch splash can still cover controls already in the accessibility tree.
        Thread.sleep(forTimeInterval: 3)
        if !report.exists { pair.tap() }
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        func capturePairingScreen(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(report.isHittable)
            XCTAssertGreaterThanOrEqual(report.frame.height, 44)
            XCTAssertTrue(app.frame.contains(report.frame))
            capturePairingScreen("pairing-support-\(orientation.rawValue)")
            report.tap()
            XCTAssertTrue(app.textViews["What happened?"].waitForExistence(timeout: 5))
            capturePairingScreen("pairing-report-form-\(orientation.rawValue)")
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(report.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Find your camera"].firstMatch.exists)
        }
        app.buttons["Pairing help and diagnostics"].tap()
        XCTAssertTrue(app.buttons["Share Diagnostics"].waitForExistence(timeout: 5))
    }

    func testPhysicalSimplifiedSupportNavigation() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires the opted-in physical navigation run")
        }
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        app.launchEnvironment["OPV_CONSENT_REVIEW_ID"] = UUID().uuidString
        app.launch()
        let decline = app.buttons["reliability.consent.decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 15))
        attach(app, "support-first-launch-consent")
        decline.tap()
        app.terminate()
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(decline.exists, "A saved decline must not prompt again")
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = originalOrientation
        }
        let home = app.buttons["cameras.settings"]
        let live = app.buttons["monitor.system.settings"]
        expectation(for: NSPredicate { _, _ in home.exists || live.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        // The launch splash briefly intercepts touches while the home controls
        // already exist in the accessibility tree.
        Thread.sleep(forTimeInterval: 3)
        let settings = live.exists ? live : home
        XCTAssertTrue(settings.isHittable)
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let system = app.buttons["monitor.settings.tab.System"]
        XCTAssertTrue(system.waitForExistence(timeout: 10), "Settings did not open")
        system.tap()
        XCTAssertTrue(app.staticTexts["Report a problem"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Request a Feature"].exists)
        XCTAssertFalse(app.staticTexts["Save diagnostic report"].exists)
        attach(app, "support-simple")
        app.buttons["support.diagnostics.disclosure"].tap()
        XCTAssertTrue(
            app.staticTexts["Save diagnostic report"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "support-diagnostic-options")
        app.buttons["support.diagnostics.disclosure"].tap()
        app.buttons["support.report.open"].tap()
        XCTAssertTrue(app.textViews["What happened?"].waitForExistence(timeout: 5))
        attach(app, "support-native-form")
        let addImages = app.buttons["support.report.images.add"]
        for _ in 0..<3 where !addImages.isHittable { app.swipeUp() }
        XCTAssertTrue(addImages.isHittable)
        attach(app, "support-image-options")
        addImages.tap()
        let cancelPicker = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelPicker.waitForExistence(timeout: 10))
        cancelPicker.tap()
        XCTAssertTrue(addImages.waitForExistence(timeout: 5))
        let send = app.buttons["support.report.send"]
        for _ in 0..<3 where !send.exists { app.swipeUp() }
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled)
        app.buttons["Close"].firstMatch.tap()
        app.buttons["READ"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Privacy"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "support-offline-privacy")
    }

    func testPhysicalAssistTabsWithConnectedCamera() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Run just ios-physical-ui-test with a connected test device")
        }
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
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
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
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

    func testPhysicalPlaybackChromeAndCenteredHome() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires an attached review device")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        let media = app.buttons["cameras.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 2)
            let pair = app.buttons["cameras.pair"]
            XCTAssertTrue(pair.isHittable)
            XCTAssertEqual(pair.frame.midX, app.frame.midX, accuracy: 2)
            attach(app, "centered-home-\(orientation.rawValue)")
        }
        media.tap()
        let clip = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "monitor.media.clip.")
        ).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 10), "A cached clip is required")
        clip.tap()
        let back = app.buttons["Back to media"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 2)
            XCTAssertTrue(back.isHittable)
            XCTAssertEqual(back.frame.width, 54, accuracy: 1)
            for title in [
                "Favorite clip", "Clip information", "Share clip", "Delete clip from camera",
            ] {
                let button = app.buttons[title]
                XCTAssertTrue(button.isHittable, title)
                XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.minX + 12)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 12)
            }
            attach(app, "playback-chrome-\(orientation.rawValue)")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        let expand = app.buttons["monitor.assists.expand"]
        if expand.exists { expand.tap() }
        app.buttons["monitor.assist.LUT"].press(forDuration: 0.6)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let lut = inspector.buttons["LUT"].firstMatch
        XCTAssertTrue(lut.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(lut.frame.minX, 55)
        attach(app, "playback-assist-safe-area")
        app.buttons["Close LUT"].tap()
        app.buttons["Share clip"].tap()
        let scroll = app.scrollViews["monitor.share.optionsScroll"]
        for name in [
            "Google Drive", "Dropbox", "NAS (SMB)", "LucidLink", "Backblaze B2", "Vimeo Review",
        ] {
            let row = app.descendants(matching: .any)["monitor.share.upcoming.\(name)"].firstMatch
            for _ in 0..<5 where !row.isHittable { scroll.swipeUp() }
            XCTAssertTrue(row.exists, name)
        }
        attach(app, "playback-share-upcoming")
        app.buttons["monitor.share.close"].tap()
        back.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
