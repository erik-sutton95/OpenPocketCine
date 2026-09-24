import XCTest

/// These exercise rendered hit targets and navigation, not camera transport.
/// Optional OPV_SIM_FEED_CLIP points at private local footage; no footage is
/// bundled in tests. Screenshots are attached to the local xcresult only.
final class MonitorUIFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "live"
        if let clip = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"] {
            app.launchEnvironment["OPV_SIM_FEED_CLIP"] = clip
        }
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testMonitorControlsAcrossBothLandscapeOrientationsAndPortrait() {
        app.launchEnvironment["OPV_UI_REVIEW_FIT"] = "1"
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let record = app.buttons["monitor.system.record"]
            XCTAssertTrue(record.waitForExistence(timeout: 10))
            XCTAssertTrue(record.isHittable)
            XCTAssertTrue(app.buttons["monitor.system.settings"].isHittable)
            XCTAssertTrue(app.buttons["monitor.system.media"].isHittable)
            XCTAssertEqual(app.buttons.matching(identifier: "monitor.capture.iso").count, 1)
            XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
            let buttonFrame = record.frame
            XCTAssertGreaterThanOrEqual(buttonFrame.minX, 0)
            XCTAssertLessThanOrEqual(buttonFrame.maxX, app.frame.width)
            XCTAssertLessThanOrEqual(buttonFrame.maxY, app.frame.height)
            if UIDevice.current.userInterfaceIdiom == .phone, orientation != .portrait,
                app.frame.width > 700
            {
                XCTAssertEqual(
                    app.buttons["monitor.system.settings"].frame.minY,
                    8 + app.frame.height * 0.025, accuracy: 1,
                    "Phone corner clearance must stay small and separate from iPad window exclusions"
                )
            }
            let lockFrame = app.buttons["monitor.system.lock"].frame
            let settingsFrame = app.buttons["monitor.system.settings"].frame
            XCTAssertEqual(lockFrame.width, settingsFrame.width, accuracy: 0.5)
            XCTAssertEqual(lockFrame.height, settingsFrame.height, accuracy: 0.5)
            XCTAssertEqual(lockFrame.midY, settingsFrame.midY, accuracy: 0.5)
            let format = app.buttons["monitor.capture.format"]
            let tally = app.descendants(matching: .any)["monitor.recording.readout"].firstMatch
            XCTAssertTrue(tally.exists)
            XCTAssertEqual(format.frame.midY, tally.frame.midY, accuracy: 1)
            let cameraBattery = app.descendants(matching: .any)["monitor.telemetry.camera"]
                .firstMatch
            XCTAssertTrue(cameraBattery.exists)
            XCTAssertTrue(cameraBattery.label.hasPrefix("Camera battery "))
            capture("monitor-\(orientation.rawValue)")
        }
    }

    func testAssistPaletteAndValueDrumRemainReachable() {
        app.launch()
        rotate(.landscapeLeft)
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        let systemFrame = app.buttons["monitor.system.settings"].frame
        for tool in ["PEAK", "FALSE"] {
            let frame = app.buttons["monitor.assist.\(tool)"].frame
            XCTAssertEqual(frame.width, systemFrame.width, accuracy: 1)
            XCTAssertEqual(frame.height, systemFrame.height, accuracy: 1)
        }
        XCTAssertEqual(expand.frame.width, 27, accuracy: 1)
        capture("assist-favorites")
        expand.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let wave = app.buttons["monitor.assist.WAVE"]
        XCTAssertTrue(wave.waitForExistence(timeout: 5))
        XCTAssertEqual(wave.frame.width, systemFrame.width, accuracy: 1)
        XCTAssertEqual(wave.frame.height, systemFrame.height, accuracy: 1)
        wave.tap()
        capture("assist-palette")
        app.buttons["Collapse View Assist tools"].tap()
        app.buttons["monitor.capture.iso"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Value"].firstMatch.waitForExistence(timeout: 5))
        capture("iso-drum")
    }

    func testPortraitToolsStayInPlaceWhenFitFillChanges() {
        app.launchEnvironment["OPV_UI_REVIEW_FIT"] = "1"
        app.launch()
        let aspect = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Fill frame with feed", "Fit feed in frame"])
        ).firstMatch
        XCTAssertTrue(aspect.waitForExistence(timeout: 10))
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        XCTAssertTrue(peak.isHittable, "Portrait collapsed View Assist must show a favorite tool")
        XCTAssertGreaterThanOrEqual(peak.frame.height, 50)
        let tools = [
            app.buttons["monitor.assists.expand"],
            peak,
            app.buttons["monitor.system.zoom"],
            app.buttons["monitor.system.gimbalControls"],
            app.descendants(matching: .any)["monitor.system.gimbal"].firstMatch,
            aspect,
        ]
        let frames = tools.map(\.frame)
        for value in ["Fill", "Fit"] {
            aspect.tap()
            expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: aspect)
            waitForExpectations(timeout: 5)
            for (tool, frame) in zip(tools, frames) {
                XCTAssertEqual(tool.frame.minX, frame.minX, accuracy: 0.5)
                XCTAssertEqual(tool.frame.minY, frame.minY, accuracy: 0.5)
                XCTAssertEqual(tool.frame.width, frame.width, accuracy: 0.5)
                XCTAssertEqual(tool.frame.height, frame.height, accuracy: 0.5)
                XCTAssertLessThan(tool.frame.maxY, app.buttons["monitor.capture.iso"].frame.minY)
            }
            capture("portrait-fixed-tools-\(value.lowercased())")
        }
    }

    func testSettingsCoverageAndCardTitleSpacing() throws {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.system.settings"].tap()
        let back = app.buttons["Back to live"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["monitor.system.record"].isHittable)
        app.buttons["monitor.settings.tab.View Assist"].tap()
        let zebra = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "monitor.settings.card.title", "Zebra")
        ).firstMatch
        for _ in 0..<6 where !zebra.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.8))
                .press(
                    forDuration: 0.01,
                    thenDragTo:
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.4)))
        }
        XCTAssertTrue(zebra.isHittable, "The Zebra title remains visible")
        let title = zebra.frame
        let units = try XCTUnwrap(
            app.staticTexts.matching(identifier: "monitor.settings.row.title")
                .allElementsBoundByIndex
                .filter { $0.label == "Units" && abs($0.frame.minX - title.minX) < 30 }
                .min { abs($0.frame.minY - title.maxY) < abs($1.frame.minY - title.maxY) })
        XCTAssertGreaterThanOrEqual(units.frame.minY - title.maxY, 8)
        capture("settings-zebra-spacing")
        back.tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
    }

    func testCoveredPickerControlsAreInaccessibleAndReturnWithTheirState() {
        app.launch()
        rotate(.portrait)
        app.buttons["monitor.capture.iso"].tap()
        let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        for (control, backLabel) in [("settings", "Back to live"), ("media", "Back")] {
            let navigation = app.buttons["monitor.system.\(control)"]
            XCTAssertTrue(navigation.isHittable)
            navigation.tap()
            let back = app.buttons[backLabel].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            capture("covered-picker-\(control)")
            // XCTest still inventories mounted layout containers and hidden
            // controls. Test actionable reachability rather than query omission.
            XCTAssertFalse(app.buttons["monitor.capture.close"].isHittable)
            XCTAssertFalse(app.buttons["monitor.system.record"].isHittable)
            XCTAssertFalse(app.buttons["monitor.capture.iso"].isHittable)
            XCTAssertFalse(navigation.isHittable)
            back.tap()
            XCTAssertTrue(panel.isHittable, "The same picker returns after \(control)")
            XCTAssertTrue(app.buttons["monitor.capture.close"].isHittable)
            XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        }
        app.buttons["monitor.capture.close"].tap()
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
    }

    func testRecordHoldDoesNotRecordAndLockedControlsStayBlocked() {
        app.launch()
        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.press(forDuration: 0.6)
        XCTAssertTrue(app.staticTexts["Shooting mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Start"].exists, "Holding Record must not also open its confirmation")
        capture("record-hold-mode")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertFalse(
            app.staticTexts["Shooting mode"].exists,
            "Close must dismiss the recording picker before Lock is tapped"
        )
        app.buttons["monitor.system.lock"].tap()
        let locked = NSPredicate(format: "label == %@", "Unlock monitor controls")
        expectation(for: locked, evaluatedWith: app.buttons["monitor.system.lock"])
        waitForExpectations(timeout: 5)
        capture("monitor-locked")
        XCTAssertFalse(app.buttons["monitor.system.settings"].isEnabled)
        XCTAssertFalse(app.buttons["monitor.system.media"].isEnabled)
        XCTAssertFalse(record.isEnabled)
        record.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(
            app.buttons["Start"].exists,
            "A touch on the disabled Record control must not open confirmation"
        )
        XCTAssertFalse(app.staticTexts["Shooting mode"].exists)
        app.buttons["monitor.system.lock"].tap()
        XCTAssertTrue(record.isEnabled)
    }

    func testDrawersAndContinuousZoomSurviveRotation() {
        app.launch()
        let gimbal = app.buttons["monitor.system.gimbalControls"]
        XCTAssertTrue(gimbal.waitForExistence(timeout: 10))
        gimbal.tap()
        XCTAssertTrue(app.buttons["Close Gimbal"].waitForExistence(timeout: 5))
        capture("gimbal-portrait")
        rotate(.landscapeLeft)
        XCTAssertTrue(app.buttons["Close Gimbal"].isHittable)
        capture("gimbal-landscape")
        let gimbalPanel = app.otherElements["monitor.inspector"]
        let panelFrame = gimbalPanel.frame
        XCTAssertEqual(panelFrame.width, min(460, app.frame.width * 0.92), accuracy: 1)
        for tab in ["Speed", "Ramp", "Mode"] {
            app.buttons[tab].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["Value"].firstMatch.exists)
            XCTAssertEqual(gimbalPanel.frame.width, panelFrame.width, accuracy: 1)
            XCTAssertEqual(gimbalPanel.frame.height, panelFrame.height, accuracy: 1)
            capture("gimbal-tab-\(tab)")
        }
        app.buttons["Close Gimbal"].tap()
        app.buttons["monitor.system.zoom"].press(forDuration: 0.55)
        let dial = app.descendants(matching: .any)["monitor.zoom.dial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        for control in ["record", "display", "settings", "media"] {
            XCTAssertFalse(
                app.buttons["monitor.system.\(control)"].isHittable,
                "The zoom modal must cover underlying \(control) controls")
        }
        capture("zoom-dial-landscape")
        XCTAssertGreaterThan(
            dial.frame.height, dial.frame.width,
            "Landscape zoom disc must be a trailing half-circle")
        XCTAssertGreaterThan(
            dial.frame.minX, app.frame.midX - 24,
            "Landscape zoom disc must sit on the trailing edge, not over the picture")
        XCTAssertEqual(dial.frame.maxX, app.frame.maxX, accuracy: 12)
        rotate(.portrait)
        XCTAssertTrue(dial.isHittable)
        XCTAssertGreaterThan(
            dial.frame.width, dial.frame.height,
            "Portrait zoom disc must be a bottom half-circle")
        XCTAssertEqual(
            dial.frame.maxY, app.frame.maxY, accuracy: 12,
            "Portrait zoom disc must sit on the screen bottom edge")
        let record = app.buttons["monitor.system.record"]
        XCTAssertTrue(record.exists)
        XCTAssertFalse(
            record.isHittable,
            "The portrait zoom disc covers the bottom system controls")
        capture("zoom-dial-portrait")
        app.buttons["Close zoom dial"].tap()
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
        XCTAssertTrue(app.buttons["monitor.system.display"].isHittable)
    }

    func testAssistInspectorTabsSurviveRotation() {
        app.launch()
        app.buttons["monitor.assists.expand"].tap()
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        peak.press(forDuration: 0.55)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        capture("assist-inspector-portrait")
        rotate(.landscapeRight)
        XCTAssertTrue(inspector.exists)
        app.buttons["Zebra"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Close Zebra"].waitForExistence(timeout: 5))
        capture("assist-inspector-landscape")
    }

    func testAssistInspectorRepeatedTabSwitchesKeepOneStablePanel() {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        let peak = app.buttons["monitor.assist.PEAK"]
        XCTAssertTrue(peak.waitForExistence(timeout: 5))
        peak.press(forDuration: 0.55)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let initialFrame = inspector.frame
        for iteration in 0..<20 {
            for title in ["False Color", "Zebra", "Peaking"] {
                app.buttons[title].firstMatch.tap()
                XCTAssertEqual(
                    app.state, .runningForeground, "Terminated at \(iteration): \(title)")
                XCTAssertTrue(app.buttons["Close \(title)"].waitForExistence(timeout: 3))
                XCTAssertEqual(inspector.frame.width, initialFrame.width, accuracy: 1)
                XCTAssertEqual(inspector.frame.height, initialFrame.height, accuracy: 1)
                if iteration == 0 { capture("assist-options-\(title)") }
            }
        }
        capture("assist-inspector-stress")
        app.buttons["Close Peaking"].tap()
        XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
    }

    func testTopRecordingFormatOpensFromLandscape() {
        app.launch()
        rotate(.landscapeLeft)
        let format = app.buttons["monitor.capture.format"]
        XCTAssertTrue(format.isHittable)
        XCTAssertGreaterThanOrEqual(format.frame.minY, 0)
        format.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["monitor.capture.panel"].firstMatch.waitForExistence(
                timeout: 5))
        capture("capture-top-format-landscape")
    }

    func testCameraPickersUseReferenceTopAndBottomAnchors() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let identifiers =
                ["iso", "shutter", "exposure", "wb", "focus", "audio", "format"]
                + (orientation == .landscapeLeft ? ["color", "mode"] : [])
            for id in identifiers {
                app.buttons["monitor.capture.\(id)"].tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), id)
                XCTAssertEqual(panel.frame.midX, app.frame.midX, accuracy: 1, id)
                XCTAssertLessThanOrEqual(panel.frame.maxY, app.frame.maxY + 1, id)
                if ["format", "color", "mode"].contains(id), orientation == .landscapeLeft {
                    XCTAssertEqual(panel.frame.minY, app.frame.minY, accuracy: 1, id)
                } else {
                    XCTAssertGreaterThan(panel.frame.minY, app.frame.minY, id)
                }
                XCTAssertTrue(app.buttons["monitor.system.record"].isHittable, id)
                XCTAssertTrue(app.buttons["monitor.system.display"].isHittable, id)
                XCTAssertFalse(app.buttons["monitor.system.zoom"].isHittable, id)
                if orientation == .landscapeLeft {
                    XCTAssertFalse(app.buttons["monitor.system.settings"].isHittable, id)
                    XCTAssertFalse(app.buttons["monitor.system.media"].isHittable, id)
                }
                capture("capture-\(id)-\(orientation.rawValue)")
                app.buttons["Close"].firstMatch.tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    func testTopPickerKeepsLowerReadoutsInteractiveAndCanBeReplaced() {
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            rotate(orientation)
            for id in ["format", "color", "mode"] {
                app.buttons["monitor.capture.\(id)"].tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), id)
                XCTAssertEqual(panel.frame.minY, app.frame.minY, accuracy: 1, id)
                let iso = app.buttons["monitor.capture.iso"]
                XCTAssertTrue(iso.isHittable, id)
                iso.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let replacement = NSPredicate { _, _ in
                    panel.exists && panel.frame.minY > self.app.frame.minY
                }
                expectation(for: replacement, evaluatedWith: app)
                waitForExpectations(timeout: 3)
                // Full ISO details can extend above the midpoint on short
                // landscape screens; the reference anchors its bottom edge.
                XCTAssertGreaterThan(panel.frame.minY, app.frame.minY, id)
                XCTAssertEqual(panel.frame.maxY, app.frame.maxY, accuracy: 1, id)
                XCTAssertEqual(app.buttons.matching(identifier: "monitor.capture.close").count, 1)
                app.buttons["monitor.capture.close"].tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    func testTopReadoutPaddingOpensThePickerWithoutMovingItsLabel() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let controls = orientation == .portrait ? ["format"] : ["format", "color", "mode"]
            for id in controls {
                let readout = app.buttons["monitor.capture.\(id)"]
                XCTAssertTrue(readout.isHittable, id)
                let center = readout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                center.withOffset(CGVector(dx: 0, dy: 18)).tap()
                let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 5), "Padding tap: \(id)")
                app.buttons["monitor.capture.close"].tap()
                XCTAssertFalse(panel.exists)
            }
        }
    }

    func testAudioMeterMovesAndRetainsOrientationOptions() {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        let audio = app.buttons["monitor.assist.AUDIO"]
        XCTAssertTrue(audio.waitForExistence(timeout: 5))
        audio.tap()
        app.buttons["Collapse View Assist tools"].tap()
        let meter = app.descendants(matching: .any)["monitor.audio.meter"].firstMatch
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        let original = meter.frame
        XCTAssertEqual(original.width, 28, accuracy: 1)
        XCTAssertEqual(original.height, 168, accuracy: 1)
        XCTAssertLessThan(original.midX, app.frame.midX)
        XCTAssertEqual(original.midY, app.frame.midY, accuracy: 1)
        let start = meter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 130, dy: -40)))
        XCTAssertGreaterThan(meter.frame.midX, original.midX + 90)
        meter.press(forDuration: 0.55)
        let horizontal = app.buttons["Horizontal"].firstMatch
        XCTAssertTrue(horizontal.waitForExistence(timeout: 5))
        horizontal.tap()
        app.switches["Show dB values"].tap()
        capture("audio-options-horizontal-db")
        app.buttons["Close Audio Levels"].tap()
        XCTAssertEqual(meter.frame.width, 168, accuracy: 1)
        XCTAssertEqual(meter.frame.height, 28, accuracy: 1)
        capture("audio-meter-moved-horizontal")
    }

    func testFalseColorReferenceStartsCenteredAndCanBePlaced() {
        app.launch()
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        app.buttons["monitor.assist.FALSE"].tap()
        app.buttons["Collapse View Assist tools"].tap()
        let key = app.descendants(matching: .any)["monitor.falseColor.reference"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertEqual(key.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(key.frame.midY, app.frame.midY, accuracy: 1)
        let original = key.frame
        capture("false-color-reference-centered")
        let start = key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 50, dy: -60)))
        XCTAssertGreaterThan(key.frame.midX, original.midX + 30)
        XCTAssertLessThan(key.frame.midY, original.midY - 40)
        capture("false-color-reference-placed")
    }

    func testMediaPageAdaptsToOrientation() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "media-fixture"
        app.launch()
        let navigation = app.otherElements["monitor.page.navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 10))
        rotate(.portrait)
        XCTAssertGreaterThan(navigation.frame.width, navigation.frame.height)
        rotate(.landscapeLeft)
        capture("media-rotation-regression")
        XCTAssertLessThan(
            navigation.frame.width, navigation.frame.height,
            "Landscape media must use its full-height navigation column")
        XCTAssertLessThan(
            navigation.frame.maxX, app.frame.midX,
            "Landscape navigation must leave room for the media detail")
    }

    func testBackButtonsStayOutsideFullHeightSidebarsAndMediaLayoutTogglesInPlace() {
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            for (control, backLabel) in [("settings", "Back to live"), ("media", "Back")] {
                let systemButtonFrame = app.buttons["monitor.system.settings"].frame
                app.buttons["monitor.system.\(control)"].tap()
                let back = app.buttons[backLabel].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                let heading = app.otherElements["monitor.page.heading"]
                let navigation = app.otherElements["monitor.page.navigation"]
                XCTAssertTrue(navigation.frame.contains(heading.frame))
                XCTAssertEqual(back.frame.width, systemButtonFrame.width, accuracy: 1)
                XCTAssertEqual(back.frame.height, systemButtonFrame.height, accuracy: 1)
                if orientation == .portrait {
                    XCTAssertTrue(navigation.frame.contains(back.frame))
                    XCTAssertLessThan(back.frame.maxX, heading.frame.minX)
                } else {
                    XCTAssertLessThan(back.frame.maxX, navigation.frame.minX)
                    XCTAssertEqual(back.frame.minY, systemButtonFrame.minY, accuracy: 1)
                    XCTAssertGreaterThan(navigation.frame.height, app.frame.height * 0.8)
                }
                XCTAssertTrue(back.isHittable)
                if control == "media" {
                    let displayControls = app.otherElements["monitor.media.displayControls"]
                    if orientation == .portrait {
                        XCTAssertGreaterThan(displayControls.frame.minY, app.frame.height * 0.8)
                        XCTAssertGreaterThan(displayControls.frame.minY, navigation.frame.maxY)
                    } else {
                        XCTAssertTrue(navigation.frame.contains(displayControls.frame))
                        XCTAssertEqual(
                            displayControls.frame.maxY, navigation.frame.maxY - 10, accuracy: 1)
                    }
                    XCTAssertFalse(app.buttons["Refresh camera media"].exists)
                    let filter = app.buttons["monitor.media.filter"]
                    let sort = app.buttons["Sort"]
                    XCTAssertTrue(filter.isHittable)
                    XCTAssertTrue(sort.isHittable)
                    XCTAssertEqual(filter.frame.height, sort.frame.height, accuracy: 1)
                    XCTAssertEqual(filter.frame.midY, sort.frame.midY, accuracy: 1)
                    filter.tap()
                    let popup = app.otherElements["monitor.media.filter.popup"]
                    XCTAssertTrue(popup.waitForExistence(timeout: 2))
                    XCTAssertGreaterThanOrEqual(popup.frame.minX, -0.5)
                    XCTAssertGreaterThanOrEqual(popup.frame.minY, -0.5)
                    XCTAssertLessThanOrEqual(popup.frame.maxX, app.frame.width + 0.5)
                    XCTAssertLessThanOrEqual(popup.frame.maxY, app.frame.height + 0.5)
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
                    XCTAssertTrue(popup.waitForNonExistence(timeout: 2))
                    let grid = app.buttons["monitor.media.layout.grid"]
                    let list = app.buttons["monitor.media.layout.list"]
                    XCTAssertTrue(grid.isHittable)
                    XCTAssertTrue(list.isHittable)
                    XCTAssertEqual(grid.frame.midY, list.frame.midY, accuracy: 1)
                    XCTAssertEqual(grid.frame.width, 32, accuracy: 1)
                    XCTAssertEqual(grid.frame.height, 28, accuracy: 1)
                    XCTAssertEqual(displayControls.frame.width, 172, accuracy: 2)
                    XCTAssertEqual(displayControls.frame.height, 34, accuracy: 2)
                    for size in ["Small", "Medium", "Large"] {
                        let button = app.buttons["\(size) thumbnails"]
                        XCTAssertTrue(button.isHittable)
                        XCTAssertTrue(displayControls.frame.contains(button.frame))
                        XCTAssertEqual(button.frame.midY, grid.frame.midY, accuracy: 1)
                        XCTAssertEqual(button.frame.width, 28, accuracy: 1)
                        XCTAssertEqual(button.frame.height, 28, accuracy: 1)
                    }
                    let originalGrid = grid.frame
                    XCTAssertTrue(
                        (grid.value as? String)?.contains("Selected") == true
                            || grid.isSelected)
                    list.tap()
                    XCTAssertTrue(
                        list.isSelected || (list.value as? String)?.contains("Selected") == true)
                    XCTAssertEqual(grid.frame.minX, originalGrid.minX, accuracy: 1)
                    XCTAssertEqual(grid.frame.width, originalGrid.width, accuracy: 1)
                    grid.tap()
                    XCTAssertTrue(
                        grid.isSelected || (grid.value as? String)?.contains("Selected") == true)
                }
                capture("\(control)-page-header-\(orientation.rawValue)")
                back.tap()
                XCTAssertTrue(app.buttons["monitor.system.record"].isHittable)
            }
        }
    }

    func testPopulatedMediaLayoutsAndPlayback() {
        for screen in ["media-fixture", "media-list", "media-selection", "playback"] {
            app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = screen
            app.launch()
            let expected =
                screen == "playback"
                ? app.buttons["Back to media"] : app.staticTexts["Media"].firstMatch
            XCTAssertTrue(expected.waitForExistence(timeout: 10))
            capture(screen + "-portrait")
            rotate(.landscapeLeft)
            capture(screen + "-landscape")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testMediaDragSelectionEntersFromHoldAndDeselectsFromSelectedClip() {
        for screen in ["media-fixture", "media-list"] {
            app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = screen
            app.launch()
            XCTAssertTrue(app.staticTexts["Review_001.MP4"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["Select Review_001.MP4"].exists)
            let first = mediaClipCenter("Review_001.MP4")
            let fourth = mediaClipCenter("Review_004.MP4")
            first.press(
                forDuration: 0.4, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["4 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Deselect Review_001.MP4"].exists)
            capture("media-drag-selected")
            first.press(
                forDuration: 0.4, thenDragTo: fourth, withVelocity: .slow, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)
            app.buttons["Clear selection"].tap()
            XCTAssertFalse(app.buttons["Select Review_001.MP4"].exists)
            app.terminate()
        }
    }

    func testMediaDragSelectionAutoScrollsAtBothEdgesAndStopsOnRelease() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "media-fixture"
        app.launch()
        XCTAssertTrue(app.staticTexts["Review_001.MP4"].waitForExistence(timeout: 10))
        app.buttons["Large thumbnails"].tap()
        let gallery = app.scrollViews["monitor.media.gallery"]
        let first = app.staticTexts["Review_001.MP4"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: -2))
        let bottom = gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(
            CGVector(dx: 0, dy: -10))
        first.press(
            forDuration: 0.4, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 6)
        XCTAssertTrue(app.buttons["Deselect Review_012.MP4"].isHittable)
        XCTAssertTrue(app.staticTexts["12 selected"].exists)
        let last = app.buttons["Deselect Review_012.MP4"]
        let stoppedFrame = last.frame
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(last.frame.minY, stoppedFrame.minY, accuracy: 1)
        let top = gallery.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
            CGVector(dx: 0, dy: 5))
        mediaClipCenter("Review_012.MP4").press(
            forDuration: 0.4, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 6)
        XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select Review_001.MP4"].isHittable)
        capture("media-drag-returned-to-top")
    }

    func testMediaDragSelectionPreservesNativeScrollingAndSidewaysRange() {
        for screen in ["media-fixture", "media-list"] {
            app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = screen
            app.launch()
            XCTAssertTrue(app.staticTexts["Review_001.MP4"].waitForExistence(timeout: 10))
            let gallery = app.scrollViews["monitor.media.gallery"]
            XCTAssertTrue(gallery.waitForExistence(timeout: 5))
            mediaClipCenter("Review_001.MP4").press(
                forDuration: 0.4, thenDragTo: mediaClipCenter("Review_002.MP4"),
                withVelocity: .slow,
                thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["2 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)

            if screen == "media-list" {
                mediaClipCenter("Review_003.MP4").press(
                    forDuration: 0.05,
                    thenDragTo: mediaClipCenter("Review_003.MP4").withOffset(
                        CGVector(dx: 80, dy: 4)),
                    withVelocity: .slow, thenHoldForDuration: 0)
                XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
            } else {
                mediaClipCenter("Review_003.MP4").press(
                    forDuration: 0.05, thenDragTo: mediaClipCenter("Review_004.MP4"),
                    withVelocity: .slow, thenHoldForDuration: 0)
                XCTAssertTrue(app.staticTexts["4 selected"].waitForExistence(timeout: 5))
            }
            let selected = screen == "media-list" ? "3 selected" : "4 selected"
            let before = visibleReviewClips()
            gallery.swipeUp(velocity: .fast)
            var after = visibleReviewClips()
            if after == before {
                gallery.swipeUp(velocity: .fast)
                after = visibleReviewClips()
            }
            XCTAssertTrue(app.staticTexts[selected].exists)
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)
            XCTAssertNotEqual(
                before, after, "\(screen) must scroll natively while selection stays active")
            gallery.swipeDown(velocity: .fast)
            XCTAssertTrue(app.staticTexts["Review_001.MP4"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[selected].exists)

            let origin = mediaClipCenter("Review_001.MP4")
            origin.press(
                forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 4, dy: 220)),
                withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts[selected].exists)
            XCTAssertFalse(app.buttons["Back to media"].exists)

            origin.press(
                forDuration: 0.4, thenDragTo: mediaClipCenter("Review_004.MP4"),
                withVelocity: .slow,
                thenHoldForDuration: 0)
            XCTAssertTrue(app.staticTexts["0 selected"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Clear selection"].exists)
            app.buttons["Clear selection"].tap()
            XCTAssertFalse(app.buttons["Select Review_001.MP4"].exists)
            app.terminate()
        }
    }

    func testHomePairAndOperatorPages() {
        for screen in ["cameras", "pair", "settings", "media"] {
            app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = screen
            app.launch()
            let expected = [
                "cameras": "Your cameras", "pair": "Find your camera",
                "settings": "Operator Setup", "media": "Media",
            ]
            XCTAssertTrue(
                app.staticTexts[expected[screen]!].firstMatch.waitForExistence(timeout: 10))
            capture(screen + "-portrait")
            rotate(.landscapeLeft)
            capture(screen + "-landscape")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testAllOperatorTabsRetainSelectionAcrossRotation() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "settings"
        app.launch()
        let tabs = app.scrollViews["monitor.settings.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        let sections = [
            ("Link", "Connection state and link behavior."),
            ("Sharing", "Share this feed with OpenPocketCine devices on the same camera Wi-Fi."),
            ("View Assist", "Behavior for live-view tools."),
            ("Controls", "Touch behavior and safety."),
            ("Display", "Live view buttons and chrome."),
            ("Storage", "Local cache and integrations."),
            ("System", "App-level behavior."),
        ]
        for (title, subtitle) in sections {
            let tab = app.buttons["monitor.settings.tab.\(title)"]
            reveal(tab, in: tabs, portrait: true)
            XCTAssertTrue(tab.isHittable, "\(title) must be reachable in the scrolling tab rail")
            tab.tap()
            XCTAssertTrue(app.staticTexts[subtitle].waitForExistence(timeout: 5))
            capture(
                "settings-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-portrait")
        }
        rotate(.landscapeLeft)
        XCTAssertTrue(app.staticTexts["App-level behavior."].exists)
        for (title, subtitle) in sections {
            let tab = app.buttons["monitor.settings.tab.\(title)"]
            reveal(tab, in: tabs, portrait: false)
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(app.staticTexts[subtitle].waitForExistence(timeout: 5))
            capture(
                "settings-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-landscape")
        }
    }

    func testPlaybackInfoLoopAndShareReturnToTheSamePlayer() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "playback"
        app.launch()
        let info = app.buttons["Clip information"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let closeInfo = app.buttons["Close clip information"]
        XCTAssertTrue(closeInfo.waitForExistence(timeout: 5))
        capture("playback-info-portrait")
        rotate(.landscapeLeft)
        XCTAssertTrue(closeInfo.isHittable)
        capture("playback-info-landscape")
        closeInfo.tap()
        let loop = app.buttons["Loop playback"]
        XCTAssertEqual(loop.value as? String, "Off")
        loop.tap()
        XCTAssertEqual(loop.value as? String, "On")
        app.buttons["Share clip"].tap()
        XCTAssertTrue(app.staticTexts["Frame.io"].firstMatch.waitForExistence(timeout: 5))
        capture("playback-share-landscape")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertEqual(loop.value as? String, "On", "Dismissing Share must preserve player state")
        app.buttons["Hide playback controls"].tap()
        let restore = app.buttons["Show playback controls"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(info.isHittable)
        XCTAssertEqual(loop.value as? String, "On")
    }

    func testPlaybackChromeAndCameraHomeSafeAreas() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "cameras"
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            rotate(orientation)
            let pair = app.buttons["cameras.pair"]
            XCTAssertTrue(pair.waitForExistence(timeout: 10))
            XCTAssertEqual(pair.frame.midX, app.frame.midX, accuracy: 2)
            capture("centered-cameras-\(orientation.rawValue)")
        }
        app.terminate()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "playback"
        app.launch()
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight, .portrait] {
            rotate(orientation)
            let back = app.buttons["Back to media"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            XCTAssertTrue(back.isHittable)
            XCTAssertEqual(back.frame.width, 54, accuracy: 1)
            for title in [
                "Favorite clip", "Clip information", "Share clip", "Delete clip from camera",
            ] {
                let button = app.buttons[title]
                XCTAssertTrue(button.isHittable, title)
                XCTAssertLessThanOrEqual(button.frame.maxX, app.frame.maxX - 12, title)
                XCTAssertGreaterThanOrEqual(button.frame.minX, 12, title)
            }
            capture("polished-playback-\(orientation.rawValue)")
        }
        rotate(.landscapeLeft)
        app.buttons["monitor.assists.expand"].tap()
        app.buttons["monitor.assist.LUT"].press(forDuration: 0.6)
        let inspector = app.otherElements["monitor.inspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let lut = inspector.buttons["LUT"].firstMatch
        XCTAssertTrue(lut.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(lut.frame.minX, 55)
        capture("playback-assist-cutout-clearance")
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
        capture("share-upcoming-destinations")
    }

    /// #406: saved cameras show their setups; Add setup offers Wi-Fi or Hotspot. Chips and
    /// Connect are not tapped here because they start a real connection.
    func testSavedCameraSetupChipsAndAddSetupFlow() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "cameras"
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let wifi = app.buttons["cameras.setup.wifi"]
            XCTAssertTrue(wifi.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["cameras.setup.phoneHotspot"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: "cameras.setup.cameraWiFi").count, 2)
            XCTAssertGreaterThanOrEqual(wifi.frame.height, 43.5)
            // Only the Nano fixture has a setup left to add.
            let add = app.buttons["cameras.addSetup"]
            XCTAssertEqual(app.buttons.matching(identifier: "cameras.addSetup").count, 1)
            capture("camera-setup-chips-\(orientation.rawValue)")
            // Landscape shows one and a half cards; the Nano's chip is below the fold.
            for _ in 0..<3 where !add.isHittable { app.scrollViews.firstMatch.swipeUp() }
            add.tap()
            let chooseWiFi = app.buttons["addSetup.wifi"]
            XCTAssertTrue(chooseWiFi.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["addSetup.phoneHotspot"].isHittable)
            capture("add-setup-choose-\(orientation.rawValue)")
            chooseWiFi.tap()
            // Wi-Fi asks for location (iOS names the current network only with it).
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                .buttons["Allow While Using App"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            // Wi-Fi scans on open; the simulator has no camera, so it says so.
            XCTAssertTrue(
                app.descendants(matching: .any)["addSetup.scanStatus"].waitForExistence(timeout: 5))
            capture("add-setup-wifi-\(orientation.rawValue)")
            app.navigationBars.buttons["Add setup"].tap()
            app.buttons["addSetup.phoneHotspot"].tap()
            let name = app.textFields["addSetup.hotspotName"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertTrue(
                app.otherElements["addSetup.hotspotStatus"].exists
                    || app.staticTexts.containing(
                        NSPredicate(format: "label CONTAINS 'Personal Hotspot'")
                    ).count > 0)
            capture("add-setup-hotspot-\(orientation.rawValue)")
            app.navigationBars.buttons["Add setup"].tap()
            app.navigationBars.buttons["Cancel"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            app.scrollViews.firstMatch.swipeDown()
        }
    }

    /// The simulator never has a hotspot, so a hotspot connect must ask first. Cancel
    /// leaves the camera untouched.
    func testHotspotConnectAsksToTurnOnPersonalHotspot() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "cameras"
        app.launch()
        rotate(.portrait)
        let hotspot = app.buttons["cameras.setup.phoneHotspot"]
        XCTAssertTrue(hotspot.waitForExistence(timeout: 10))
        hotspot.tap()
        let alert = app.alerts["Turn on Personal Hotspot"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Open Settings"].exists)
        XCTAssertTrue(alert.buttons["Connect"].exists)
        capture("hotspot-connect-prompt")
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["CONNECTING"].exists)
    }

    func testConnectingCardShowsOneProgressLine() {
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "cameras"
        app.launchEnvironment["OPV_UI_REVIEW_CONNECTING"] = "1"
        app.launch()
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            rotate(orientation)
            let progress = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH 'Moving the camera to Studio-5G'"))
                .firstMatch
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Cancel connecting to Studio camera"].exists)
            capture("connecting-progress-\(orientation.rawValue)")
        }
    }

    private func reveal(_ tab: XCUIElement, in rail: XCUIElement, portrait: Bool) {
        for _ in 0..<6 where !tab.isHittable {
            if portrait {
                if tab.frame.minX < rail.frame.minX { rail.swipeRight() } else { rail.swipeLeft() }
            } else {
                if tab.frame.minY < rail.frame.minY { rail.swipeDown() } else { rail.swipeUp() }
            }
        }
    }

    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let rotated = NSPredicate { _, _ in
            (self.app.frame.width > self.app.frame.height) == landscape
        }
        expectation(for: rotated, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        // XCUI updates the application frame before UIKit finishes rotating its
        // content. Require both the window and first control to settle before
        // asserting hit targets or capturing the device's physical pixels.
        var previous: [CGRect] = []
        var unchangedSince = Date()
        let settled = NSPredicate { _, _ in
            let frames = [self.app.frame, self.app.buttons.firstMatch.frame]
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

    private func mediaClipCenter(_ filename: String) -> XCUICoordinate {
        app.otherElements["monitor.media.clip.UI-REVIEW/\(filename)"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    private func visibleReviewClips() -> [String] {
        (1...12).compactMap { index in
            let name = String(format: "Review_%03d.MP4", index)
            let clip = app.staticTexts[name]
            return clip.exists && clip.isHittable ? name : nil
        }
    }
}
