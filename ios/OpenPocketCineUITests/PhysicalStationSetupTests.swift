import XCTest

/// Opt-in real-device check for #406: connects the saved camera over its Wi-Fi or Hotspot
/// setup and reports whether the monitor went live. Needs the camera on and nearby and the
/// setup already added. Run with `TEST_RUNNER_OPV_PHYSICAL_STATION=wifi` (or
/// `phoneHotspot`); the device journal (`Documents/control-live.log`) holds the detail.
final class PhysicalStationSetupTests: XCTestCase {
    func testConnectOverSavedStationSetup() throws {
        guard let setup = ProcessInfo.processInfo.environment["OPV_PHYSICAL_STATION"] else {
            throw XCTSkip("Requires TEST_RUNNER_OPV_PHYSICAL_STATION=wifi or phoneHotspot")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        defer { app.terminate() }
        // Cold path: the camera starts on its own access point, as after a Camera Wi-Fi
        // session, so the Wi-Fi setup has to move it and wait for the router's address.
        if ProcessInfo.processInfo.environment["OPV_PHYSICAL_STATION_FROM_AP"] == "1" {
            launch(app)
            XCTAssertTrue(connect(app, over: "cameraWiFi", name: "ap"), "Camera Wi-Fi not live")
            app.terminate()
        }
        launch(app)
        let chip = app.buttons["cameras.setup.\(setup)"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "no saved \(setup) setup")
        // The launch splash can still cover controls already in the accessibility tree.
        Thread.sleep(forTimeInterval: 3)
        capture("station-before")
        chip.tap()
        let prompt = app.alerts["Turn on Personal Hotspot"]
        if prompt.waitForExistence(timeout: 2) { prompt.buttons["Connect"].tap() }
        let (isLive, seconds) = waitForLive(app, name: "station")
        XCTAssertTrue(isLive, "not live after \(seconds) s")
        if isLive {
            // Stays live, not just a first frame.
            Thread.sleep(forTimeInterval: 15)
            capture("station-live-15s")
            XCTAssertTrue(liveButton(app).exists)
        }
    }

    /// The whole Add setup › Wi-Fi flow: forget the saved Wi-Fi setup, add it back from the
    /// camera's scan (password from this app's Keychain), connect. Run with
    /// `TEST_RUNNER_OPV_PHYSICAL_ADD_WIFI=<network name>`.
    func testAddWiFiSetupFromCameraScan() throws {
        guard let ssid = ProcessInfo.processInfo.environment["OPV_PHYSICAL_ADD_WIFI"] else {
            throw XCTSkip("Requires TEST_RUNNER_OPV_PHYSICAL_ADD_WIFI=<network name>")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        launch(app)
        let saved = app.buttons["cameras.setup.wifi"].firstMatch
        if saved.waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 3)
            saved.press(forDuration: 1)
            let forget = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Forget'"))
                .firstMatch
            XCTAssertTrue(forget.waitForExistence(timeout: 5))
            forget.tap()
        }
        let add = app.buttons["cameras.addSetup"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        add.tap()
        app.buttons["addSetup.wifi"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        capture("add-wifi-scanning")
        // The scan returns the camera to its own Wi-Fi when it ends ("Scan again" appears).
        XCTAssertTrue(
            app.buttons["addSetup.rescan"].waitForExistence(timeout: 90), "scan did not end")
        capture("add-wifi-scanned")
        let network = app.buttons["addSetup.network.\(ssid)"].firstMatch
        XCTAssertTrue(network.waitForExistence(timeout: 5), "\(ssid) not listed")
        network.tap()
        let connect = app.buttons["addSetup.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.isEnabled, "password not remembered")
        connect.tap()
        let (isLive, seconds) = waitForLive(app, name: "add-wifi")
        XCTAssertTrue(isLive, "not live after \(seconds) s")
    }

    private func launch(_ app: XCUIApplication) {
        app.launch()
        let decline = app.buttons["reliability.consent.decline"]
        if decline.waitForExistence(timeout: 5) { decline.tap() }
    }

    private func connect(_ app: XCUIApplication, over setup: String, name: String) -> Bool {
        let chip = app.buttons["cameras.setup.\(setup)"].firstMatch
        guard chip.waitForExistence(timeout: 30) else { return false }
        Thread.sleep(forTimeInterval: 3)
        chip.tap()
        return waitForLive(app, name: name).0
    }

    private func liveButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(
                format: "identifier IN %@",
                ["monitor.assists.expand", "monitor.assists.collapse"])
        ).firstMatch
    }

    private func waitForLive(_ app: XCUIApplication, name: String) -> (Bool, Int) {
        let live = liveButton(app)
        let failed = app.staticTexts["NOT CONNECTED"]
        let started = Date()
        // iOS asks once per network before this app may join it.
        let join = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Join"]
        while Date().timeIntervalSince(started) < 150, !live.exists, !failed.exists {
            if join.exists { join.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        capture(live.exists ? "\(name)-live" : "\(name)-result")
        return (live.exists, Int(Date().timeIntervalSince(started)))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
