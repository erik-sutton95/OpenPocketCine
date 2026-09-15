import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct FeedIncidentRecorderTests {
    @Test func freshInputStaleOutputStartsIncident() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-fresh" })
        _ = recorder.beginSession(Fixture.context())
        for tick in 0..<8 {
            _ = recorder.recordSnapshot(Fixture.healthy(now: Double(tick)))
        }
        let job = recorder.recordSnapshot(Fixture.stall(now: 10, outputAge: 5))
        #expect(job?.reason == .started)
        #expect(job?.bundle.header.kind == .freshInputStaleOutput)
        #expect(job?.bundle.header.failingStage == .decodedOutput)
        #expect(job?.bundle.header.outcome == .open)
        #expect(job?.bundle.prelude.count ?? 0 >= 8)
        #expect(recorder.openHeader?.incidentID == "inc-fresh")
    }

    @Test func settingsCoverDoesNotSuppressEstablishedStall() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-settings" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.healthy(now: 1))
        let job = recorder.recordSnapshot(
            Fixture.stall(now: 4, outputAge: 3, settingsCovered: true))
        #expect(job?.reason == .started)
        #expect(job?.bundle.header.kind == .freshInputStaleOutput)
    }

    @Test func expectedAbsenceDoesNotStartIncident() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-none" })
        _ = recorder.beginSession(Fixture.context())
        #expect(recorder.recordSnapshot(Fixture.healthy(now: 1, live: false)) == nil)
        #expect(
            recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3, connected: false)) == nil)
        #expect(
            recorder.recordSnapshot(Fixture.stall(now: 8, outputAge: 3, playback: true)) == nil)
        #expect(
            recorder.recordSnapshot(Fixture.stall(now: 12, outputAge: 3, foreground: false))
                == nil)
        #expect(recorder.openHeader == nil)
    }

    @Test func continuingStallDedupsAndTracksWorstGap() {
        let ids = StubIDs(["inc-1", "inc-2"])
        var recorder = FeedIncidentRecorder(makeIncidentID: { ids.next() })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.healthy(now: 1))
        _ = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 2.5))
        for tick in 5..<16 {
            _ = recorder.recordSnapshot(
                Fixture.stall(now: Double(tick), outputAge: Double(tick) - 2))
        }
        #expect(recorder.openHeader?.incidentID == "inc-1")
        #expect(ids.remaining == ["inc-2"])
        #expect((recorder.openHeader?.worstGapSeconds ?? 0) >= 13)
        #expect(recorder.exportOpen()?.during.isEmpty == false)
    }

    @Test func recoveredOutputClosesAfterAftermath() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-rec" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.healthy(now: 1))
        _ = recorder.recordSnapshot(Fixture.stall(now: 5, outputAge: 3))
        let recovered = recorder.recordSnapshot(Fixture.healthy(now: 8))
        #expect(recovered?.reason == .outcome)
        #expect(recovered?.bundle.header.outcome == .recovered)
        #expect(recorder.isCollectingAftermath)
        #expect(recorder.openHeader?.incidentID == "inc-rec")
        var last: FeedIncidentPersistenceJob?
        for tick in 9...38 {
            last = recorder.recordSnapshot(Fixture.healthy(now: Double(tick)))
        }
        #expect(last?.reason == .outcome)
        #expect(last?.bundle.header.outcome == .recovered)
        #expect(last?.bundle.aftermath.isEmpty == false)
        #expect(recorder.openHeader == nil)
        #expect(!recorder.isCollectingAftermath)
    }

    @Test func stallDuringAftermathStaysSameIncident() {
        let ids = StubIDs(["inc-1", "inc-2"])
        var recorder = FeedIncidentRecorder(makeIncidentID: { ids.next() })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        _ = recorder.recordSnapshot(Fixture.healthy(now: 6))
        #expect(recorder.isCollectingAftermath)
        _ = recorder.recordSnapshot(Fixture.stall(now: 8, outputAge: 3))
        #expect(recorder.openHeader?.incidentID == "inc-1")
        #expect(recorder.openHeader?.outcome == .open)
        #expect(!recorder.isCollectingAftermath)
        #expect(ids.remaining == ["inc-2"])
    }

    @Test func decoderErrorClassIsRecordedAndAggregated() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-err" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(
            Fixture.stall(
                now: 4, outputAge: 3, errorClass: "invalidSession", decoderFailed: true))
        _ = recorder.recordSnapshot(
            Fixture.stall(
                now: 5, outputAge: 4, errorClass: "invalidSession", decoderFailed: true))
        let bundle = recorder.exportOpen()
        #expect(bundle?.header.kind == .decoderError)
        #expect(bundle?.header.errorClass == "invalidSession")
        #expect(bundle?.aggregatedErrors.first?.count == 2)
    }

    @Test func snapshotsBeforeBeginSessionDoNotOpenIncident() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-late" })
        #expect(recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3)) == nil)
        #expect(recorder.openHeader == nil)
        _ = recorder.beginSession(Fixture.context())
        let job = recorder.recordSnapshot(Fixture.stall(now: 6, outputAge: 5))
        #expect(job?.reason == .started)
        #expect(job?.bundle.header.incidentID == "inc-late")
    }

    @Test func packetSilenceDuringDecoderIncidentStaysOpen() {
        let ids = StubIDs(["inc-1", "inc-2"])
        var recorder = FeedIncidentRecorder(makeIncidentID: { ids.next() })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        let silent = Fixture.snap(
            now: 8,
            packetHz: 0,
            auHz: 0,
            submitHz: 0,
            acceptHz: 0,
            outputHz: 0,
            presentHz: 0,
            packetAge: 5,
            auAge: 5,
            outputAge: 7,
            presentAge: 7)
        _ = recorder.recordSnapshot(silent)
        #expect(recorder.openHeader?.incidentID == "inc-1")
        #expect(recorder.openHeader?.outcome == .open)
        #expect(ids.remaining == ["inc-2"])
        #expect(!FeedIncidentClassifier.isRecovered(silent))
    }

    @Test func generationChangeDoesNotRecover() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-gen" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3, generation: 1))
        recorder.noteDecoderGeneration(2)
        _ = recorder.recordSnapshot(Fixture.stall(now: 6, outputAge: 5, generation: 2))
        #expect(recorder.openHeader?.incidentID == "inc-gen")
        #expect(recorder.openHeader?.outcome == .open)
        #expect(recorder.openHeader?.decoderGeneration == 2)
    }

    @Test func recoveryRequiresFreshOutputAndPresentation() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-partial" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        let outputOnly = Fixture.snap(
            now: 8, outputHz: 25, presentHz: 0, outputAge: 0.04, presentAge: 6)
        _ = recorder.recordSnapshot(outputOnly)
        #expect(recorder.openHeader?.outcome == .open)
        #expect(!recorder.isCollectingAftermath)
        _ = recorder.recordSnapshot(Fixture.healthy(now: 10))
        #expect(recorder.openHeader?.outcome == .recovered)
    }

    @Test func compressedLayerUnknownOutputDoesNotFalseStall() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-layer" })
        _ = recorder.beginSession(Fixture.context())
        let compressed = Fixture.snap(
            now: 4,
            outputHz: 0,
            outputAge: 8,
            presentAge: 0.04,
            outputObservable: false)
        #expect(recorder.recordSnapshot(compressed) == nil)
        #expect(recorder.openHeader == nil)
    }

    @Test func cumulativeErrorCountIsNotCurrentFailure() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-olderr" })
        _ = recorder.beginSession(Fixture.context())
        let job = recorder.recordSnapshot(
            Fixture.stall(now: 4, outputAge: 3, errorCount: 4, decoderFailed: false))
        #expect(job?.bundle.header.kind == .freshInputStaleOutput)
    }

    @Test func unexpectedDisconnectStartsDistinctIncident() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-disc" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.healthy(now: 1))
        let job = recorder.noteUnexpectedDisconnect(now: 1.2)
        #expect(job?.bundle.header.kind == .unexpectedDisconnect)
        #expect(job?.reason == .started)
    }

    @Test func healthyExposureAccumulatesOnlyWhileRecovered() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-exp" })
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.healthy(now: 1))
        _ = recorder.recordSnapshot(Fixture.healthy(now: 2))
        _ = recorder.recordSnapshot(Fixture.healthy(now: 3))
        #expect(recorder.healthyExposureSeconds >= 1.9)
        _ = recorder.recordSnapshot(Fixture.stall(now: 6, outputAge: 3))
        let afterStall = recorder.healthyExposureSeconds
        _ = recorder.recordSnapshot(Fixture.stall(now: 8, outputAge: 5))
        #expect(recorder.healthyExposureSeconds == afterStall)
    }
}

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
        let text = FeedIncidentExport.text(from: [loaded])
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

    @Test func coveredUnobservableFeedCannotClaimRecoveryOrHealthyExposure() {
        var recorder = FeedIncidentRecorder()
        _ = recorder.beginSession(Fixture.context())
        for tick in 0..<10 {
            let snapshot = Fixture.snap(
                now: Double(tick), settingsCovered: true,
                outputObservable: false, presentationExpected: false)
            #expect(!FeedIncidentClassifier.isRecovered(snapshot))
            _ = recorder.recordSnapshot(snapshot)
        }
        #expect(recorder.healthyExposureSeconds == 0)
    }

    @Test func disconnectDuringAftermathPreservesObservedRecovery() throws {
        var recorder = FeedIncidentRecorder()
        _ = recorder.beginSession(Fixture.context())
        _ = recorder.recordSnapshot(Fixture.stall(now: 5, outputAge: 3))
        _ = recorder.recordSnapshot(Fixture.healthy(now: 8))
        let result = recorder.endSession(now: 9)
        let final = try #require(result)
        #expect(final.bundle.header.outcome == .recovered)
        #expect(final.bundle.header.endedAtMonotonic == 8)
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

@Suite struct FeedIncidentOriginTests {
    @Test func deriveUsesVerificationThenInjectionThenAutomation() {
        #expect(
            FeedIncidentTestSource.derive(
                verification: true, injectionActivated: true, automation: true) == .verification)
        #expect(
            FeedIncidentTestSource.derive(
                verification: false, injectionActivated: true, automation: true) == .faultInjection)
        #expect(
            FeedIncidentTestSource.derive(
                verification: false, injectionActivated: false, automation: true) == .automation)
        #expect(
            FeedIncidentTestSource.derive(
                verification: false, injectionActivated: false, automation: false) == .manual)
        #expect(FeedIncidentTestSource.parse(nil) == .unknown)
        #expect(FeedIncidentTestSource.parse("not-a-source") == .unknown)
        #expect(FeedIncidentTestSource.parse("faultInjection") == .faultInjection)
    }

    @Test func recorderCopiesSessionOriginAndDoesNotDowngrade() {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-origin" })
        _ = recorder.beginSession(
            Fixture.context(
                sessionID: "session-origin",
                testSource: .automation,
                buildIdentity: "ios-0123456789abcdef0123456789abcd"))
        let job = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        #expect(job?.bundle.header.resolvedTestSource == .automation)
        #expect(job?.bundle.header.resolvedBuildIdentity == "ios-0123456789abcdef0123456789abcd")
        recorder.noteTestSource(.manual)
        #expect(recorder.openHeader?.resolvedTestSource == .automation)
        recorder.noteTestSource(.faultInjection)
        #expect(recorder.openHeader?.resolvedTestSource == .automation)
        _ = recorder.recordSnapshot(Fixture.healthy(now: 8))
        _ = recorder.endSession(now: 40)
        _ = recorder.beginSession(
            Fixture.context(
                sessionID: "session-origin-2",
                testSource: .faultInjection,
                buildIdentity: "ios-0123456789abcdef0123456789abcd"))
        let next = recorder.recordSnapshot(Fixture.stall(now: 44, outputAge: 3))
        #expect(next?.bundle.header.resolvedTestSource == .faultInjection)
    }

    @Test func legacyJSONWithoutOriginDecodesUnknown() throws {
        var recorder = FeedIncidentRecorder(makeIncidentID: { "inc-legacy" })
        _ = recorder.beginSession(Fixture.context())
        let job = recorder.recordSnapshot(Fixture.stall(now: 4, outputAge: 3))
        let encoded = try FeedIncidentCoding.encoder().encode(try #require(job?.bundle))
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var header = try #require(json["header"] as? [String: Any])
        header.removeValue(forKey: "testSource")
        header.removeValue(forKey: "buildIdentity")
        json["header"] = header
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try FeedIncidentCoding.decoder().decode(
            FeedIncidentBundle.self, from: stripped)
        #expect(decoded.header.testSource == nil)
        #expect(decoded.header.buildIdentity == nil)
        #expect(decoded.header.resolvedTestSource == .unknown)
        #expect(decoded.header.resolvedBuildIdentity == "unknown")
    }

    @Test func nativeBreadcrumbDetailsKeepOnlyTypedTokens() {
        let scene = FeedIncidentNativeBreadcrumb.details(kind: .sceneActivity, detail: "inactive")
        #expect(scene == ["sceneState": "inactive"])
        let leaked = FeedIncidentNativeBreadcrumb.details(
            kind: .sceneActivity, detail: "password=hunter2")
        #expect(leaked.isEmpty)
        let assist = FeedIncidentNativeBreadcrumb.details(
            kind: .assistChange, detail: "replacement")
        #expect(assist == ["assistState": "replacement"])
        #expect(
            FeedIncidentNativeBreadcrumb.details(kind: .assistChange, detail: "private_project")
                .isEmpty)
        let repair = FeedIncidentNativeBreadcrumb.details(
            repair: FeedRepairRecord(
                monotonicAt: 1, action: "decoder", phase: .requested, reason: "outputSilence"))
        #expect(repair["repairPhase"] == "requested")
        #expect(repair["repairAction"] == "decoder")
        #expect(
            FeedIncidentNativeBreadcrumb.details(
                repair: FeedRepairRecord(
                    monotonicAt: 1, action: "Erik", phase: .requested))["repairAction"] == nil)
        #expect(
            FeedIncidentNativeBreadcrumb.sanitized([
                "sceneState": "active",
                "password": "secret",
                "free": "text with spaces",
            ]) == ["sceneState": "active"])
        #expect(FeedIncidentNativeBreadcrumb.sanitized(["sceneState": "Erik"]).isEmpty)
        #expect(FeedIncidentNativeBreadcrumb.sanitized(["sceneState": "private_project"]).isEmpty)
        #expect(FeedIncidentNativeBreadcrumb.sanitized(["assistState": "Erik"]).isEmpty)
        #expect(
            FeedIncidentNativeBreadcrumb.details(kind: .cameraCommand, detail: "format").isEmpty)
        #expect(FeedIncidentNativeBreadcrumb.isAllowedMessage("repair"))
        #expect(!FeedIncidentNativeBreadcrumb.isAllowedMessage("arbitrary operator text"))
    }
}

@Suite struct FeedIncidentNamingTests {
    @Test func metricKitNamesAreUniquePerDelivery() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = FeedIncidentFileNaming.metricKit(
            kind: "diagnostic", deliveredAt: date, deliveryID: UUID(), index: 0)
        let second = FeedIncidentFileNaming.metricKit(
            kind: "diagnostic", deliveredAt: date, deliveryID: UUID(), index: 0)
        #expect(first != second)
        #expect(first != "metrickit-diagnostic-0.json")
        #expect(first.hasPrefix("metrickit-diagnostic-"))
        #expect(first.contains("-0.json"))
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

private final class StubIDs: @unchecked Sendable {
    private var values: [String]
    var remaining: [String] { values }
    init(_ values: [String]) { self.values = values }
    func next() -> String {
        values.isEmpty ? "overflow" : values.removeFirst()
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
