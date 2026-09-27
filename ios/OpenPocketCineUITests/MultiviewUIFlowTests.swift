import XCTest

/// Runs the production stage on simulator or an opt-in physical review device.
/// The DEBUG fixture has no camera transports or saved-camera writes.
final class MultiviewUIFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_MULTIVIEW"] = "1"
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testLayoutsSelectionAndSystemControlsAcrossOrientations() {
        app.launch()
        var previousLandscapeRailX: CGFloat?
        var landscapeFrames: [String: [CGRect]] = [:]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let layout = revealToolbarButton("multiview.layout")
            let record = app.buttons["multiview.recordAll"]
            let display = app.buttons["multiview.display"]
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            XCTAssertTrue(layout.isHittable)
            XCTAssertTrue(display.isHittable)
            let recordFrame = record.frame
            let displayFrame = display.frame
            if orientation != .portrait {
                let rail = app.scrollViews["multiview.toolbar"]
                let exit = app.buttons["multiview.close"]
                let network = app.buttons["multiview.network"]
                // ScrollView accessibility bounds can extend to the screen
                // edge; alignment belongs to the rendered button target.
                let toolbarX = layout.frame.midX
                XCTAssertGreaterThanOrEqual(layout.frame.width, 44 - 0.001)
                let toolbarOnLeft = toolbarX < app.frame.midX
                XCTAssertEqual(
                    toolbarX,
                    toolbarOnLeft ? exit.frame.midX : display.frame.midX, accuracy: 1)
                XCTAssertGreaterThanOrEqual(
                    rail.frame.minY, (toolbarOnLeft ? exit.frame.maxY : network.frame.maxY) + 7)
                XCTAssertLessThanOrEqual(rail.frame.maxY, display.frame.minY - 7)
                if app.frame.height < 600, exit.frame.minY < 50 {
                    // Native phone corner clearance identifies a cutout device.
                    // Opposite rotations move only the toolbar across the feeds.
                    if let previousLandscapeRailX {
                        XCTAssertNotEqual(toolbarX, previousLandscapeRailX)
                    }
                    previousLandscapeRailX = toolbarX
                }
                if !toolbarOnLeft, app.frame.height < 600 {
                    XCTAssertEqual(toolbarX, network.frame.midX, accuracy: 1)
                }
            }
            for expected in ["Grid", "Center stage"] {
                layout.tap()
                XCTAssertEqual(layout.value as? String, expected)
                XCTAssertEqual(record.frame, recordFrame)
                XCTAssertEqual(display.frame, displayFrame)
                XCTAssertEqual(app.buttons.matching(identifier: "multiview.add").count, 1)
                let tile = app.buttons["multiview.tile.1"]
                XCTAssertTrue(tile.isHittable)
                tile.tap()
                // The native exclusive double-tap recognizer must expire before
                // a single tap selects the feed. XCTest idleness does not wait
                // for that recognizer deadline.
                expectation(
                    for: NSPredicate(format: "value BEGINSWITH %@", "Selected"), evaluatedWith: tile
                )
                waitForExpectations(timeout: 3)
                XCTAssertEqual(
                    layout.value as? String, expected, "Selecting a grid feed keeps Grid")
                XCTAssertTrue(app.buttons["multiview.options.1"].isHittable)
                if orientation == .portrait {
                    if expected == "Grid" {
                        XCTAssertGreaterThan(layout.frame.minX, tile.frame.maxX)
                    } else {
                        XCTAssertGreaterThanOrEqual(layout.frame.minY, tile.frame.maxY)
                    }
                    XCTAssertLessThan(display.frame.midX, record.frame.midX)
                    XCTAssertEqual(display.frame.midY, record.frame.midY, accuracy: 1)
                } else {
                    XCTAssertEqual(display.frame.midX, record.frame.midX, accuracy: 1)
                    XCTAssertLessThan(display.frame.maxY, record.frame.minY)
                    let frames =
                        (0..<3).map { app.buttons["multiview.tile.\($0)"].frame }
                        + [app.buttons["multiview.add"].frame]
                    for frame in frames.prefix(2) {
                        XCTAssertEqual(
                            frame.minY, app.buttons["multiview.close"].frame.minY, accuracy: 0.5)
                        XCTAssertEqual(
                            frame.minY, app.buttons["multiview.network"].frame.minY, accuracy: 0.5)
                    }
                    if let previous = landscapeFrames[expected] {
                        for (frame, prior) in zip(frames, previous) {
                            // Rotation's coordinate conversion can introduce
                            // floating-point noise below a rendered pixel.
                            XCTAssertEqual(frame.minX, prior.minX, accuracy: 0.5)
                            XCTAssertEqual(frame.minY, prior.minY, accuracy: 0.5)
                            XCTAssertEqual(frame.width, prior.width, accuracy: 0.5)
                            XCTAssertEqual(frame.height, prior.height, accuracy: 0.5)
                        }
                    }
                    landscapeFrames[expected] = frames
                }
                capture("multiview-\(expected)-\(orientation.rawValue)")
            }
            display.tap()
            XCTAssertEqual(display.value as? String, "Clean")
            XCTAssertFalse(app.buttons["multiview.layout"].exists)
            XCTAssertFalse(app.buttons["multiview.options.1"].exists)
            XCTAssertFalse(app.buttons["multiview.add"].exists)
            XCTAssertEqual(record.frame, recordFrame)
            XCTAssertEqual(display.frame, displayFrame)
            capture("multiview-clean-\(orientation.rawValue)")
            display.tap()
        }
    }

    func testOptionsKeepUnavailableHardwareActionsDisabledAndOneAddSlot() {
        app.launchEnvironment["OPV_UI_REVIEW_MULTIVIEW_COUNT"] = "1"
        app.launch()
        let options = app.buttons["multiview.options.0"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "multiview.add").count, 1)
        XCTAssertFalse(app.buttons["multiview.recordAll"].isEnabled)
        options.tap()
        XCTAssertTrue(app.buttons["Live View"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Live View"].isEnabled)
        XCTAssertFalse(app.buttons["Stop recording"].isEnabled)
        XCTAssertTrue(app.buttons["Disable Auto LUT"].isEnabled)
        capture("multiview-camera-options")
        app.buttons["monitor.capture.close"].tap()
        app.buttons["multiview.add"].tap()
        XCTAssertTrue(app.otherElements["multiview.cameraPicker"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "multiview.add").count, 1)
    }

    func testFloatingPanelsStayBoundedAndCameraTabsKeepStageSelection() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let tile = app.buttons["multiview.tile.0"]
            let originalFrame = tile.frame
            let selectedValue = tile.value as? String
            let settings = revealToolbarButton("multiview.settings")
            settings.tap()
            var panel = app.descendants(matching: .any)["multiview.settings.panel"]
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            assertBounded(panel)
            XCTAssertTrue(app.buttons["multiview.settings.camera.0"].exists)
            let cameraA = app.buttons["multiview.settings.camera.0"]
            let cameraB = app.buttons["multiview.settings.camera.1"]
            XCTAssertEqual(cameraA.frame.maxX, cameraB.frame.minX, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(cameraA.frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(cameraB.frame.height, 44 - 0.001)
            XCTAssertEqual(
                app.buttons["multiview.settings.control.iso"].frame.maxX,
                app.buttons["multiview.settings.control.shutter"].frame.minX, accuracy: 0.5)
            app.buttons["multiview.settings.camera.1"].tap()
            XCTAssertTrue(app.buttons["multiview.settings.camera.1"].isSelected)
            XCTAssertTrue(panel.staticTexts["Close-up"].exists)
            XCTAssertTrue(
                panel.otherElements.matching(
                    NSPredicate(format: "label == %@ AND value == %@", "Value", "800")
                ).firstMatch.exists,
                "The editor displays camera B's ISO while stage A stays selected")
            XCTAssertTrue(app.buttons["multiview.settings.control.wb"].waitForExistence(timeout: 5))
            app.buttons["multiview.settings.control.wb"].tap()
            panel = app.descendants(matching: .any)["multiview.settings.panel"]
            assertBounded(panel)
            XCTAssertEqual(tile.frame, originalFrame)
            XCTAssertEqual(tile.value as? String, selectedValue)
            capture("multiview-settings-\(orientation.rawValue)")
            app.buttons["monitor.capture.close"].tap()
            XCTAssertFalse(panel.exists)
            app.buttons["multiview.options.1"].tap()
            let options = app.descendants(matching: .any)["multiview.cameraOptions"]
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            assertBounded(options)
            capture("multiview-options-\(orientation.rawValue)")
            app.buttons["monitor.capture.close"].tap()
            XCTAssertFalse(options.exists)
        }
    }

    /// Smaller phones keep full-size buttons in a bounded side rail.
    /// Reveal the requested control without changing the native Record/DISP slots.
    private func revealToolbarButton(_ identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let rail = app.scrollViews["multiview.toolbar"]
        XCTAssertTrue(rail.exists)
        let recordFrame = app.buttons["multiview.recordAll"].frame
        let displayFrame = app.buttons["multiview.display"].frame
        for _ in 0..<2 {
            if rail.frame.contains(button.frame) { break }
            if button.frame.minY < rail.frame.minY { rail.swipeDown() } else { rail.swipeUp() }
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(app.buttons["multiview.recordAll"].frame, recordFrame)
        XCTAssertEqual(app.buttons["multiview.display"].frame, displayFrame)
        return button
    }

    private func assertBounded(_ panel: XCUIElement) {
        XCTAssertGreaterThanOrEqual(panel.frame.minX, app.frame.minX + 15)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, app.frame.minY + 15)
        XCTAssertLessThanOrEqual(panel.frame.maxX, app.frame.maxX - 15)
        XCTAssertLessThanOrEqual(panel.frame.maxY, app.frame.maxY - 15)
        XCTAssertLessThanOrEqual(panel.frame.width, 560)
    }

    func testRecoveryRemainsVisibleInCleanView() {
        app.launchEnvironment["OPV_UI_REVIEW_MULTIVIEW_RECOVERY"] = "1"
        app.launch()
        let display = app.buttons["multiview.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        display.tap()
        let recovery = app.buttons["Restoring picture…"]
        XCTAssertTrue(recovery.isHittable)
        capture("multiview-clean-recovery")
        recovery.tap()
        XCTAssertTrue(app.buttons["Reconnect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reconnect"].isEnabled, "An active recovery retains ownership")
    }

    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let rotated = NSPredicate { _, _ in
            (self.app.frame.width > self.app.frame.height) == landscape
        }
        expectation(for: rotated, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        var previous: [CGRect] = []
        var unchangedSince = Date()
        let settled = NSPredicate { _, _ in
            let frames = [self.app.frame, self.app.buttons["multiview.display"].frame]
            if frames != previous {
                previous = frames
                unchangedSince = Date()
                return false
            }
            return Date().timeIntervalSince(unchangedSince) >= 0.5
        }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
