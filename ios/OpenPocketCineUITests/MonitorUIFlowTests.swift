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
            capture("monitor-\(orientation.rawValue)")
        }
    }

    func testAssistPaletteAndValueDrumRemainReachable() {
        app.launch()
        let expand = app.buttons["monitor.assists.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let wave = app.buttons["monitor.assist.WAVE"]
        XCTAssertTrue(wave.waitForExistence(timeout: 5))
        wave.tap()
        capture("assist-palette")
        app.buttons["Collapse View Assist tools"].tap()
        app.buttons["monitor.capture.iso"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Value"].firstMatch.waitForExistence(timeout: 5))
        capture("iso-drum")
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
        app.buttons["Close Gimbal"].tap()
        app.buttons["monitor.system.zoom"].press(forDuration: 0.55)
        let dial = app.descendants(matching: .any)["monitor.zoom.dial"].firstMatch
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["monitor.system.record"].isHittable,
            "Record remains reachable above the zoom disc")
        XCTAssertTrue(app.buttons["monitor.system.display"].isHittable)
        capture("zoom-dial-landscape")
        rotate(.portrait)
        XCTAssertTrue(dial.isHittable)
        capture("zoom-dial-portrait")
        app.buttons["Close zoom dial"].tap()
        XCTAssertTrue(app.buttons["monitor.capture.iso"].isHittable)
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
}
