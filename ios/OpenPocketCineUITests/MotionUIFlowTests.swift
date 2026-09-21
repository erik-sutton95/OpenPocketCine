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

    func testDLog2ExplainsWhyZoomProgramCannotStart() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION_ZOOM"] = "1"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["monitor.system.gimbalControls"].waitForExistence(timeout: 10))
        app.buttons["monitor.system.gimbalControls"].tap()
        let open = app.buttons["motion.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let reason = app.staticTexts["motion.zoomUnavailable"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertEqual(reason.label, "Zoom moves are unavailable in D-Log2")
        XCTAssertTrue(reason.isHittable, "The reason must be visible beside the disabled Start button")
        XCTAssertFalse(app.buttons["motion.startStop"].isEnabled)
        XCTAssertTrue(app.buttons["motion.clear"].isEnabled)
        attachScreenshot("motion-zoom-dlog2-unavailable")
    }

    func testZoomChipAndDiscKeepFullEditorInBothOrientations() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_ZOOM_CONTROLS"] = "1"
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
        let zoom = app.buttons["monitor.system.zoom"]
        let scroll = app.scrollViews["motion.editor.scroll"]
        let clear = app.buttons["motion.clear"]
        let start = app.buttons["motion.startStop"]
        let points = ["A", "B", "C"].map { app.staticTexts["motion.waypoint.\($0).readout"] }
        let savedPoints = points.map(\.label)
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let settled = NSPredicate { _, _ in
                (app.frame.width > app.frame.height) == orientation.isLandscape
                    && zoom.isHittable && clear.isHittable
            }
            expectation(for: settled, evaluatedWith: app)
            waitForExpectations(timeout: 10)
            let titleFrame = title.frame
            let clearFrame = clear.frame
            let startFrame = start.frame
            if !orientation.isLandscape {
                XCTAssertLessThanOrEqual(clearFrame.maxY, zoom.frame.minY - 8,
                    "The default editor must leave the original zoom chip exposed")
            }
            let beforeTap = zoom.label
            zoom.tap()
            XCTAssertTrue(title.exists, "The existing zoom chip must not minimize Motion Control")
            XCTAssertFalse(app.buttons["motion.expand"].exists)
            expectation(for: NSPredicate { _, _ in zoom.label != beforeTap }, evaluatedWith: zoom)
            waitForExpectations(timeout: 5)
            XCTAssertNotEqual(zoom.label, beforeTap, "The original single-tap action must receive the touch")
            let beforeDoubleTap = zoom.label
            zoom.doubleTap()
            XCTAssertTrue(title.exists, "Extended zoom must also leave the full editor open")
            expectation(for: NSPredicate { _, _ in zoom.label != beforeDoubleTap }, evaluatedWith: zoom)
            waitForExpectations(timeout: 5)
            XCTAssertNotEqual(zoom.label, beforeDoubleTap, "The original double-tap action must receive the touch")
            zoom.press(forDuration: 0.55)
            let dial = app.descendants(matching: .any)["monitor.zoom.dial"].firstMatch
            XCTAssertTrue(dial.waitForExistence(timeout: 5))
            XCTAssertTrue(dial.isHittable, "The zoom disc must be above the Motion Control card")
            XCTAssertFalse(clear.isHittable, "The disc owns input while open")
            XCTAssertFalse(app.buttons["motion.minimizeBackdrop"].isHittable,
                "The covered backdrop must not receive a minimize action")
            attachScreenshot(orientation.isLandscape ? "motion-zoom-disc-landscape" : "motion-zoom-disc-portrait")
            app.buttons["Close zoom dial"].tap()
            expectation(for: NSPredicate { _, _ in !dial.isHittable && clear.isHittable },
                evaluatedWith: app)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(title.exists)
            XCTAssertTrue(clear.isHittable)
            XCTAssertTrue(zoom.isHittable)
            XCTAssertFalse(app.buttons["motion.expand"].exists)
            XCTAssertFalse(app.sliders["motion.zoom"].exists, "Motion Control uses the existing zoom controls")
            XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 1)
            XCTAssertEqual(points.map(\.label), savedPoints)

            scrollSettingsToBottom(scroll)
            XCTAssertEqual(clear.frame.minY, clearFrame.minY, accuracy: 1)
            XCTAssertEqual(start.frame.minY, startFrame.minY, accuracy: 1)
            XCTAssertTrue(clear.isHittable)
            XCTAssertTrue(start.isHittable)
            attachScreenshot(orientation.isLandscape ? "motion-zoom-chip-landscape" : "motion-zoom-chip-portrait")
        }
    }

    func testZoomChipKeepsRecordingColorGateWithEditorOpen() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_ZOOM_CONTROLS"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_ZOOM_DLOG2_RECORDING"] = "1"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["monitor.system.gimbalControls"].waitForExistence(timeout: 10))
        app.buttons["monitor.system.gimbalControls"].tap()
        let open = app.buttons["motion.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let title = app.staticTexts["motion.editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let zoom = app.buttons["monitor.system.zoom"]
        let before = zoom.label
        zoom.tap()
        XCTAssertTrue(app.staticTexts["motion.editor.title"].exists)
        XCTAssertEqual(zoom.label, before)
        XCTAssertTrue(app.staticTexts["Can't change color while recording — D-Log2 can't zoom"].waitForExistence(timeout: 5))
    }

    func testEditorKeepsActionsFixedAndFadesOnlyOverflowInBothOrientations() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION_RUNNING"] = "1"
        app.launchEnvironment["OPV_UI_REVIEW_MOTION_PAUSED"] = "1"
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
        let restart = app.buttons["motion.restart"]
        let startStop = app.buttons["motion.startStop"]
        let pause = app.buttons["motion.pauseResume"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["motion.clear"].exists)
        XCTAssertEqual(restart.label, "Restart")
        XCTAssertEqual(pause.label, "Resume")
        let readouts = ["A", "B", "C"].map { app.staticTexts["motion.waypoint.\($0).readout"] }
        let savedPoints = readouts.map(\.label)

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let settled = NSPredicate { _, _ in
                (app.frame.width > app.frame.height) == orientation.isLandscape
                    && app.buttons["motion.close"].isHittable && restart.isHittable
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
            let restartFrame = restart.frame
            let startFrame = startStop.frame
            let pauseFrame = pause.frame
            XCTAssertLessThanOrEqual(restartFrame.maxY - titleFrame.minY, 420)
            XCTAssertGreaterThanOrEqual(restartFrame.height, 44)
            XCTAssertTrue(startStop.isHittable)
            XCTAssertEqual(startStop.label, "Stop")
            XCTAssertTrue(pause.isHittable)
            XCTAssertLessThanOrEqual(scroll.frame.maxY, restartFrame.minY)
            attachScreenshot(orientation.isLandscape ? "motion-compact-landscape-overflow" : "motion-compact-portrait-overflow")

            scrollSettingsToBottom(scroll)
            XCTAssertEqual(scroll.value as? String, "End of settings")
            XCTAssertTrue(app.switches["motion.loop"].isHittable)
            XCTAssertEqual(title.frame.minY, titleFrame.minY, accuracy: 1)
            XCTAssertEqual(restart.frame.minY, restartFrame.minY, accuracy: 1)
            XCTAssertEqual(startStop.frame.minY, startFrame.minY, accuracy: 1)
            XCTAssertEqual(pause.frame.minY, pauseFrame.minY, accuracy: 1)
            XCTAssertTrue(restart.isHittable)
            XCTAssertTrue(startStop.isHittable)
            XCTAssertTrue(pause.isHittable)
            XCTAssertTrue(app.buttons["motion.close"].isHittable)
            attachScreenshot(orientation.isLandscape ? "motion-compact-landscape-end" : "motion-compact-portrait-end")
        }

        // Restart cancels the continuation but must never erase the saved path.
        restart.tap()
        XCTAssertTrue(app.buttons["motion.clear"].waitForExistence(timeout: 5))
        XCTAssertFalse(restart.exists)
        XCTAssertEqual(readouts.map(\.label), savedPoints,
            "Restart must preserve the program even when fresh camera feedback is unavailable")
        app.buttons["motion.clear"].tap()
        XCTAssertEqual(app.staticTexts["motion.waypoint.A.readout"].label, "Not set")
        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { _, _ in app.frame.width < app.frame.height }
        expectation(for: portrait, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        scrollSettingsToBottom(scroll)
        XCTAssertEqual(scroll.value as? String, "End of settings")
        attachScreenshot("motion-compact-empty-settings-end")
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
        let footerOffset = app.buttons["motion.startStop"].frame.minY - origin.minY
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
        XCTAssertEqual(
            app.buttons["motion.startStop"].frame.minY - title.frame.minY, footerOffset, accuracy: 1,
            "The first drag release must keep the same card height")
        XCTAssertTrue(app.buttons["motion.minimize"].exists)
        XCTAssertTrue(app.buttons["motion.close"].exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "motion-control-after-drag-release"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
