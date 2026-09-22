import UIKit
import XCTest

/// Opt-in presentation proof on the real saved camera connection. This test only
/// opens and scrolls Motion Control and opens/closes its zoom disc; it never
/// changes zoom or a programmed move.
final class PhysicalMotionZoomTests: XCTestCase {
    func testExistingZoomDiscPreservesEditorAndFixedActions() throws {
        guard ProcessInfo.processInfo.environment["OPV_PHYSICAL_UI_REVIEW"] == "1" else {
            throw XCTSkip("Requires an opted-in physical run with a saved Pocket 4 Pro")
        }
        #if targetEnvironment(simulator)
            throw XCTSkip("Requires a physical iPhone and real camera connection")
        #endif
        continueAfterFailure = false
        let originalOrientation = XCUIDevice.shared.orientation
        let app = XCUIApplication()
        app.launchEnvironment["OPV_PHYSICAL_UI_REVIEW"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS_LIMIT_S"] = "600"
        app.launchEnvironment["OPV_FEED_STRESS_RECORD"] = "0"
        app.launchEnvironment["OPV_FEED_STRESS_INJECT"] = ""
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = originalOrientation
        }

        let controls = app.buttons["monitor.system.gimbalControls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 60), "Saved camera must reconnect")
        wait(until: { (Int(self.snapshot(app)["pres"] ?? "0") ?? 0) > 0 },
            "Real live view must present before checking Motion Control")
        XCTAssertEqual(snapshot(app)["rec"], "0", "Camera must remain idle")
        controls.tap()
        let open = app.buttons["motion.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let title = app.staticTexts["motion.editor.title"]
        let zoom = app.buttons["monitor.system.zoom"]
        let scroll = app.scrollViews["motion.editor.scroll"]
        let clear = app.buttons["motion.clear"]
        let start = app.buttons["motion.startStop"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        let originalZoom = zoom.label
        let points = ["A", "B", "C"].map { app.staticTexts["motion.waypoint.\($0).readout"] }
        let originalPoints = points.map(\.label)

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            var previousFrames: [CGRect] = []
            var unchangedSince = Date()
            wait(until: {
                guard (app.frame.width > app.frame.height) == orientation.isLandscape,
                    zoom.isHittable, clear.isHittable, start.isHittable
                else { return false }
                let frames = [app.frame, title.frame, zoom.frame, clear.frame, start.frame]
                if frames != previousFrames {
                    previousFrames = frames
                    unchangedSince = Date()
                    return false
                }
                return Date().timeIntervalSince(unchangedSince) >= 0.5
            }, "Editor must settle with zoom and actions visible")

            // Drag in the settings margin, away from every waypoint, dial and toggle.
            for _ in 0..<3 { scrollMargin(scroll, towardBottom: false) }
            XCTAssertTrue(zoom.isEnabled, "Real idle camera must permit manual zoom")
            XCTAssertTrue(app.buttons["motion.close"].isHittable)
            XCTAssertLessThanOrEqual(scroll.frame.maxY, clear.frame.minY)
            XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
            XCTAssertGreaterThanOrEqual(start.frame.height, 44)
            let fixedFrames = [title.frame, zoom.frame, clear.frame, start.frame]
            let name = orientation.isLandscape ? "landscape" : "portrait"
            attachScreenshot("physical-motion-zoom-\(name)-settings-top", app: app)

            for _ in 0..<5 {
                if (scroll.value as? String) == "End of settings" { break }
                scrollMargin(scroll, towardBottom: true)
            }
            XCTAssertEqual(scroll.value as? String, "End of settings")
            XCTAssertTrue(app.switches["motion.loop"].isHittable)
            for (element, frame) in zip([title, zoom, clear, start], fixedFrames) {
                XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1)
                XCTAssertEqual(element.frame.minX, frame.minX, accuracy: 1)
                XCTAssertTrue(element.isHittable)
            }
            XCTAssertEqual(zoom.label, originalZoom, "Scrolling must not adjust the lens")
            XCTAssertEqual(points.map(\.label), originalPoints, "Scrolling must not edit the program")
            attachScreenshot("physical-motion-zoom-\(name)-settings-end", app: app)
            zoom.press(forDuration: 0.55)
            let dial = app.descendants(matching: .any)["monitor.zoom.dial"].firstMatch
            XCTAssertTrue(dial.waitForExistence(timeout: 5))
            XCTAssertTrue(dial.isHittable)
            XCTAssertFalse(clear.isHittable, "The disc must own input above the editor")
            attachScreenshot("physical-motion-zoom-\(name)-disc", app: app)
            app.buttons["Close zoom dial"].tap()
            wait(until: { !dial.isHittable && clear.isHittable },
                "Closing the disc must restore the full editor after its exit transition")
            XCTAssertTrue(title.exists)
            XCTAssertTrue(clear.isHittable)
            XCTAssertFalse(app.buttons["motion.expand"].exists)
            XCTAssertFalse(app.sliders["motion.zoom"].exists)
            XCTAssertEqual(zoom.label, originalZoom, "Opening the disc must not adjust the lens")
            XCTAssertEqual(points.map(\.label), originalPoints)
            let before = Int(snapshot(app)["pres"] ?? "0") ?? 0
            wait(until: { (Int(self.snapshot(app)["pres"] ?? "0") ?? 0) > before },
                "Live view must continue presenting while the editor is open")
            XCTAssertEqual(snapshot(app)["rec"], "0", "Camera must remain idle")
        }
        app.buttons["motion.close"].tap()
        XCTAssertFalse(title.exists)
    }

    private func scrollMargin(_ scroll: XCUIElement, towardBottom: Bool) {
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: towardBottom ? 0.85 : 0.15))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: towardBottom ? 0.15 : 0.85))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    private func wait(until predicate: @escaping () -> Bool, _ message: String) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 20), .completed, message)
    }

    private func snapshot(_ app: XCUIApplication) -> [String: String] {
        let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
        guard probe.exists, let value = probe.value as? String else { return [:] }
        return Dictionary(value.split(separator: " ").compactMap {
            let pair = $0.split(separator: "=", maxSplits: 1)
            return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
        }, uniquingKeysWith: { _, new in new })
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
