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

    /// Connect the host using the first offered current/saved network while a scan is
    /// active, then close. Credentials stay in the device's Keychain; this never records.
    func testMultiviewSharedWiFiSetup() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_WIFI"] == "1" else {
            throw XCTSkip("Requires TEST_RUNNER_OPV_PHYSICAL_MULTIVIEW_WIFI=1")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        openMultiviewOnSavedWiFi(app)
        // Closing here also verifies AP return for the camera used by the scan.
        XCTAssertTrue(closeMultiview(app))
    }

    /// Recover a prior failed physical check without joining a new camera network.
    func testMultiviewPendingCleanup() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_WIFI"] == "1" else {
            throw XCTSkip("Requires TEST_RUNNER_OPV_PHYSICAL_MULTIVIEW_WIFI=1")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.activate()
        Thread.sleep(forTimeInterval: 4)
        if !app.buttons["Close Multiview"].exists {
            app.buttons["cameras.multiview"].tap()
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
            app.buttons["Cancel"].tap()
            XCTAssertTrue(
                waitUntil(timeout: 60) {
                    !app.buttons["Close Multiview"].exists
                        && app.buttons["cameras.multiview"].isHittable
                })
        } else {
            XCTAssertTrue(closeMultiview(app))
        }
    }

    /// Opt-in real-camera presentation smoke. Names must explicitly identify the
    /// intended cameras; credentials remain in the phone's existing Keychain.
    /// Checks fresh pictures and reported 180° shutter timing, then restores original
    /// camera settings. Uses a DEBUG-only readback probe; never records or moves the gimbal.
    func testMultiviewCameraControls() throws {
        guard let value = ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_CAMERAS"]
        else {
            throw XCTSkip("Requires TEST_RUNNER_OPV_PHYSICAL_MULTIVIEW_CAMERAS JSON name array")
        }
        let names = try JSONDecoder().decode([String].self, from: Data(value.utf8))
        XCTAssertTrue((2...4).contains(names.count))
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        addTeardownBlock {
            // Keep the app available for manual cleanup if AP return fails.
            // Never force-quit away an outstanding camera network obligation.
            if self.closeMultiview(app) { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
        }
        openMultiviewOnSavedWiFi(app)
        for (index, name) in names.enumerated() {
            let add = app.buttons["multiview.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 15))
            add.tap()
            let picker = app.otherElements["multiview.cameraPicker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            let camera = app.buttons.matching(NSPredicate(format: "label == %@", name))
                .firstMatch
            XCTAssertTrue(camera.waitForExistence(timeout: 30), "Requested camera not discovered")
            camera.tap()
            XCTAssertTrue(
                waitUntil(timeout: 150) {
                    self.previewFrames(app, index: index) != nil
                }, "Camera did not produce a fresh Multiview picture")
        }
        if ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_EXIT_ONLY"] == "1" {
            assertRollingPictures(app, cameras: names.count)
            XCTAssertTrue(closeMultiview(app), "The first Exit must restore every camera")
            return
        }
        let handoffOnly =
            ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_HANDOFF_ONLY"] == "1"
        for orientation
            in (handoffOnly ? [] : [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight])
        {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation != .portrait
            XCTAssertTrue(
                waitUntil(timeout: 10) {
                    (app.frame.width > app.frame.height) == landscape
                })
            Thread.sleep(forTimeInterval: 1)
            let layout = revealMultiviewTool(app, "multiview.layout")
            if layout.value as? String == "Grid" { layout.tap() }
            let wifiFrame = app.buttons["multiview.network"].frame
            let closeFrame = app.buttons["multiview.close"].frame
            // ScrollView accessibility bounds can extend to the screen edge.
            // Check the rendered control's touch target, not that container.
            let fit = revealMultiviewTool(app, "multiview.fitFill")
            XCTAssertTrue(fit.isHittable)
            XCTAssertGreaterThanOrEqual(fit.frame.width, 44 - 0.001)
            let toolbarColumn =
                landscape && fit.frame.midX < app.frame.midX
                ? closeFrame.midX : wifiFrame.midX
            XCTAssertEqual(
                fit.frame.midX, toolbarColumn, accuracy: 1,
                "Toolbar must align with its native button column")
            let recordFrame = app.buttons["multiview.recordAll"].frame
            let displayFrame = app.buttons["multiview.display"].frame
            let tiles = names.indices.map { app.buttons["multiview.tile.\($0)"].frame }
            if landscape {
                XCTAssertEqual(tiles[0].minY, closeFrame.minY, accuracy: 0.5)
                XCTAssertEqual(tiles[1].minY, closeFrame.minY, accuracy: 0.5)
                XCTAssertEqual(wifiFrame.midX, closeFrame.midX, accuracy: 0.5)
                XCTAssertEqual(wifiFrame.minY, closeFrame.maxY + 8, accuracy: 0.5)
                let strip = app.scrollViews["multiview.secondaryStrip"]
                XCTAssertTrue(strip.exists)
                XCTAssertLessThanOrEqual(strip.frame.maxY, displayFrame.minY - 7)
                scrollCameraStrip(strip, towardTop: false)
                assertRollingPictures(app, cameras: names.count)
                capture("multiview-physical-scrolled-\(orientation.rawValue)")
                scrollCameraStrip(strip, towardTop: true)
                XCTAssertTrue(
                    waitUntil(timeout: 3) {
                        abs(app.buttons["multiview.tile.1"].frame.minY - closeFrame.minY) < 0.5
                    })
            }
            capture("multiview-physical-stage-\(orientation.rawValue)")

            app.buttons["multiview.options.0"].tap()
            let options = app.descendants(matching: .any)["multiview.cameraOptions"].firstMatch
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            assertFloating(options, in: app)
            XCTAssertTrue(
                app.buttons["Disable Auto LUT"].exists, "New cameras default to Auto LUT on")
            capture("multiview-physical-menu-\(orientation.rawValue)")
            app.buttons["monitor.capture.close"].firstMatch.tap()

            let settingsButton = revealMultiviewTool(app, "multiview.settings")
            settingsButton.tap()
            let settings = app.descendants(matching: .any)["multiview.settings.panel"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            assertFloating(settings, in: app)
            let cameraA = app.buttons["multiview.settings.camera.0"]
            let cameraB = app.buttons["multiview.settings.camera.1"]
            XCTAssertEqual(cameraA.frame.maxX, cameraB.frame.minX, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(cameraA.frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(cameraB.frame.height, 44 - 0.001)
            for index in names.indices {
                let tab = app.buttons["multiview.settings.camera.\(index)"]
                XCTAssertTrue(tab.isHittable)
                tab.tap()
                let wb = app.buttons["multiview.settings.control.wb"]
                XCTAssertTrue(wb.waitForExistence(timeout: 5))
                wb.tap()
                capture("multiview-physical-settings-\(index)-\(orientation.rawValue)")
            }
            app.buttons["monitor.capture.close"].firstMatch.tap()
            assertRollingPictures(app, cameras: names.count)
            XCTAssertEqual(app.buttons["multiview.recordAll"].frame, recordFrame)
            XCTAssertEqual(app.buttons["multiview.display"].frame, displayFrame)
            for index in names.indices {
                XCTAssertEqual(app.buttons["multiview.tile.\(index)"].frame, tiles[index])
            }
        }
        let controlsIndex =
            names.indices.first { !names[$0].localizedCaseInsensitiveContains("nano") } ?? 0
        inspectBorrowedLiveChrome(app, index: controlsIndex)
        for duration in (handoffOnly ? [5.0] : [5.0, 35.0]) {
            assertRollingPictures(app, cameras: names.count)
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: duration)
            app.activate()
            let recovered = waitUntil(timeout: 60) {
                names.indices.allSatisfy { self.previewFrames(app, index: $0) != nil }
            }
            let health = XCTAttachment(
                string: names.indices.map {
                    "tile\($0): \(app.buttons["multiview.tile.\($0)"].value as? String ?? "missing")"
                }.joined(separator: "\n"))
            health.name = "multiview-foreground-health"
            health.lifetime = .keepAlways
            add(health)
            XCTAssertTrue(
                recovered, "Every camera must restore a fresh picture after returning to the app")
            assertRollingPictures(app, cameras: names.count)
            capture("multiview-physical-foreground-\(Int(duration))s")
        }
        if handoffOnly {
            XCTAssertTrue(closeMultiview(app))
            return
        }
        try exercisePhysicalShutterAngle(
            testCase: self, app: app,
            openSettings: {
                self.revealMultiviewTool(app, "multiview.settings").tap()
                let firstCamera = app.buttons["multiview.settings.camera.\(controlsIndex)"]
                XCTAssertTrue(firstCamera.waitForExistence(timeout: 5))
                firstCamera.tap()
            },
            readProbe: {
                let panel = app.descendants(matching: .any)["multiview.settings.panel"].firstMatch
                let element = panel.exists ? panel : app.buttons["multiview.tile.\(controlsIndex)"]
                let text = element.value as? String ?? ""
                return Dictionary(
                    uniqueKeysWithValues: text.split(separator: ";").compactMap {
                        let pair = $0.split(separator: "=", maxSplits: 1).map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                        return pair.count == 2 ? (pair[0], pair[1]) : nil
                    })
            })
        capture("multiview-physical-after-controls")
        XCTAssertTrue(closeMultiview(app), "Camera Wi-Fi restoration did not finish")
    }

    private func revealMultiviewTool(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let expand = app.buttons["multiview.toolbar.expand"]
        if expand.waitForExistence(timeout: 2) { expand.tap() }
        let tool = app.buttons[identifier]
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        let rail = app.scrollViews.containing(.button, identifier: identifier).firstMatch
        for _ in 0..<5 {
            if tool.isHittable, rail.frame.contains(tool.frame) { break }
            if tool.frame.minY < rail.frame.minY { rail.swipeDown() } else { rail.swipeUp() }
        }
        XCTAssertTrue(tool.isHittable)
        return tool
    }

    private func scrollCameraStrip(_ strip: XCUIElement, towardTop: Bool) {
        // Default AX swipes can start at the system edge and open Control Center.
        let start = strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.4 : 0.85))
        let end = strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.85 : 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func inspectBorrowedLiveChrome(_ app: XCUIApplication, index: Int) {
        app.buttons["multiview.tile.\(index)"].doubleTap()
        let back = app.buttons["Return to Multiview"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["monitor.system.gimbal"].firstMatch.exists)
        capture("physical-joystick-adaptive-ink")
        let expand = app.buttons["monitor.assists.expand"]
        if expand.exists { expand.tap() }
        let lut = app.buttons["monitor.assist.LUT"]
        if lut.isHittable {
            lut.tap()
            capture("physical-joystick-alternate-lut-path")
            lut.tap()
        }
        app.buttons["monitor.system.settings"].tap()
        let display = app.buttons["monitor.settings.tab.Display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        display.tap()
        capture("physical-settings-boxless-vertical-tabs")
        app.swipeUp()
        capture("physical-settings-opacity-scroll-fade")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: 10) { app.frame.height > app.frame.width })
        capture("physical-settings-boxless-horizontal-tabs")
        app.buttons["Back to live"].firstMatch.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["multiview.tile.0"].waitForExistence(timeout: 10))
    }

    private func previewFrames(_ app: XCUIApplication, index: Int) -> Int? {
        let tile = app.buttons["multiview.tile.\(index)"]
        guard tile.exists, let value = tile.value as? String,
            value.contains("Live; frames="),
            let count = value.components(separatedBy: "frames=").last
        else { return nil }
        return Int(count.prefix { $0.isNumber })
    }

    private func assertRollingPictures(_ app: XCUIApplication, cameras: Int) {
        let before = (0..<cameras).map { previewFrames(app, index: $0) }
        XCTAssertTrue(before.allSatisfy { $0 != nil }, "All cameras must have fresh pictures")
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                (0..<cameras).allSatisfy { index in
                    guard let first = before[index],
                        let current = self.previewFrames(app, index: index)
                    else { return false }
                    return current > first + 5
                }
            }, "Each camera must continue presenting new source pictures")
    }

    private func assertFloating(_ popup: XCUIElement, in app: XCUIApplication) {
        let frame = popup.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(frame))
        XCTAssertLessThan(frame.width * frame.height, app.frame.width * app.frame.height * 0.9)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func closeMultiview(_ app: XCUIApplication) -> Bool {
        let backToLive = app.buttons["Back to live"].firstMatch
        if backToLive.exists { backToLive.tap() }
        let returnToStage = app.buttons["Return to Multiview"]
        if returnToStage.exists { returnToStage.tap() }
        let cleanupError = app.alerts["Multiview"]
        if cleanupError.exists { cleanupError.buttons["OK"].tap() }
        if !app.buttons["Close Multiview"].exists,
            app.buttons["cameras.multiview"].isHittable
        {
            return true
        }
        let popupClose = app.buttons["monitor.capture.close"].firstMatch
        if popupClose.exists { popupClose.tap() }
        let picker = app.otherElements["multiview.cameraPicker"]
        if picker.exists { app.buttons["Cancel"].firstMatch.tap() }
        let close = app.buttons["Close Multiview"]
        guard waitUntil(timeout: 60, { close.exists && close.isEnabled }) else { return false }
        close.tap()
        let confirm = app.buttons["Close monitoring"]
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        _ = waitUntil(timeout: 60) {
            cleanupError.exists || (!close.exists && app.buttons["cameras.multiview"].isHittable)
        }
        return !cleanupError.exists && !close.exists
            && app.buttons["cameras.multiview"].isHittable
    }

    private func openMultiviewOnSavedWiFi(_ app: XCUIApplication) {
        app.launchEnvironment["OPV_PHYSICAL_MULTIVIEW_PROBE"] = "1"
        launch(app)
        let multiview = app.buttons["cameras.multiview"]
        XCTAssertTrue(multiview.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        multiview.tap()
        let wifi = app.buttons["multiview.setup.wifi"]
        XCTAssertTrue(wifi.waitForExistence(timeout: 10))
        wifi.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        let network: XCUIElement
        if let name = ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_NETWORK"] {
            network = app.buttons["multiview.setup.network.\(name)"].firstMatch
        } else {
            network =
                app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH 'multiview.setup.network.'")
                ).firstMatch
        }
        XCTAssertTrue(network.waitForExistence(timeout: 15))
        capture("multiview-wifi-scanning")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil(timeout: 10) { app.frame.width > app.frame.height })
        capture("multiview-wifi-landscape-columns")
        network.tap()
        let connect = app.buttons["multiview.setup.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.isEnabled)
        capture("multiview-wifi-landscape-password-footer")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitUntil(timeout: 10) { app.frame.height > app.frame.width })
        connect.tap()
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add camera'"))
            .firstMatch
        let join = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Join"]
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline && !add.exists {
            if join.exists { join.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(add.exists, "Host Wi-Fi must be confirmed before cameras can be added")
        capture("multiview-wifi-confirmed")
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
