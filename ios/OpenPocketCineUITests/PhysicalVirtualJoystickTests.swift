import UIKit
import XCTest

/// Navigation and saved preference proof only; never drives the camera.
final class PhysicalVirtualJoystickTests: XCTestCase {
    func testVirtualJoystickPreferencesPersist() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires opted-in physical navigation")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        #if targetEnvironment(simulator)
            app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "settings"
        #endif
        app.launchArguments += ["-opc.reliabilityReporting.optIn", "NO"]
        let originalOrientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = originalOrientation
        }
        app.launch()
        try openControls(app)
        let pan = app.buttons["gimbal.virtual.invertPan"]
        guard pan.waitForExistence(timeout: 5) else {
            throw XCTSkip("Connect a gimbal camera to expose its joystick settings")
        }
        reveal(pan, in: app)
        let original = try XCTUnwrap(pan.value as? String)
        XCTAssertTrue(["On", "Off"].contains(original))
        defer {
            if pan.isHittable, pan.value as? String != original { pan.tap() }
        }
        pan.tap()
        let changed = original == "On" ? "Off" : "On"
        XCTAssertEqual(pan.value as? String, changed)
        app.terminate()
        app.launch()
        try openControls(app)
        reveal(pan, in: app)
        XCTAssertEqual(pan.value as? String, changed)
        pan.tap()
        XCTAssertEqual(pan.value as? String, original)
        let tilt = app.buttons["gimbal.virtual.invertTilt"]
        reveal(tilt, in: app)
        XCTAssertTrue(tilt.isHittable)
        XCTAssertTrue(app.staticTexts["Dead zone"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Response curve"].firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "physical-virtual-joystick-settings"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openControls(_ app: XCUIApplication) throws {
        let controls = app.buttons["monitor.settings.tab.Controls"]
        #if targetEnvironment(simulator)
            if controls.waitForExistence(timeout: 10) {
                controls.tap()
                return
            }
        #endif
        let home = app.buttons["cameras.settings"]
        let live = app.buttons["monitor.system.settings"]
        expectation(for: NSPredicate { _, _ in home.exists || live.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 20)
        Thread.sleep(forTimeInterval: 3)
        (live.exists ? live : home).tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 10))
        controls.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
