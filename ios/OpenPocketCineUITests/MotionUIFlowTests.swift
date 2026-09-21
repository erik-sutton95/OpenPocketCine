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
        scrollSettingsToBottom(app.scrollViews["motion.editor.scroll"])
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
        scrollSettingsToBottom(app.scrollViews["motion.editor.scroll"])
        XCTAssertTrue(["1", "On"].contains(loopValue()), loop.debugDescription)
        app.buttons["motion.clear"].tap()
        XCTAssertEqual(readouts.map(\.label), ["Not set", "Not set", "Not set"])
        XCTAssertTrue(["0", "Off"].contains(loopValue()), loop.debugDescription)
        XCTAssertFalse(smoothness.exists)
    }

    func testEditorKeepsActionsFixedAndFadesOnlyOverflowInBothOrientations() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION_RUNNING"] = "1"
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
        let scroll = app.scrollViews["motion.editor.scroll"]
        let clear = app.buttons["motion.clear"]
        let startStop = app.buttons["motion.startStop"]
        let pause = app.buttons["motion.pauseResume"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let settled = NSPredicate { _, _ in
                (app.frame.width > app.frame.height) == orientation.isLandscape
                    && app.buttons["motion.close"].isHittable && clear.isHittable
            }
            expectation(for: settled, evaluatedWith: app)
            waitForExpectations(timeout: 10)
            scroll.swipeDown()
            let hasMore = NSPredicate { _, _ in
                (scroll.value as? String) == "More settings below"
            }
            expectation(for: hasMore, evaluatedWith: scroll)
            waitForExpectations(timeout: 5)

            let titleFrame = title.frame
            let clearFrame = clear.frame
            let startFrame = startStop.frame
            let pauseFrame = pause.frame
            XCTAssertLessThanOrEqual(clearFrame.maxY - titleFrame.minY, 420)
            XCTAssertGreaterThanOrEqual(clearFrame.height, 44)
            XCTAssertTrue(startStop.isHittable)
            XCTAssertEqual(startStop.label, "Stop")
            XCTAssertTrue(pause.isHittable)
            XCTAssertLessThanOrEqual(scroll.frame.maxY, clearFrame.minY)
            attachScreenshot(orientation.isLandscape ? "motion-compact-landscape-overflow" : "motion-compact-portrait-overflow")

            scrollSettingsToBottom(scroll)
            XCTAssertEqual(scroll.value as? String, "End of settings")
            XCTAssertTrue(app.switches["motion.loop"].isHittable)
            XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 1)
            XCTAssertEqual(clear.frame.minY, clearFrame.minY, accuracy: 1)
            XCTAssertEqual(startStop.frame.minY, startFrame.minY, accuracy: 1)
            XCTAssertEqual(pause.frame.minY, pauseFrame.minY, accuracy: 1)
            XCTAssertTrue(clear.isHittable)
            XCTAssertTrue(startStop.isHittable)
            XCTAssertTrue(pause.isHittable)
            XCTAssertTrue(app.buttons["motion.close"].isHittable)
            attachScreenshot(orientation.isLandscape ? "motion-compact-landscape-end" : "motion-compact-portrait-end")
        }

        // A footer action remains usable after scrolling to the last setting.
        clear.tap()
        XCTAssertEqual(app.staticTexts["motion.waypoint.A.readout"].label, "Not set")
        XCUIDevice.shared.orientation = .portrait
        let fits = NSPredicate { _, _ in
            app.frame.width < app.frame.height && (scroll.value as? String) == "End of settings"
        }
        expectation(for: fits, evaluatedWith: scroll)
        waitForExpectations(timeout: 5)
        attachScreenshot("motion-compact-empty-without-overflow")
    }

    private func scrollSettingsToBottom(_ scroll: XCUIElement) {
        for _ in 0..<5 {
            if (scroll.value as? String) == "End of settings" { return }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.85))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.15))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
