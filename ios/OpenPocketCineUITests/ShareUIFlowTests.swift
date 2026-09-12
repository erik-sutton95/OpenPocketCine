import XCTest

/// Visits production Share options with an actual cached, generated review clip.
/// Never starts export, Photos access, system sharing, uploads, or a network hop.
final class ShareUIFlowTests: XCTestCase {
    func testCachedClipOptionsSurviveRotationAndReturnToSamePlayer() throws {
        continueAfterFailure = false
        guard let clip = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"],
            FileManager.default.fileExists(atPath: clip)
        else { throw XCTSkip("Pass OPV_SIM_FEED_CLIP pointing to the generated review video") }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["OPV_UI_REVIEW_SCREEN"] = "playback"
        app.launchEnvironment["OPV_SIM_FEED_CLIP"] = clip
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let share = app.buttons["Share clip"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["monitor.review.cacheError"].exists)
        let loop = app.buttons["Loop playback"]
        if loop.value as? String == "Off" { loop.tap() }
        share.tap()

        let destination = app.buttons["monitor.share.destination.nativeShare"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isEnabled, "The review clip must use the real local cache seam")
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "on-camera clip"))
                .firstMatch.exists)
        destination.tap()
        let summary = app.staticTexts["monitor.share.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 clip"))
        XCTAssertFalse(summary.label.contains("Size unavailable"))
        let summaryBeforeRotation = summary.label
        let begin = app.buttons["monitor.share.begin"]
        XCTAssertTrue(begin.isEnabled)
        XCTAssertTrue(begin.isHittable)
        capture("share-options-cached-portrait")

        let scroll = app.scrollViews["monitor.share.optionsScroll"]
        let mp4 = app.buttons["MP4"]
        for _ in 0..<5 where !mp4.isHittable && scroll.exists { scroll.swipeUp() }
        XCTAssertTrue(mp4.isHittable)
        mp4.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: mp4)
        let selectionResult = XCTWaiter.wait(for: [selected], timeout: 2)
        if selectionResult != .completed {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "share-format-selection-failure"
            tree.lifetime = .keepAlways
            add(tree)
        }
        capture("share-format-after-tap")
        XCTAssertTrue(mp4.isSelected)
        XCTAssertFalse(app.buttons["MOV"].isSelected)
        for text in [
            "MOV preserves quality; MP4 is more widely compatible.",
            "Filename, capture date, and size (best-effort JSON sidecar).",
        ] {
            let help = app.staticTexts[text]
            for _ in 0..<5 where !help.isHittable && scroll.exists { scroll.swipeUp() }
            XCTAssertTrue(help.isHittable, "Options help is visible inline and reachable")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        let close = app.buttons["monitor.share.close"]
        var previous: [CGRect] = []
        var unchangedSince = Date()
        let settled = NSPredicate { _, _ in
            guard app.frame.width > app.frame.height else { return false }
            let frames = [app.frame, close.frame, summary.frame]
            if frames != previous {
                previous = frames
                unchangedSince = Date()
                return false
            }
            return Date().timeIntervalSince(unchangedSince) >= 0.5
        }
        expectation(for: settled, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.buttons["monitor.share.back"].isHittable)
        XCTAssertTrue(begin.isHittable)
        XCTAssertEqual(summary.label, summaryBeforeRotation)
        XCTAssertTrue(mp4.isSelected, "The typed format choice must survive rotation")
        XCTAssertFalse(app.buttons["MOV"].isSelected)
        capture("share-options-cached-landscape")

        app.buttons["monitor.share.back"].tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isEnabled)
        destination.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(mp4.isSelected, "Back and reselect must preserve export options")
        close.tap()
        XCTAssertFalse(summary.exists)
        XCTAssertTrue(app.buttons["Clip information"].isHittable)
        XCTAssertEqual(
            loop.value as? String, "On", "Closing options must preserve the same player state")
        XCTAssertTrue(share.isHittable)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
