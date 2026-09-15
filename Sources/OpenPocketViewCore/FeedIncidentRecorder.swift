import Foundation

/// Bounded in-memory recorder for established-feed stalls.
///
/// Callers supply one-second snapshots. Persistence is a returned job; the
/// recorder never writes files or logs. One open incident covers a continuous
/// outage. Settings coverage is context, not suppression.
public struct FeedIncidentRecorder: Sendable {
    public static let preludeSeconds = FeedIncidentBounds.preludeSeconds
    public static let aftermathSeconds = FeedIncidentBounds.aftermathSeconds

    private let makeIncidentID: @Sendable () -> String
    private var session: FeedIncidentSessionContext?
    private var ring: [FeedIncidentSnapshot] = []
    private var breadcrumbs: [FeedIncidentBreadcrumb] = []
    private var repairs: [FeedRepairRecord] = []
    private var open: OpenIncident?
    private var lastSampleAt: TimeInterval?
    private var healthyExposure: TimeInterval = 0
    private var startedIncidentCount = 0

    public init(makeIncidentID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.makeIncidentID = makeIncidentID
    }

    public var hasSession: Bool { session != nil }
    public var openHeader: FeedIncidentHeader? { open?.header }
    public var isCollectingAftermath: Bool { open?.aftermathEndsAt != nil }
    public var healthyExposureSeconds: TimeInterval { healthyExposure }
    public var incidentCount: Int { startedIncidentCount }

    public mutating func beginSession(_ context: FeedIncidentSessionContext)
        -> FeedIncidentPersistenceJob?
    {
        let leftover = finalizeOpen(outcome: .suppressed, now: ring.last?.monotonicNow ?? 0)
        session = context
        ring.removeAll(keepingCapacity: true)
        breadcrumbs.removeAll(keepingCapacity: true)
        repairs.removeAll(keepingCapacity: true)
        lastSampleAt = nil
        healthyExposure = 0
        startedIncidentCount = 0
        return leftover
    }

    public mutating func endSession(now: TimeInterval) -> FeedIncidentPersistenceJob? {
        let job = finalizeOpen(outcome: .suppressed, now: now)
        session = nil
        ring.removeAll(keepingCapacity: true)
        breadcrumbs.removeAll(keepingCapacity: true)
        repairs.removeAll(keepingCapacity: true)
        lastSampleAt = nil
        return job
    }

    public mutating func noteDecoderGeneration(_ generation: Int) {
        session?.decoderGeneration = max(0, generation)
        open?.header.decoderGeneration = max(0, generation)
    }

    public mutating func noteSocketGeneration(_ generation: Int) {
        session?.socketGeneration = max(0, generation)
        open?.header.socketGeneration = max(0, generation)
    }

    /// Upgrade session origin for later incidents. An open incident keeps the
    /// origin captured when it started.
    public mutating func noteTestSource(_ source: FeedIncidentTestSource) {
        guard source.rank > (session?.testSource.rank ?? -1) else { return }
        session?.testSource = source
    }

    public mutating func noteExhausted(now: TimeInterval) -> FeedIncidentPersistenceJob? {
        guard var open, open.header.outcome == .open || open.header.outcome == .exhausted else {
            return nil
        }
        open.header.outcome = .exhausted
        open.header.endedAtMonotonic = now
        self.open = open
        return FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .outcome)
    }

    public mutating func recordBreadcrumb(_ breadcrumb: FeedIncidentBreadcrumb) {
        breadcrumbs.append(breadcrumb)
        trim(&breadcrumbs, keep: FeedIncidentBounds.breadcrumbRing)
        open?.breadcrumbs.append(breadcrumb)
        if let count = open?.breadcrumbs.count, count > FeedIncidentBounds.breadcrumbRing {
            open?.header.evictions += 1
            open?.breadcrumbs.removeFirst()
        }
    }

    public mutating func recordRepair(_ repair: FeedRepairRecord) -> FeedIncidentPersistenceJob? {
        repairs.append(repair)
        trim(&repairs, keep: FeedIncidentBounds.repairRing)
        guard open != nil else { return nil }
        open?.repairs.append(repair)
        if let count = open?.repairs.count, count > FeedIncidentBounds.repairRing {
            open?.header.evictions += 1
            open?.repairs.removeFirst()
        }
        guard let open else { return nil }
        return FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .repair)
    }

    /// BLE / path loss before ages can be fabricated. Does not treat a repair request as the outage.
    public mutating func noteUnexpectedDisconnect(now: TimeInterval) -> FeedIncidentPersistenceJob?
    {
        guard session != nil else { return nil }
        recordBreadcrumb(
            FeedIncidentBreadcrumb(
                monotonicAt: now, kind: .pathChange, detail: "unexpectedDisconnect"))
        if open != nil {
            return checkpointIfNeeded(ring.last ?? FeedIncidentSnapshot(monotonicNow: now))
        }
        let snapshot =
            ring.last
            ?? FeedIncidentSnapshot(
                monotonicNow: now,
                lifecycle: FeedIncidentLifecycle(connected: true, liveEstablished: true))
        return startIncident(snapshot, kind: .unexpectedDisconnect, stage: .packet)
    }

    /// Ingest a 1 Hz snapshot. Returns a persistence job on start, repair, checkpoint, or outcome.
    public mutating func recordSnapshot(_ snapshot: FeedIncidentSnapshot)
        -> FeedIncidentPersistenceJob?
    {
        appendRing(snapshot)
        noteExposure(snapshot)
        guard session != nil else { return nil }

        let verdict = FeedIncidentClassifier.classify(snapshot)
        let recovered = FeedIncidentClassifier.isRecovered(snapshot)
        if open != nil {
            if recovered {
                if open?.aftermathEndsAt != nil {
                    return collectAftermath(snapshot)
                }
                return beginAftermath(now: snapshot.monotonicNow, snapshot: snapshot)
            }
            if verdict.suppression == .disconnected || verdict.suppression == .playback {
                return finalizeOpen(outcome: .suppressed, now: snapshot.monotonicNow)
            }
            if verdict.suppression == .background {
                return checkpointIfNeeded(snapshot)
            }
            return continueOpen(snapshot, verdict: verdict)
        }

        guard verdict.shouldRecord, let kind = verdict.kind, let stage = verdict.failingStage else {
            return nil
        }
        return startIncident(snapshot, kind: kind, stage: stage)
    }

    public func exportOpen() -> FeedIncidentBundle? { open?.bundle() }

    private mutating func startIncident(
        _ snapshot: FeedIncidentSnapshot,
        kind: FeedIncidentKind,
        stage: FeedIncidentFailingStage
    ) -> FeedIncidentPersistenceJob? {
        guard let session else { return nil }
        let gap = FeedIncidentPrivacy.gapSeconds(for: snapshot, stage: stage)
        let header = FeedIncidentHeader(
            schemaVersion: FeedIncidentSchema.version,
            incidentID: FeedIncidentPrivacy.token(makeIncidentID()),
            sessionID: session.sessionID,
            kind: kind,
            failingStage: stage,
            errorClass: snapshot.decoder.errorClass,
            outcome: .open,
            startedAtWallClock: snapshot.wallClock,
            startedAtMonotonic: snapshot.monotonicNow,
            endedAtMonotonic: nil,
            firstFailureAt: snapshot.monotonicNow,
            worstGapSeconds: gap,
            appVersion: session.appVersion,
            appBuild: session.appBuild,
            sourceRevision: session.sourceRevision,
            osName: session.osName,
            osVersion: session.osVersion,
            hardwareClass: session.hardwareClass,
            cameraFamily: session.cameraFamily,
            cameraFirmware: session.cameraFirmware,
            decoderGeneration: snapshot.decoder.generation > 0
                ? snapshot.decoder.generation : session.decoderGeneration,
            socketGeneration: session.socketGeneration,
            evictions: 0,
            assistState: snapshot.lifecycle.assistState,
            healthyExposureSeconds: healthyExposure,
            testSource: session.testSource,
            buildIdentity: session.buildIdentity)
        var incident = OpenIncident(header: header, prelude: ring)
        incident.breadcrumbs = breadcrumbs
        incident.repairs = repairs
        incident.noteError(snapshot.decoder.errorClass)
        self.open = incident
        startedIncidentCount += 1
        return FeedIncidentPersistenceJob(bundle: incident.bundle(), reason: .started)
    }

    private mutating func continueOpen(
        _ snapshot: FeedIncidentSnapshot,
        verdict: FeedIncidentVerdict
    ) -> FeedIncidentPersistenceJob? {
        guard var open else { return nil }
        if open.aftermathEndsAt != nil {
            open.aftermathEndsAt = nil
            open.aftermath.removeAll(keepingCapacity: true)
            open.header.outcome = .open
            open.header.endedAtMonotonic = nil
        }
        if let stage = verdict.failingStage {
            let gap = FeedIncidentPrivacy.gapSeconds(for: snapshot, stage: stage)
            if gap > open.header.worstGapSeconds {
                open.header.worstGapSeconds = gap
                open.header.failingStage = stage
            }
            if let kind = verdict.kind, open.header.errorClass == nil, kind == .decoderError {
                open.header.kind = kind
                open.header.errorClass = snapshot.decoder.errorClass
            }
        }
        open.appendDuring(snapshot)
        open.noteError(snapshot.decoder.errorClass)
        open.header.assistState = snapshot.lifecycle.assistState
        open.snapshotsUntilCheckpoint -= 1
        self.open = open
        if open.snapshotsUntilCheckpoint <= 0 {
            self.open?.snapshotsUntilCheckpoint = 5
            return FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .checkpoint)
        }
        return nil
    }

    private mutating func beginAftermath(
        now: TimeInterval, snapshot: FeedIncidentSnapshot?
    ) -> FeedIncidentPersistenceJob? {
        guard var open else { return nil }
        if open.aftermathEndsAt == nil {
            if open.header.outcome != .exhausted {
                open.header.outcome = .recovered
            }
            open.header.endedAtMonotonic = now
            open.aftermathEndsAt = now + FeedIncidentBounds.aftermathSeconds
        }
        if let snapshot {
            open.appendAftermath(snapshot)
        }
        self.open = open
        return FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .outcome)
    }

    private mutating func collectAftermath(_ snapshot: FeedIncidentSnapshot)
        -> FeedIncidentPersistenceJob?
    {
        guard var open, let end = open.aftermathEndsAt else { return nil }
        open.appendAftermath(snapshot)
        if snapshot.monotonicNow >= end {
            let job = FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .outcome)
            self.open = nil
            return job
        }
        self.open = open
        return nil
    }

    private mutating func checkpointIfNeeded(_ snapshot: FeedIncidentSnapshot)
        -> FeedIncidentPersistenceJob?
    {
        guard var open else { return nil }
        open.appendDuring(snapshot)
        open.snapshotsUntilCheckpoint -= 1
        self.open = open
        if open.snapshotsUntilCheckpoint <= 0 {
            self.open?.snapshotsUntilCheckpoint = 5
            return FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .checkpoint)
        }
        return nil
    }

    private mutating func finalizeOpen(outcome: FeedIncidentOutcome, now: TimeInterval)
        -> FeedIncidentPersistenceJob?
    {
        guard var open else { return nil }
        if open.header.outcome == .open {
            open.header.outcome = outcome
        }
        if open.header.endedAtMonotonic == nil { open.header.endedAtMonotonic = now }
        let job = FeedIncidentPersistenceJob(bundle: open.bundle(), reason: .outcome)
        self.open = nil
        return job
    }

    private mutating func appendRing(_ snapshot: FeedIncidentSnapshot) {
        if let last = ring.last, snapshot.monotonicNow + 0.000_1 < last.monotonicNow {
            return
        }
        if let lastIndex = ring.indices.last,
            snapshot.monotonicNow - ring[lastIndex].monotonicNow < 0.9
        {
            ring[lastIndex] = snapshot
        } else {
            ring.append(snapshot)
        }
        let cutoff = snapshot.monotonicNow - FeedIncidentBounds.preludeSeconds
        ring.removeAll { $0.monotonicNow < cutoff }
        if ring.count > FeedIncidentBounds.ringCount {
            ring = Array(ring.suffix(FeedIncidentBounds.ringCount))
        }
    }

    private mutating func noteExposure(_ snapshot: FeedIncidentSnapshot) {
        let now = snapshot.monotonicNow
        if let lastSampleAt, session != nil, FeedIncidentClassifier.isRecovered(snapshot) {
            let delta = min(1.5, max(0, now - lastSampleAt))
            healthyExposure += delta
        }
        lastSampleAt = now
    }

    private func trim<T>(_ items: inout [T], keep: Int) {
        if items.count > keep {
            items = Array(items.suffix(keep))
        }
    }
}

public struct FeedIncidentPersistenceJob: Equatable, Sendable {
    public var bundle: FeedIncidentBundle
    public var reason: Reason

    public enum Reason: String, Equatable, Sendable {
        case started
        case checkpoint
        case repair
        case outcome
    }
}

private struct OpenIncident {
    var header: FeedIncidentHeader
    var prelude: [FeedIncidentSnapshot]
    var during: [FeedIncidentSnapshot] = []
    var aftermath: [FeedIncidentSnapshot] = []
    var breadcrumbs: [FeedIncidentBreadcrumb] = []
    var repairs: [FeedRepairRecord] = []
    var aggregatedErrors: [String: Int] = [:]
    var aftermathEndsAt: TimeInterval?
    var snapshotsUntilCheckpoint = 5

    mutating func appendDuring(_ snapshot: FeedIncidentSnapshot) {
        during.append(snapshot)
        if during.count > FeedIncidentBounds.duringCount {
            header.evictions += during.count - FeedIncidentBounds.duringCount
            during = FeedIncidentSampling.downsample(during, keep: FeedIncidentBounds.duringCount)
        }
    }

    mutating func appendAftermath(_ snapshot: FeedIncidentSnapshot) {
        aftermath.append(snapshot)
        if aftermath.count > 30 {
            header.evictions += 1
            aftermath.removeFirst()
        }
    }

    mutating func noteError(_ errorClass: String?) {
        guard let errorClass, !errorClass.isEmpty else { return }
        aggregatedErrors[errorClass, default: 0] += 1
        if header.errorClass == nil {
            header.errorClass = errorClass
        }
        if aggregatedErrors.count > FeedIncidentBounds.errorClasses,
            let rare = aggregatedErrors.min(by: { $0.value < $1.value })?.key
        {
            aggregatedErrors.removeValue(forKey: rare)
            header.evictions += 1
        }
    }

    func bundle() -> FeedIncidentBundle {
        let errors = aggregatedErrors.keys.sorted().map {
            FeedIncidentErrorCount(errorClass: $0, count: aggregatedErrors[$0] ?? 0)
        }
        return FeedIncidentBundle(
            header: header,
            prelude: prelude,
            during: during,
            aftermath: aftermath,
            breadcrumbs: breadcrumbs,
            repairs: repairs,
            aggregatedErrors: errors)
    }
}

enum FeedIncidentSampling {
    static func downsample<T>(_ items: [T], keep: Int) -> [T] {
        guard keep > 0, !items.isEmpty else { return [] }
        if items.count <= keep { return items }
        if keep == 1 { return [items[items.count - 1]] }
        var out: [T] = []
        out.reserveCapacity(keep)
        for i in 0..<keep {
            let index = i * (items.count - 1) / (keep - 1)
            out.append(items[index])
        }
        return out
    }
}
