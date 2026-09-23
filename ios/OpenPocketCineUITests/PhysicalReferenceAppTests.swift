import XCTest

/// Opt-in driver for the vendor reference app during a phone RVI capture.
/// `OPV_REFERENCE_TAPS` is a `|`-separated list of accessibility labels (or
/// `@x,y` normalized coordinates) tapped in order; `OPV_REFERENCE_DWELL` is how
/// long to stay afterwards. Each run attaches the element tree and screenshots.
final class PhysicalReferenceAppTests: XCTestCase {
    func testDriveReferenceApp() throws {
        let env = ProcessInfo.processInfo.environment
        guard let bundle = env["OPV_REFERENCE_BUNDLE"], !bundle.isEmpty else {
            throw XCTSkip("Requires the opted-in reference capture run")
        }
        let app = XCUIApplication(bundleIdentifier: bundle)
        if env["OPV_REFERENCE_LAUNCH"] == "1" { app.launch() } else { app.activate() }
        Thread.sleep(forTimeInterval: 3)
        snapshot(app, "start")
        let taps = (env["OPV_REFERENCE_TAPS"] ?? "").split(separator: "|").map(String.init)
        for (index, entry) in taps.enumerated() {
            // `?label` is optional: a system prompt that may or may not appear.
            let optional = entry.hasPrefix("?")
            let target = optional ? String(entry.dropFirst()) : entry
            if target.hasPrefix("@") {
                let parts = target.dropFirst().split(separator: ",").compactMap { Double($0) }
                guard parts.count == 2 else { continue }
                app.coordinate(withNormalizedOffset: CGVector(dx: parts[0], dy: parts[1])).tap()
            } else if target.hasPrefix("cc:") {
                // Control Center makes the scene inactive without backgrounding.
                let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.001))
                    .press(forDuration: 0.1, thenDragTo:
                        board.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)))
                Thread.sleep(forTimeInterval: Double(target.dropFirst(3)) ?? 10)
                snapshot(app, "control-center-\(index)")
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
                    .press(forDuration: 0.1, thenDragTo:
                        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            } else if target.hasPrefix("bt:") {
                // Bluetooth off in Control Center drops the camera BLE link.
                let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.001))
                    .press(forDuration: 0.1, thenDragTo:
                        board.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)))
                Thread.sleep(forTimeInterval: 1.5)
                let toggle = board.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.47))
                toggle.tap()
                snapshot(app, "bt-off-\(index)")
                Thread.sleep(forTimeInterval: Double(target.dropFirst(3)) ?? 5)
                toggle.tap()
                Thread.sleep(forTimeInterval: 1)
                snapshot(app, "bt-on-\(index)")
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
                    .press(forDuration: 0.1, thenDragTo:
                        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            } else if target.hasPrefix("bg:") {
                XCUIDevice.shared.press(.home)
                Thread.sleep(forTimeInterval: Double(target.dropFirst(3)) ?? 5)
                app.activate()
            } else if target.hasPrefix("~") {
                Thread.sleep(forTimeInterval: Double(target.dropFirst()) ?? 1)
                continue
            } else {
                // System prompts (Wi-Fi join, permissions) live in SpringBoard.
                let match = NSPredicate(format: "label == %@ OR identifier == %@", target, target)
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                let inApp = app.descendants(matching: .any).matching(match).firstMatch
                let inSystem = springboard.descendants(matching: .any).matching(match).firstMatch
                let found = NSPredicate { _, _ in inApp.exists || inSystem.exists }
                let waited = XCTNSPredicateExpectation(predicate: found, object: nil)
                let element = XCTWaiter.wait(for: [waited], timeout: 10) == .completed
                    ? (inSystem.exists ? inSystem : inApp) : inApp
                guard element.exists else {
                    if optional { continue }
                    snapshot(app, "missing-\(index)")
                    XCTFail("no element \(target)")
                    return
                }
                if element.exists { element.tap() }
            }
            Thread.sleep(forTimeInterval: 2)
            snapshot(app, "after-\(index)")
        }
        let dwell = Double(env["OPV_REFERENCE_DWELL"] ?? "0") ?? 0
        let end = Date().addingTimeInterval(dwell)
        var shot = 0
        while Date() < end {
            Thread.sleep(forTimeInterval: min(60, max(0, end.timeIntervalSinceNow)))
            shot += 1
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "dwell-\(shot)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        snapshot(app, "end")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
