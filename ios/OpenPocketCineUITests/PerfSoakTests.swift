import XCTest

/// Physical iPhone + saved Pocket 4 Pro power/thermal soak. Opt-in only.
///
/// Sets a named assist profile, then holds the live monitor with no input and
/// no accessibility queries so the host can attach Instruments (Power Profiler,
/// Time Profiler, Metal System Trace) without the runner waking the app.
/// `tools/perf-soak.sh` starts tracing on the `PERF_SOAK_HOLD_BEGIN` marker.
final class PerfSoakTests: XCTestCase {
    /// Assists the soak drives. Each profile turns its listed tools on and the rest off.
    private static let driven = ["LUT", "PEAK", "FALSE", "ZEBRA", "WAVE", "HISTO", "VECTOR"]
    private static let profiles: [String: [String]] = [
        "clean": [],
        "lut": ["LUT"],
        "pro": ["LUT", "PEAK", "WAVE"],
        "heavy": ["LUT", "PEAK", "ZEBRA", "WAVE", "HISTO", "VECTOR"],
    ]

    func testPhysicalPerfSoak() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Physical iPhone + Pocket 4 Pro required")
        #endif
        let env = ProcessInfo.processInfo.environment
        guard env["OPV_PERF_SOAK"] == "1" else {
            throw XCTSkip("Set OPV_PERF_SOAK=1 (tools/perf-soak.sh)")
        }
        let name = env["OPV_PERF_PROFILE"] ?? "pro"
        guard let wanted = Self.profiles[name] else {
            throw XCTSkip("Unknown OPV_PERF_PROFILE \(name)")
        }
        let hold = TimeInterval(env["OPV_PERF_SOAK_S"] ?? "") ?? 90

        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        // The host launches the app first (devicectl); XCTest's own target-app
        // launch fails for Release builds on device, so attach instead.
        if env["OPV_PERF_ATTACH"] == "1" { app.activate() } else { app.launch() }
        // Detached: configure, then leave the app running with XCTest gone, so
        // the host trace does not include UI-automation accessibility work.
        let detach = env["OPV_PERF_DETACH"] == "1"
        defer { if !detach { app.terminate() } }
        // Camera Wi-Fi join / Bluetooth / local network prompts (same set as FeedStressTests).
        addUIInterruptionMonitor(withDescription: "camera connection alerts") { alert in
            for title in ["Join", "Allow", "OK"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        if env["OPV_PERF_DUMP"] == "1" {
            // Diagnostic: print what is on screen, then stop.
            print("PERF_SOAK_DUMP\n\(app.debugDescription)")
            attach("perf-soak-dump", app)
            return
        }
        let record = app.buttons["monitor.system.record"]
        let settings = app.buttons["monitor.system.settings"]
        if env["OPV_PERF_STOP"] == "1" {
            // Second pass of a detached take: stop REC, prove it stopped.
            XCTAssertTrue(record.waitForExistence(timeout: 10), "no live monitor to stop REC")
            record.tap()
            let stop = app.buttons["Stop"]
            if stop.waitForExistence(timeout: 3) { stop.tap() }
            Thread.sleep(forTimeInterval: 2)
            attach("perf-soak-\(name)-stopped", app)
            return
        }
        let liveDeadline = Date().addingTimeInterval(90)
        // Release has no stress auto-reconnect: tap the nearby saved camera's Connect.
        let connect = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Connect OsmoPocket4'")
        ).firstMatch
        var lastConnectTap = Date.distantPast
        while !(record.exists || settings.exists) && Date() < liveDeadline {
            let join = springboard.alerts.buttons["Join"]
            if join.exists { join.tap() }
            if connect.exists && connect.isHittable && Date().timeIntervalSince(lastConnectTap) > 20 {
                connect.tap()
                lastConnectTap = Date()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(record.exists || settings.exists, "no live monitor within 90s")
        // Let the stream, decoder and looks settle before changing assists.
        Thread.sleep(forTimeInterval: 8)

        let expand = app.buttons["monitor.assists.expand"]
        if expand.waitForExistence(timeout: 4) { expand.tap() }
        Thread.sleep(forTimeInterval: 0.5)
        var applied: [String] = []
        for tool in Self.driven {
            let button = app.buttons["monitor.assist.\(tool)"]
            guard button.waitForExistence(timeout: 2) else { continue }
            let on = (button.value as? String) == "On"
            if on != wanted.contains(tool) {
                button.tap()
                Thread.sleep(forTimeInterval: 0.6)
            }
            if (button.value as? String) == "On" { applied.append(tool) }
        }
        let collapse = app.buttons["monitor.assists.collapse"]
        if collapse.exists { collapse.tap() }
        let labeled = app.buttons["Collapse View Assist tools"]
        if labeled.exists { labeled.tap() }
        // Settle chrome animations and first-use shader/LUT preparation.
        Thread.sleep(forTimeInterval: 10)
        attach("perf-soak-\(name)-start", app)

        // Optional camera recording (writes a clip to the card) for the REC chrome path.
        let recordTake = env["OPV_PERF_RECORD"] == "1"
        if recordTake {
            record.tap()
            // REC asks "Start recording?" first; confirm it.
            let start = app.buttons["Start"]
            if start.waitForExistence(timeout: 3) { start.tap() }
            Thread.sleep(forTimeInterval: 3)
        }
        print("PERF_SOAK_HOLD_BEGIN profile=\(name) on=\(applied.joined(separator: ",")) rec=\(recordTake) hold=\(Int(hold))")
        if recordTake { attach("perf-soak-\(name)-recording", app) }
        if detach { return }
        // ponytail: plain sleep, no queries; the host trace is the measurement.
        Thread.sleep(forTimeInterval: hold)
        print("PERF_SOAK_HOLD_END profile=\(name)")
        if recordTake {
            record.tap()
            let stop = app.buttons["Stop"]
            if stop.waitForExistence(timeout: 3) { stop.tap() }
            Thread.sleep(forTimeInterval: 2)
        }

        attach("perf-soak-\(name)-end", app)
        XCTAssertTrue(record.exists || settings.exists, "live monitor lost during soak")
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
