import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct FeedIncidentStoreTests {
    @Test func nextLaunchMarksOpenIncidentInterruptedNotCrash() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-open" })
        _ = recorder.beginSession(Fixture.context())
        let job = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        let store = FeedIncidentStore(directory: dir)
        try store.persist(try #require(job), now: Date(timeIntervalSince1970: 1_000_004))
        let relaunch = FeedIncidentStore(directory: dir)
        let marked = try relaunch.markInterrupted(now: Date(timeIntervalSince1970: 1_000_010))
        #expect(marked == ["inc-open"])
        let loaded = try #require(relaunch.loadAll().first)
        #expect(loaded.header.outcome == .interrupted)
        #expect(loaded.header.processInterrupted)
        let text = FeedIncidentExport.text(from: [loaded], product: "OpenPocketCine")
        #expect(text.contains("interrupted"))
        #expect(!text.lowercased().contains("crash"))
        #expect(!text.contains("control-live.log"))
    }

    @Test func retentionEnforcesCountAndTTL() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        let limits = FeedIncidentLimits(
            maxBundles: 2, maxBundleBytes: 32_768, maxSpoolBytes: 1_048_576, ttl: 60)
        let store = FeedIncidentStore(directory: dir, limits: limits)
        let now = Date(timeIntervalSince1970: 2_000_000)
        for index in 1...3 {
            var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-\(index)" })
            _ = recorder.beginSession(Fixture.context(sessionID: "s-\(index)"))
            let job = recorder.recordSnapshot(
                Fixture.stall(
                    now: Double(index),
                    outputAge: 3,
                    wall: now.addingTimeInterval(Double(index))))
            try store.persist(try #require(job), now: now)
        }
        let kept = store.loadAll().map(\.header.incidentID)
        #expect(kept.count == 2)
        #expect(!kept.contains("inc-1"))
        #expect(kept.contains("inc-3"))

        let expiredDir = try Scratch.directory()
        defer { Scratch.remove(expiredDir) }
        let ttlStore = FeedIncidentStore(
            directory: expiredDir,
            limits: FeedIncidentLimits(maxBundles: 20, ttl: 10))
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-old" })
        _ = recorder.beginSession(Fixture.context())
        let old = recorder.recordSnapshot(
            Fixture.stall(
                now: 4, outputAge: 3, wall: now.addingTimeInterval(-30)))
        try ttlStore.persist(try #require(old), now: now)
        try ttlStore.applyRetention(now: now)
        #expect(ttlStore.loadAll().isEmpty)
    }

    @Test func corruptSpoolFileIsSkipped() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-good" })
        _ = recorder.beginSession(Fixture.context())
        let job = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        let store = FeedIncidentStore(directory: dir)
        try store.persist(try #require(job))
        let garbage = dir.appendingPathComponent("incident-deadbeef.json")
        try Data("not-json".utf8).write(to: garbage)
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.header.incidentID == "inc-good")
    }

    @Test func exportIsJournalIndependentAndRedactsSecrets() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-priv" })
        _ = recorder.beginSession(Fixture.context())
        recorder.recordBreadcrumb(
            FeedIncidentBreadcrumb(
                monotonicAt: 3,
                kind: .cameraCommand,
                detail: "password=hunter2 tester@example.com"))
        let job = recorder.recordSnapshot(
            Fixture.stall(
                now: 4,
                outputAge: 3,
                errorClass: "invalidSession",
                rebuildReason: "password=hunter2 payload=NAL serial=ABC"))
        let store = FeedIncidentStore(directory: dir)
        try store.persist(try #require(job))
        let extras = store.exportExtras()
        #expect(extras.contains { $0.name == "incidents.txt" })
        let listing = extras.first { $0.name == "incidents.txt" }?.body ?? ""
        #expect(listing.hasPrefix("OpenPocketCine feed incidents (typed snapshots, no journal)\n"))
        #expect(extras.contains { $0.name == "incident-inc-priv.json" })
        let joined = extras.map(\.body).joined(separator: "\n")
        #expect(!joined.contains("hunter2"))
        #expect(!joined.contains("tester@example.com"))
        #expect(!joined.contains("control-live.log"))
        let json = try #require(extras.first { $0.name.hasSuffix(".json") }?.body)
        let keys = JSONKeyWalker.keys(in: json)
        for forbidden in ["password", "payload", "footage", "serial", "ssid", "email", "nal"] {
            #expect(!keys.contains(forbidden), "allowlist leaked \(forbidden)")
        }
        let envelope = FeedIncidentExport.envelope(from: try #require(store.loadAll().first))
        #expect(envelope.eventName == "feed.incident")
        #expect(envelope.grouping.failingStage == "decodedOutput")
        #expect(envelope.kind == "freshInputStaleOutput")
        #expect(!envelope.grouping.errorClass.contains("hunter2"))
    }

    @Test func oversizedHeaderCannotEscapeDiskSizeCap() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        let store = FeedIncidentStore(directory: dir)
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-size-header" })
        _ = recorder.beginSession(Fixture.context())
        let first = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        var job = try #require(first)
        job.bundle.header.sourceRevision = String(repeating: "x", count: 300_000)
        #expect(throws: FeedIncidentStore.StorageError.self) { try store.persist(job) }
        #expect(store.loadAll().isEmpty)
    }

    @Test func bundleSizeCapRecordsEvictions() throws {
        let dir = try Scratch.directory()
        defer { Scratch.remove(dir) }
        let limits = FeedIncidentLimits(
            maxBundles: 5, maxBundleBytes: 4_096, maxSpoolBytes: 1_048_576, ttl: 604_800)
        let store = FeedIncidentStore(directory: dir, limits: limits)
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-size" })
        _ = recorder.beginSession(Fixture.context())
        var job: FeedIncidentPersistenceJob?
        for tick in 0..<80 {
            job =
                recorder.recordSnapshot(
                    Fixture.stall(now: Double(tick) + 4, outputAge: Double(tick) + 2)) ?? job
        }
        try store.persist(try #require(job))
        let url = dir.appendingPathComponent("incident-inc-size.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs[.size] as? NSNumber)?.intValue ?? Int.max
        #expect(bytes <= 4_096)
        #expect((store.loadAll().first?.header.evictions ?? 0) > 0)
    }
}

private enum Fixture {
    static func context(
        sessionID: String = "session-1",
        testSource: FeedIncidentTestSource = .unknown,
        buildIdentity: String = "unknown"
    ) -> FeedIncidentSessionContext {
        FeedIncidentSessionContext(
            sessionID: sessionID,
            appVersion: "0.1.0",
            appBuild: "107",
            sourceRevision: "afbdba3",
            osName: "iOS",
            osVersion: "27.0",
            hardwareClass: "iPhone17,2",
            cameraFamily: "pocket",
            cameraFirmware: "1.2.3",
            testSource: testSource,
            buildIdentity: buildIdentity)
    }

    static func snap(
        now: TimeInterval,
        packetHz: Double = 25,
        auHz: Double = 25,
        submitHz: Double = 25,
        acceptHz: Double = 25,
        outputHz: Double = 25,
        presentHz: Double = 25,
        packetAge: TimeInterval? = 0.04,
        auAge: TimeInterval? = 0.04,
        acceptAge: TimeInterval? = 0.04,
        outputAge: TimeInterval? = 0.04,
        presentAge: TimeInterval? = 0.04,
        live: Bool = true,
        connected: Bool = true,
        foreground: Bool = true,
        scene: Bool = true,
        settingsCovered: Bool = false,
        playback: Bool = false,
        errorClass: String? = nil,
        errorCount: Int = 0,
        decoderFailed: Bool = false,
        errorAge: TimeInterval? = nil,
        rebuildReason: String? = nil,
        generation: Int = 1,
        outputObservable: Bool = true,
        presentationExpected: Bool = true,
        wall: Date? = nil
    ) -> FeedIncidentSnapshot {
        FeedIncidentSnapshot(
            monotonicNow: now,
            wallClock: wall ?? Date(),
            rates: FeedIncidentRates(
                packetHz: packetHz,
                accessUnitHz: auHz,
                decodeSubmitHz: submitHz,
                decodeAcceptHz: acceptHz,
                decodedOutputHz: outputHz,
                presentHz: presentHz,
                ackHz: 40),
            ages: FeedIncidentAges(
                packetAge: packetAge,
                accessUnitAge: auAge,
                decodeAcceptAge: acceptAge,
                decodedOutputAge: outputAge,
                presentAge: presentAge),
            decoder: FeedIncidentDecoder(
                generation: generation,
                errorClass: errorClass,
                errorCount: errorCount,
                decoderFailed: decoderFailed,
                errorAge: errorAge,
                rebuildReason: rebuildReason),
            lifecycle: FeedIncidentLifecycle(
                foreground: foreground,
                settingsCovered: settingsCovered,
                playbackActive: playback,
                connected: connected,
                liveEstablished: live,
                sceneActive: scene,
                outputObservable: outputObservable,
                presentationExpected: presentationExpected))
    }

    static func stall(
        now: TimeInterval,
        outputAge: TimeInterval,
        settingsCovered: Bool = false,
        connected: Bool = true,
        playback: Bool = false,
        foreground: Bool = true,
        errorClass: String? = nil,
        errorCount: Int = 0,
        decoderFailed: Bool = false,
        rebuildReason: String? = nil,
        generation: Int = 1,
        wall: Date? = nil
    ) -> FeedIncidentSnapshot {
        snap(
            now: now,
            outputHz: 0,
            presentHz: 0,
            outputAge: outputAge,
            presentAge: outputAge,
            connected: connected,
            foreground: foreground,
            settingsCovered: settingsCovered,
            playback: playback,
            errorClass: errorClass,
            errorCount: errorCount,
            decoderFailed: decoderFailed,
            rebuildReason: rebuildReason,
            generation: generation,
            wall: wall)
    }

    static func healthy(now: TimeInterval, live: Bool = true) -> FeedIncidentSnapshot {
        snap(now: now, live: live)
    }
}

private enum Scratch {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-incident-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum JSONKeyWalker {
    static func keys(in json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        var found: Set<String> = []
        walk(object, into: &found)
        return found
    }

    private static func walk(_ value: Any, into found: inout Set<String>) {
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                found.insert(key)
                walk(child, into: &found)
            }
        } else if let array = value as? [Any] {
            for child in array { walk(child, into: &found) }
        }
    }
}
