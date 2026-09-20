import CoreFoundation
import XCTest

/// Physical iPhone + Pocket 4 Pro feed stress. Opt-in only.
///
/// Asserts source / decoded / present *counter* progress from `feed.stress.snapshot`.
/// Cached FPS and historical journals are not pass criteria. Simulator and
/// missing `OPV_FEED_STRESS=1` skip; a missing live camera fails.
final class FeedStressTests: XCTestCase {
    private var app: XCUIApplication!
    private var seed: UInt64 = 20_260_914
    private var limitS: TimeInterval = 300
    private var recordOptIn = false
    private var injectOptIn = false
    private var deadline: Date = .distantFuture
    private var isoOriginal = ""
    private var failures: [String] = []
    private var rng = FeedStressSeed(state: 20_260_914)
    private var finished = false
    private var identityProofOriginalLUT: Bool?
    private var selectedScenarios = FeedStressScenario.core

    override func setUp() {
        continueAfterFailure = true
        super.setUp()
    }

    override func tearDown() {
        if app != nil {
            finishSafely()
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSeededPhysicalFeedStress() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Physical iPhone + Pocket 4 Pro required")
        #endif
        let env = ProcessInfo.processInfo.environment
        guard env["OPV_FEED_STRESS"] == "1" else {
            throw XCTSkip("Set OPV_FEED_STRESS=1 (just ios-feed-stress / tools/feed-stress-run.sh)")
        }
        seed = UInt64(env["OPV_FEED_STRESS_SEED"] ?? "") ?? 20_260_914
        limitS = TimeInterval(env["OPV_FEED_STRESS_LIMIT_S"] ?? "") ?? 300
        if limitS < 60 { limitS = 60 }
        // Reserve the final minute inside the app recorder's 30-minute cap.
        if limitS > 1_740 { limitS = 1_740 }
        recordOptIn = env["OPV_FEED_STRESS_RECORD"] == "1"
        injectOptIn = !(env["OPV_FEED_STRESS_INJECT"] ?? "").isEmpty
        if let filter = env["OPV_FEED_STRESS_SCENARIOS"], !filter.isEmpty {
            let names = filter.split(separator: ",").map(String.init)
            selectedScenarios = FeedStressScenario.selectable.filter { names.contains($0.rawValue) }
            guard selectedScenarios.count == names.count else {
                throw FeedStressError.halted("Unknown or duplicate scenario filter")
            }
        }
        let steadyOnly = selectedScenarios == [.steadyFeed]
        if selectedScenarios.contains(.steadyFeed) {
            guard steadyOnly, !recordOptIn, !injectOptIn, limitS <= 1_560 else {
                throw FeedStressError.halted(
                    "steadyFeed must run alone, without recording/injection, for at most 1560s")
            }
        }
        rng = FeedStressSeed(state: seed == 0 ? 1 : seed)
        deadline = Date().addingTimeInterval(limitS)

        app = XCUIApplication()
        app.launchEnvironment["OPV_FEED_STRESS"] = "1"
        app.launchEnvironment["OPV_FEED_STRESS_SEED"] = "\(seed)"
        // Keep counters alive through a final in-flight scenario and teardown.
        app.launchEnvironment["OPV_FEED_STRESS_LIMIT_S"] =
            "\(Int(limitS) + (steadyOnly ? 240 : 60))"
        if recordOptIn { app.launchEnvironment["OPV_FEED_STRESS_RECORD"] = "1" }
        if let inject = env["OPV_FEED_STRESS_INJECT"], !inject.isEmpty {
            app.launchEnvironment["OPV_FEED_STRESS_INJECT"] = inject
        }
        XCUIDevice.shared.orientation = .portrait
        addUIInterruptionMonitor(
            withDescription: "Bluetooth, local network, camera Wi-Fi Join"
        ) { alert in
            Self.handleAuthorizedSystemAlert(alert)
        }
        app.launch()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()

        try waitForLiveMonitor()
        try enablePeakingForDecodeProof()
        if selectedScenarios.contains(where: {
            [FeedStressScenario.mediaReturn, .steadyFeed].contains($0)
        }) {
            try establishIdentityProofMode()
        }
        isoOriginal = captureValue("monitor.capture.iso")
        try waitForHealthyBaseline(minimum: injectOptIn ? 30 : 8)

        // The uninterrupted interval starts after cold launch, setup and the
        // healthy baseline. Preserve historical timing for the default mix.
        if steadyOnly { deadline = Date().addingTimeInterval(limitS) }
        var cycle = 0
        var completedScenarios = 0
        while Date() < deadline {
            if thermalHalt() {
                failures.append("thermal halt before completing the requested run")
                break
            }
            cycle += 1
            var scenarios = selectedScenarios
            if recordOptIn { scenarios.append(.briefRecord) }
            if injectOptIn { scenarios.append(.injectFault) }
            scenarios.shuffle(using: &rng)
            for scenario in scenarios {
                if Date() > deadline { break }
                if thermalHalt() {
                    failures.append("thermal halt before completing the requested run")
                    break
                }
                do {
                    try run(scenario)
                    completedScenarios += 1
                    record(scenario, "pass", extra: "cycle=\(cycle)")
                } catch {
                    record(scenario, "fail", extra: "cycle=\(cycle) \(error)")
                    failures.append("cycle \(cycle) \(scenario.rawValue): \(error)")
                }
                dismissChrome()
            }
            if steadyOnly { break }
        }
        if completedScenarios == 0 {
            failures.append("no scenario completed successfully")
        }

        finishSafely()
        attachNumericLog()
        XCTAssertTrue(
            failures.isEmpty,
            "Feed stress failures (seed=\(seed)):\n\(failures.joined(separator: "\n"))")
    }

    private func run(_ scenario: FeedStressScenario) throws {
        postFeedStress("com.opencapture.opc.feed-stress.begin.\(scenario.rawValue)")
        switch scenario {
        case .settingsOpenClose: try settingsOpenClose()
        case .assistToggles: try assistToggles()
        case .rotation: try rotation()
        case .cameraSettingChanges: try cameraSettingChanges()
        case .boundedJoystick: try boundedJoystick()
        case .lifecycleInterrupt: try lifecycleInterrupt()
        case .briefRecord: try briefRecord()
        case .injectFault: try injectFault()
        case .mediaReturn: try mediaReturn()
        case .steadyFeed: try steadyFeed()
        }
    }

    private func settingsOpenClose() throws {
        let rounds = 2 + Int(rng.next() % 2)
        for _ in 0..<rounds {
            let before = try requireSnapshot()
            try openLiveSettings()
            sleepStep(2.2)
            let covered = try requireSnapshot()
            try assertProgress(
                from: before, to: covered, source: true, decode: true, present: false,
                why: "Settings cover must keep source and decode moving")
            try closeSettings()
            _ = try waitProgress(
                from: covered, source: true, decode: true, present: true, timeout: 8,
                why: "picture after Settings return")
        }
    }

    private func assistToggles() throws {
        try expandAssists()
        let tools = ["PEAK", "FALSE", "WAVE", "LUT"]
        let picked = tools.shuffled(using: &rng).prefix(3)
        for id in picked {
            let button = app.buttons["monitor.assist.\(id)"]
            if !button.waitForExistence(timeout: 3) { continue }
            let before = try requireSnapshot()
            let wasOn = (button.value as? String) == "On"
            button.tap()
            sleepStep(1.2)
            _ = try waitProgress(
                from: before, source: true, decode: true, present: true, timeout: 6,
                why: "assist \(id) toggle")
            if (button.value as? String) == "On" && !wasOn {
                button.tap()
                sleepStep(0.8)
            }
        }
        collapseAssists()
        try enablePeakingForDecodeProof()
    }

    private func rotation() throws {
        let sequence: [UIDeviceOrientation] = [.landscapeLeft, .landscapeRight, .portrait]
        for orientation in sequence {
            let before = try requireSnapshot()
            XCUIDevice.shared.orientation = orientation
            sleepStep(1.4)
            _ = try waitProgress(
                from: before, source: true, decode: true, present: true, timeout: 8,
                why: "rotation \(orientation.rawValue)")
        }
    }

    private func cameraSettingChanges() throws {
        let iso = app.buttons["monitor.capture.iso"]
        XCTAssertTrue(iso.waitForExistence(timeout: 5), "ISO chip missing")
        isoOriginal = iso.value as? String ?? isoOriginal
        let before = try requireSnapshot()
        iso.tap()
        let panel = app.descendants(matching: .any)["monitor.capture.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "ISO panel missing")
        let drum = app.descendants(matching: .any)["Value"].firstMatch
        if drum.exists {
            drum.swipeLeft()
        }
        sleepStep(0.6)
        closeCapturePanel()
        sleepStep(4.2)
        _ = try waitProgress(
            from: before, source: true, decode: true, present: true, timeout: 8,
            why: "after ISO SET grace")
        restoreISOViaUI()
        sleepStep(2.0)
    }

    private func boundedJoystick() throws {
        let stick = app.descendants(matching: .any)["monitor.system.gimbal"].firstMatch
        guard stick.waitForExistence(timeout: 4), stick.isHittable else {
            throw FeedStressError.missingControl("gimbal stick")
        }
        let before = try requireSnapshot()
        let start = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let hold = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.40))
        start.press(forDuration: 0.7, thenDragTo: hold)
        sleepStep(0.4)
        _ = try waitProgress(
            from: before, source: true, decode: true, present: true, timeout: 8,
            why: "after bounded stick lift")
    }

    private func lifecycleInterrupt() throws {
        XCUIDevice.shared.press(.home)
        sleepStep(2.0)
        app.activate()
        // Frames submitted before Home/activation cannot prove foreground recovery.
        let returned = try requireSnapshot()
        _ = try waitProgress(
            from: returned, source: true, decode: true, present: true, timeout: 16,
            why: "lifecycle recover deadline")
    }

    /// Catalog-only return is useful even with an empty camera/card/cache.
    /// Playback is intentionally outside this catalog-return qualification.
    private func mediaReturn() throws {
        let media = app.buttons["monitor.system.media"]
        guard media.waitForExistence(timeout: 4), media.isHittable else {
            throw FeedStressError.missingControl("Open Media")
        }
        let gallery = app.descendants(matching: .any)["monitor.media.gallery"].firstMatch
        media.tap()
        guard gallery.waitForExistence(timeout: 8) else {
            throw FeedStressError.missingControl("Media catalog")
        }
        defer { dismissMediaIfVisible() }
        attachEvidence("media-catalog-entered")
        // Exercise playback entry/listing; an empty catalog remains valid.
        sleepStep(2)
        guard app.buttons["Back"].firstMatch.isHittable else {
            throw FeedStressError.missingControl("Media Back")
        }
        app.buttons["Back"].firstMatch.tap()
        let closed = NSPredicate(format: "exists == false")
        let gone = XCTNSPredicateExpectation(predicate: closed, object: gallery)
        guard XCTWaiter.wait(for: [gone], timeout: 6) == .completed,
            app.buttons["monitor.system.media"].isHittable
        else { throw FeedStressError.missingControl("live monitor after Media") }

        // Take the baseline AFTER leaving both playback and the catalog. A
        // cached redraw, or packets received while browsing, cannot pass this.
        // No assist/chrome mutation between catalog dismissal and proof.
        // Fresh identity enqueues themselves verify the established live path.
        let returned = try requireActiveSnapshot()
        let recovered = try waitIdentityProgress(from: returned, timeout: 16)
        var previous = recovered
        for _ in 0..<3 {
            let current = try nextActiveSnapshot(after: previous)
            guard identityProgressed(from: previous, to: current) else {
                throw FeedStressError.noProgress(
                    "Media returned only a transient picture: \(current)")
            }
            previous = current
        }
        attachEvidence("media-live-return", detail: "returned=\(returned) restored=\(previous)")
    }

    private func dismissMediaIfVisible() {
        let playerBack = app.buttons["Back to media"]
        if playerBack.exists, playerBack.isHittable { playerBack.tap() }
        let gallery = app.descendants(matching: .any)["monitor.media.gallery"].firstMatch
        let back = app.buttons["Back"].firstMatch
        if gallery.exists, back.exists, back.isHittable { back.tap() }
    }

    private func steadyFeed() throws {
        try assertIdentityProofMode()
        let started = ContinuousClock.now
        let end = started.advanced(by: .seconds(limitS))
        let first = try requireActiveSnapshot()
        var previous = first
        // No camera commands, chrome changes, orientation changes or recording
        // during this interval. Every window needs fresh source/decode/enqueue.
        while ContinuousClock.now < end {
            if thermalHalt() { throw FeedStressError.halted("thermal during uninterrupted feed") }
            let current = try nextActiveSnapshot(after: previous)
            guard identityProgressed(from: previous, to: current) else {
                throw FeedStressError.noProgress("Uninterrupted feed stalled: \(current)")
            }
            previous = current
        }
        attachEvidence(
            "steady-feed-complete",
            detail:
                "duration=\(started.duration(to: ContinuousClock.now)) start=\(first) end=\(previous)"
        )
    }

    private func waitIdentityProgress(from start: [String: String], timeout: TimeInterval)
        throws -> [String: String]
    {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if thermalHalt() { throw FeedStressError.halted("thermal during live return") }
            sleepStep(0.5)
            let current = try requireActiveSnapshot()
            if identityProgressed(from: start, to: current) { return current }
        }
        throw FeedStressError.noProgress("No fresh source/decode/identity enqueue after Media")
    }

    private func identityProgressed(from start: [String: String], to end: [String: String]) -> Bool
    {
        guard end["halt"] == "0", end["run"] == start["run"],
            let oldTime = Double(start["t"] ?? ""), let newTime = Double(end["t"] ?? ""),
            newTime > oldTime,
            int(end, "srcDelAU") > int(start, "srcDelAU"),
            int(end, "decOut") > int(start, "decOut"),
            int(end, "presEnqueue") > int(start, "presEnqueue")
        else { return false }
        return ["srcAgeMs", "decAgeMs", "enqueueAgeMs"].allSatisfy {
            guard let age = Int(end[$0] ?? "") else { return false }
            return (0..<2_000).contains(age)
        }
    }

    private func attachEvidence(_ name: String, detail: String = "") {
        let counters = XCTAttachment(string: "\(name) \(detail) snapshot=\(snapshot())")
        counters.name = name + "-counters"
        counters.lifetime = .keepAlways
        add(counters)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name + "-screen"
        image.lifetime = .keepAlways
        add(image)
    }

    /// PEAK supplies VT output. Disabling only the LUT leaves the identity
    /// pixel-buffer sink active; false color is an overlay, and this app clears
    /// omitted desqueeze at cold launch. Cached playback Metal cannot pass an
    /// identity-enqueue assertion. This qualifies this explicit output mode.
    private func establishIdentityProofMode() throws {
        try expandAssists()
        defer { collapseAssists() }
        let lut = app.buttons["monitor.assist.LUT"]
        guard lut.waitForExistence(timeout: 4), let value = lut.value as? String,
            value == "On" || value == "Off"
        else { throw FeedStressError.missingControl("LUT state for identity proof") }
        if identityProofOriginalLUT == nil { identityProofOriginalLUT = value == "On" }
        if value == "On" { lut.tap() }
        let off = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Off'"), object: lut)
        guard XCTWaiter.wait(for: [off], timeout: 3) == .completed else {
            throw FeedStressError.halted("Cannot establish identity output mode")
        }
    }

    private func assertIdentityProofMode() throws {
        // Only used before the uninterrupted interval starts. Media return
        // deliberately performs no assist/chrome action before picture proof.
        try expandAssists()
        defer { collapseAssists() }
        guard app.buttons["monitor.assist.LUT"].value as? String == "Off" else {
            throw FeedStressError.halted("Identity proof mode changed during scenario")
        }
    }

    private func restoreIdentityProofMode() {
        guard let wanted = identityProofOriginalLUT else { return }
        do {
            try expandAssists()
            defer { collapseAssists() }
            let lut = app.buttons["monitor.assist.LUT"]
            guard lut.waitForExistence(timeout: 4), let value = lut.value as? String,
                value == "On" || value == "Off"
            else { throw FeedStressError.missingControl("LUT restore") }
            if (value == "On") != wanted { lut.tap() }
            let restored = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", wanted ? "On" : "Off"), object: lut)
            guard XCTWaiter.wait(for: [restored], timeout: 3) == .completed else {
                throw FeedStressError.halted("LUT state did not restore")
            }
        } catch {
            let message = "restore identity proof mode: \(error)"
            failures.append(message)
            XCTFail(message)
        }
    }

    /// HUD publishes at 1 Hz. Poll for its next generation instead of assuming
    /// a one-second sleep crossed a tick. No interval may hide a two-second gap.
    private func nextActiveSnapshot(after previous: [String: String]) throws -> [String: String] {
        guard let oldTime = Double(previous["t"] ?? "") else {
            throw FeedStressError.noSnapshot
        }
        let expires = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < expires {
            sleepStep(0.1)
            let current = snapshot()
            if current.isEmpty { continue }
            guard current["halt"] == "0", current["run"] == previous["run"] else {
                throw FeedStressError.halted(
                    "Recorder changed/stopped during qualification: \(current)")
            }
            guard ContinuousClock.now < expires else { break }
            if let time = Double(current["t"] ?? ""), time > oldTime { return current }
        }
        throw FeedStressError.noProgress(
            "Recorder did not advance within the continuous two-second gap limit")
    }

    private func requireActiveSnapshot() throws -> [String: String] {
        let current = try requireSnapshot()
        guard current["halt"] == "0", current["run"] != nil else {
            throw FeedStressError.halted("Recorder stopped during qualification: \(current)")
        }
        return current
    }

    private func briefRecord() throws {
        let record = app.buttons["monitor.system.record"]
        guard record.waitForExistence(timeout: 4) else {
            throw FeedStressError.missingControl("record lamp")
        }
        let before = try requireSnapshot()
        tapRecord(start: true)
        sleepStep(3.0)
        let rolling = try requireSnapshot()
        XCTAssertEqual(rolling["rec"], "1", "brief recording did not start")
        try assertProgress(
            from: before, to: rolling, source: true, decode: true, present: true,
            why: "progress while briefly recording")
        tapRecord(start: false)
        sleepStep(2.0)
        let after = try requireSnapshot()
        XCTAssertNotEqual(after["rec"], "1", "recording must stop; never delete media")
    }

    private func injectFault() throws {
        // Every arm needs a new continuous healthy window, including after a
        // previous fault or lifecycle scenario. Elapsed run time is not health.
        try waitForHealthyBaseline(minimum: 30)
        let before = try requireSnapshot()
        postFeedStress("com.opencapture.opc.feed-stress.arm-inject")
        sleepStep(3.5)
        postFeedStress("com.opencapture.opc.feed-stress.disarm-inject")
        let afterFault = try requireSnapshot()
        let injectedBefore =
            (Int(before["injDrop"] ?? "0") ?? 0) + (Int(before["injSil"] ?? "0") ?? 0)
        let injectedAfter =
            (Int(afterFault["injDrop"] ?? "0") ?? 0) + (Int(afterFault["injSil"] ?? "0") ?? 0)
        XCTAssertGreaterThan(injectedAfter, injectedBefore, "Fault must actually be injected")
        _ = try waitProgress(
            from: afterFault, source: true, decode: true, present: true, timeout: 16,
            why: "recover after bounded inject")
    }

    private func waitForLiveMonitor() throws {
        let liveDeadline = Date().addingTimeInterval(60)
        while Date() < liveDeadline {
            if isLiveMonitorVisible {
                let snap = waitSnapshot(timeout: 15)
                XCTAssertFalse(
                    snap.isEmpty,
                    "feed.stress.snapshot missing — wire FeedStressAutomation.installIfRequested()")
                return
            }
            let snap = snapshot()
            let reconnect = snap["reconnect"] ?? ""
            if reconnect == "none" {
                XCTFail("No saved Pocket 4 Pro (model id 0x0022) to reconnect after cold launch")
                throw FeedStressError.noLiveMonitor
            }
            if reconnect == "ambiguous" {
                XCTFail("Multiple saved Pocket 4 Pro cameras; reconnect is ambiguous")
                throw FeedStressError.noLiveMonitor
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
            sleepStep(1.0)
        }
        XCTFail("No live monitor within 60s after cold-launch Pocket 4 Pro reconnect")
        throw FeedStressError.noLiveMonitor
    }

    private var isLiveMonitorVisible: Bool {
        app.buttons["monitor.system.record"].exists
            || app.buttons["monitor.system.settings"].exists
            || app.buttons["Open Operator Setup"].exists
    }

    private static func handleAuthorizedSystemAlert(_ alert: XCUIElement) -> Bool {
        let text =
            ([alert.label]
            + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            .lowercased()
        let relevant =
            text.contains("bluetooth") || text.contains("local network")
            || text.contains("local-network") || text.contains("wi-fi")
            || text.contains("wifi") || text.contains("wlan")
            || text.contains("openpocket") || text.contains("osmo")
            || text.contains("pocket") || text.contains("join")
        guard relevant else { return false }
        for title in ["Join", "Allow", "OK"] {
            let button = alert.buttons[title]
            if button.exists {
                button.tap()
                return true
            }
        }
        return false
    }

    private func enablePeakingForDecodeProof() throws {
        try expandAssists()
        let peak = app.buttons["monitor.assist.PEAK"]
        if peak.waitForExistence(timeout: 4), (peak.value as? String) != "On" {
            peak.tap()
            sleepStep(0.8)
        }
        collapseAssists()
    }

    private func waitForHealthyBaseline(minimum: TimeInterval) throws {
        var healthySince = Date()
        let expires = Date().addingTimeInterval(max(60, minimum * 3))
        var last = try requireSnapshot()
        while Date() < expires {
            if thermalHalt() { throw FeedStressError.halted("thermal during baseline") }
            sleepStep(1.0)
            let now = try requireSnapshot()
            if !progressed(from: last, to: now, source: true, decode: true, present: false) {
                healthySince = Date()
            }
            last = now
            if Date().timeIntervalSince(healthySince) >= minimum { return }
        }
        throw FeedStressError.halted("No continuous healthy source/decode baseline")
    }

    private func openLiveSettings() throws {
        let button =
            app.buttons["monitor.system.settings"].exists
            ? app.buttons["monitor.system.settings"]
            : app.buttons["Open Operator Setup"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "live settings control missing")
        button.tap()
        let tabs = app.descendants(matching: .any)["monitor.settings.tabs"].firstMatch
        let link = app.buttons["monitor.settings.tab.Link"]
        let heading = app.descendants(matching: .any)["monitor.page.heading"].firstMatch
        let back = app.buttons["Back to live"]
        let opened =
            tabs.waitForExistence(timeout: 8)
            || link.waitForExistence(timeout: 1)
            || heading.waitForExistence(timeout: 1)
            || back.waitForExistence(timeout: 1)
        XCTAssertTrue(
            opened,
            "Operator Setup did not open (do not use cameras.settings; wait for tabs/heading/back)")
        if link.exists { link.tap() }
    }

    private func closeSettings() throws {
        let back = app.buttons["Back to live"]
        if back.waitForExistence(timeout: 4) {
            back.tap()
        } else if app.buttons["Close"].firstMatch.exists {
            app.buttons["Close"].firstMatch.tap()
        }
        XCTAssertTrue(
            app.buttons["monitor.system.record"].waitForExistence(timeout: 6)
                || app.buttons["monitor.system.settings"].waitForExistence(timeout: 2),
            "Did not return to live")
    }

    private func expandAssists() throws {
        let expand = app.buttons["monitor.assists.expand"]
        if expand.waitForExistence(timeout: 3) {
            expand.tap()
            sleepStep(0.4)
        }
    }

    private func collapseAssists() {
        let collapse = app.buttons["monitor.assists.collapse"]
        if collapse.exists { collapse.tap() }
        let labeled = app.buttons["Collapse View Assist tools"]
        if labeled.exists { labeled.tap() }
    }

    private func closeCapturePanel() {
        let close = app.buttons["monitor.capture.close"]
        if close.exists {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        }
    }

    private func restoreISOViaUI() {
        guard !isoOriginal.isEmpty else { return }
        let iso = app.buttons["monitor.capture.iso"]
        guard iso.exists else { return }
        if (iso.value as? String) == isoOriginal { return }
        iso.tap()
        let drum = app.descendants(matching: .any)["Value"].firstMatch
        for _ in 0..<8 {
            if (iso.value as? String) == isoOriginal { break }
            if (drum.value as? String) == isoOriginal { break }
            drum.swipeRight()
            sleepStep(0.2)
        }
        closeCapturePanel()
    }

    private func tapRecord(start: Bool) {
        let record = app.buttons["monitor.system.record"]
        record.tap()
        let title = start ? "Start recording?" : "Stop recording?"
        if app.staticTexts[title].waitForExistence(timeout: 2) {
            app.buttons[start ? "Start" : "Stop"].firstMatch.tap()
        } else if app.buttons[start ? "Start" : "Stop"].firstMatch.exists {
            app.buttons[start ? "Start" : "Stop"].firstMatch.tap()
        }
    }

    private func dismissChrome() {
        closeCapturePanel()
        if app.buttons["Back to live"].exists { app.buttons["Back to live"].tap() }
        collapseAssists()
        let close = app.buttons["Close"].firstMatch
        if close.exists { close.tap() }
    }

    private func finishSafely() {
        guard !finished else { return }
        finished = true
        guard app != nil, app.state == .runningForeground || app.state == .runningBackground
        else { return }
        if app.state == .runningBackground { app.activate() }
        dismissChrome()
        if app.buttons["monitor.system.record"].exists {
            let snap = snapshot()
            if recordOptIn, snap["rec"] == "1" { tapRecord(start: false) }
        }
        restoreISOViaUI()
        postFeedStress("com.opencapture.opc.feed-stress.teardown")
        sleepStep(1.0)
        // Run after the existing runtime restore: its baseline is captured on
        // the HUD timer and may race the first UI setup toggle.
        restoreIdentityProofMode()
        XCUIDevice.shared.orientation = .portrait
    }

    private func waitProgress(
        from start: [String: String],
        source: Bool, decode: Bool, present: Bool,
        timeout: TimeInterval, why: String
    ) throws -> [String: String] {
        let end = Date().addingTimeInterval(timeout)
        var last = start
        while Date() < end {
            if thermalHalt() { throw FeedStressError.halted("thermal") }
            sleepStep(0.5)
            last = snapshot()
            if last.isEmpty { continue }
            if progressed(from: start, to: last, source: source, decode: decode, present: present) {
                return last
            }
        }
        throw FeedStressError.noProgress(why + " snap=\(last)")
    }

    private func assertProgress(
        from start: [String: String], to end: [String: String],
        source: Bool, decode: Bool, present: Bool, why: String
    ) throws {
        if !progressed(from: start, to: end, source: source, decode: decode, present: present) {
            throw FeedStressError.noProgress(why + " start=\(start) end=\(end)")
        }
    }

    private func progressed(
        from start: [String: String], to end: [String: String],
        source: Bool, decode: Bool, present: Bool
    ) -> Bool {
        if source && !sourceMoved(from: start, to: end) { return false }
        if decode && !decodeMoved(from: start, to: end) { return false }
        if present && !presentMoved(from: start, to: end) { return false }
        return true
    }

    private func sourceMoved(from start: [String: String], to end: [String: String]) -> Bool {
        if int(end, "srcDelAU") > int(start, "srcDelAU") { return true }
        if int(end, "srcDelP") > int(start, "srcDelP") { return true }
        if int(end, "srcObsAU") > int(start, "srcObsAU") { return true }
        if int(end, "srcObsP") > int(start, "srcObsP") { return true }
        return false
    }

    private func decodeMoved(from start: [String: String], to end: [String: String]) -> Bool {
        int(end, "decOut") > int(start, "decOut")
    }

    private func presentMoved(from start: [String: String], to end: [String: String]) -> Bool {
        if int(end, "presMetal") > int(start, "presMetal") { return true }
        if int(end, "presEnqueue") > int(start, "presEnqueue") { return true }
        if int(end, "pres") > int(start, "pres") { return true }
        return false
    }

    private func requireSnapshot() throws -> [String: String] {
        let snap = waitSnapshot(timeout: 5)
        if snap.isEmpty {
            throw FeedStressError.noSnapshot
        }
        return snap
    }

    private func waitSnapshot(timeout: TimeInterval) -> [String: String] {
        let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
        guard probe.waitForExistence(timeout: timeout) else { return [:] }
        return parse(probe.value as? String ?? "")
    }

    private func snapshot() -> [String: String] {
        let probe = app.descendants(matching: .any)["feed.stress.snapshot"].firstMatch
        guard probe.exists else { return [:] }
        return parse(probe.value as? String ?? "")
    }

    private func parse(_ line: String) -> [String: String] {
        var out: [String: String] = [:]
        for token in line.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                out[String(parts[0])] = String(parts[1])
            }
        }
        return out
    }

    private func int(_ snap: [String: String], _ key: String) -> Int {
        Int(snap[key] ?? "") ?? 0
    }

    private func captureValue(_ id: String) -> String {
        app.buttons[id].value as? String ?? ""
    }

    private func thermalHalt() -> Bool {
        let halt = snapshot()["halt"] ?? "0"
        return halt == "thermal"
    }

    private func record(_ scenario: FeedStressScenario, _ result: String, extra: String = "") {
        if result == "pass" {
            postFeedStress("com.opencapture.opc.feed-stress.pass.\(scenario.rawValue)")
        } else if result == "fail" {
            postFeedStress("com.opencapture.opc.feed-stress.fail.\(scenario.rawValue)")
        }
        let snap = snapshot()
        let body =
            "scenario=\(scenario.rawValue) result=\(result) extra=\(extra) "
            + "srcDelAU=\(snap["srcDelAU"] ?? "?") decOut=\(snap["decOut"] ?? "?") "
            + "pres=\(snap["pres"] ?? "?") presEnqueue=\(snap["presEnqueue"] ?? "?") "
            + "presMetal=\(snap["presMetal"] ?? "?") t=\(snap["t"] ?? "?") hook=\(snap["hook"] ?? "?")"
        let attachment = XCTAttachment(string: body)
        attachment.name = "feed-stress-\(scenario.rawValue)-\(result)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachNumericLog() {
        let snap = snapshot()
        let attachment = XCTAttachment(string: "seed=\(seed) final \(snap)")
        attachment.name = "feed-stress-final"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func sleepStep(_ seconds: TimeInterval) {
        let slice = min(max(seconds, 0.05), 5)
        RunLoop.current.run(until: Date().addingTimeInterval(slice))
        if seconds > 5 {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds - slice))
        }
    }
}

private func postFeedStress(_ name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name as CFString),
        nil,
        nil,
        true)
}

private enum FeedStressScenario: String {
    case settingsOpenClose
    case assistToggles
    case rotation
    case cameraSettingChanges
    case boundedJoystick
    case lifecycleInterrupt
    case briefRecord
    case injectFault
    case mediaReturn
    case steadyFeed

    // Keep the historical default list/order and seed behavior unchanged.
    static var selectable: [FeedStressScenario] {
        core + [.mediaReturn, .steadyFeed]
    }

    static let core: [FeedStressScenario] = [
        .settingsOpenClose, .assistToggles, .rotation, .cameraSettingChanges,
        .boundedJoystick, .lifecycleInterrupt,
    ]
}

private enum FeedStressError: Error, CustomStringConvertible {
    case noSnapshot
    case noLiveMonitor
    case missingControl(String)
    case halted(String)
    case noProgress(String)
    var description: String {
        switch self {
        case .noSnapshot:
            return "feed.stress.snapshot missing (installIfRequested / Debug + OPV_FEED_STRESS)"
        case .noLiveMonitor:
            return "no live monitor after cold-launch Pocket 4 Pro reconnect"
        case .missingControl(let name):
            return "missing control: \(name)"
        case .halted(let why):
            return "halted: \(why)"
        case .noProgress(let why):
            return "no source/decode/present counter progress: \(why)"
        }
    }
}

private struct FeedStressSeed: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
