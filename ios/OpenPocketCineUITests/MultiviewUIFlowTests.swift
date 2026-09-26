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
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let layout = app.buttons["multiview.layout"]
            let record = app.buttons["multiview.recordAll"]
            let display = app.buttons["multiview.display"]
            XCTAssertTrue(layout.waitForExistence(timeout: 10))
            XCTAssertTrue(layout.isHittable)
            XCTAssertTrue(display.isHittable)
            let recordFrame = record.frame
            let displayFrame = display.frame
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
                    for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: tile)
                waitForExpectations(timeout: 3)
                XCTAssertEqual(
                    layout.value as? String, expected, "Selecting a grid feed keeps Grid")
                XCTAssertTrue(app.buttons["multiview.options.1"].isHittable)
                if orientation == .portrait {
                    if expected == "Grid" {
                        XCTAssertLessThan(layout.frame.maxX, tile.frame.minX)
                    } else {
                        XCTAssertGreaterThanOrEqual(layout.frame.minY, tile.frame.maxY)
                    }
                    XCTAssertLessThan(display.frame.midX, record.frame.midX)
                    XCTAssertEqual(display.frame.midY, record.frame.midY, accuracy: 1)
                } else {
                    XCTAssertEqual(display.frame.midX, record.frame.midX, accuracy: 1)
                    XCTAssertLessThan(display.frame.maxY, record.frame.minY)
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
        XCTAssertTrue(app.buttons["Enable Auto LUT"].isEnabled)
        capture("multiview-camera-options")
        app.buttons["Done"].tap()
        app.buttons["multiview.add"].tap()
        XCTAssertTrue(app.otherElements["multiview.cameraPicker"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "multiview.add").count, 1)
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
