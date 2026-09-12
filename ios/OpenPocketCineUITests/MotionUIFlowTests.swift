import XCTest

/// Presentation fixture only; no camera or transport is connected. An outside
/// touch over Record must be consumed before its confirmation/command path.
final class MotionUIFlowTests: XCTestCase {
    func testOutsideTapMinimizesWithoutActivatingCameraControls() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        if let clip = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"] {
            app.launchEnvironment["OPV_SIM_FEED_CLIP"] = clip
        }
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        let recordPoint = record.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        app.buttons["monitor.system.gimbalControls"].tap()
        let open = app.buttons["motion.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let title = app.staticTexts["motion.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        for slot in ["A", "B", "C"] {
            let readout = app.staticTexts["motion.waypoint.\(slot).readout"]
            XCTAssertTrue(readout.exists)
            XCTAssertEqual(readout.label, "Not set")
            XCTAssertTrue(app.buttons["motion.waypoint.\(slot)"].isHittable)
        }
        let full = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        full.name = "motion-control-empty-points"
        full.lifetime = .keepAlways
        add(full)

        recordPoint.tap()
        let expand = app.buttons["motion.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.staticTexts["Start recording?"].exists)
        XCTAssertEqual(record.label, "Start recording")
        expand.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["motion.waypoint.C.readout"].exists)

        XCUIDevice.shared.orientation = .landscapeLeft
        var previous: [CGRect] = []
        var unchangedSince = Date()
        let settled = NSPredicate { _, _ in
            guard app.frame.width > app.frame.height else { return false }
            let frames = [app.frame, title.frame]
            if frames != previous {
                previous = frames
                unchangedSince = Date()
                return false
            }
            return Date().timeIntervalSince(unchangedSince) >= 0.5
        }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let scroll = app.scrollViews["motion.editor.scroll"]
        for slot in ["A", "B", "C"] {
            let set = app.buttons["motion.waypoint.\(slot)"]
            if !set.isHittable, scroll.exists { scroll.swipeUp() }
            XCTAssertTrue(set.isHittable)
            XCTAssertEqual(app.staticTexts["motion.waypoint.\(slot).readout"].label, "Not set")
        }
        let minimize = app.buttons["motion.minimize"]
        if !minimize.isHittable, scroll.exists { scroll.swipeDown() }
        XCTAssertTrue(app.buttons["motion.close"].isHittable)
        XCTAssertTrue(minimize.isHittable)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "motion-control-landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        minimize.tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }
}
