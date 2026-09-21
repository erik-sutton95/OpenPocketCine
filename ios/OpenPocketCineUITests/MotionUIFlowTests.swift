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

    func testLoopAndProgramSurviveClosingUntilClear() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launch()
        defer { app.terminate() }

        func openEditor() {
            app.buttons["monitor.system.gimbalControls"].tap()
            let open = app.buttons["motion.openEditor"]
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            open.tap()
            XCTAssertTrue(app.staticTexts["motion.editor.title"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.buttons["monitor.system.gimbalControls"].waitForExistence(timeout: 10))
        openEditor()
        let readouts = ["A", "B", "C"].map { app.staticTexts["motion.waypoint.\($0).readout"] }
        let saved = readouts.map(\.label)
        XCTAssertFalse(saved.contains("Not set"))
        let durations = ["B", "C"].map { app.descendants(matching: .any)["motion.duration.\($0)"].firstMatch }
        let savedDurations = durations.map { $0.value as? String }
        XCTAssertEqual(savedDurations, ["3s", "2s"])
        let smoothness = app.sliders["Path smoothness"]
        let savedSmoothness = smoothness.value as? String
        XCTAssertNotNil(savedSmoothness)
        let loop = app.switches["motion.loop"]
        // Custom Toggle styles can expose NSNumber rather than String to XCTest.
        func loopValue() -> String { String(describing: loop.value ?? "") }
        XCTAssertTrue(loop.isHittable, app.debugDescription)
        XCTAssertTrue(["0", "Off"].contains(loopValue()), loop.debugDescription)
        loop.tap()
        XCTAssertTrue(["1", "On"].contains(loopValue()), loop.debugDescription)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "motion-control-loop-saved-program"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["motion.close"].tap()
        XCTAssertFalse(app.staticTexts["motion.editor.title"].exists)
        openEditor()
        XCTAssertEqual(readouts.map(\.label), saved)
        XCTAssertEqual(durations.map { $0.value as? String }, savedDurations)
        XCTAssertEqual(smoothness.value as? String, savedSmoothness)
        XCTAssertTrue(["1", "On"].contains(loopValue()), loop.debugDescription)
        app.buttons["motion.clear"].tap()
        XCTAssertEqual(readouts.map(\.label), ["Not set", "Not set", "Not set"])
        XCTAssertTrue(["0", "Off"].contains(loopValue()), loop.debugDescription)
        XCTAssertFalse(smoothness.exists)
    }

    func testFloatingEditorDragCommitsLocationAfterRelease() {
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

        XCTAssertTrue(app.buttons["monitor.system.gimbalControls"].waitForExistence(timeout: 10))
        app.buttons["monitor.system.gimbalControls"].tap()
        let open = app.buttons["motion.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let title = app.staticTexts["motion.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let origin = title.frame
        let start = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.01,
            thenDragTo: start.withOffset(CGVector(dx: 80, dy: 120)))
        let moved = NSPredicate { _, _ in
            hypot(title.frame.minX - origin.minX, title.frame.minY - origin.minY) > 40
        }
        expectation(for: moved, evaluatedWith: title)
        waitForExpectations(timeout: 4)
        XCTAssertGreaterThan(
            hypot(title.frame.minX - origin.minX, title.frame.minY - origin.minY), 40,
            "Release must keep the dragged editor location")
        XCTAssertTrue(app.buttons["motion.minimize"].exists)
        XCTAssertTrue(app.buttons["motion.close"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "motion-control-after-drag-release"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
