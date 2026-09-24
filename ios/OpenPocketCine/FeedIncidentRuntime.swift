import Foundation
import OpenPocketViewCore

/// Shell owner for feed-incident persistence. Core records in memory; this type
/// writes on a utility queue. Never call from a receive, decode, display, or
/// fatal-signal handler except via the ingest methods, which return immediately.
///
/// Coordinator hooks (camera session / decoder / chrome — not wired here):
/// - `install()` once at diagnostic boot (marks leftover open incidents interrupted)
/// - `beginSession(_:)` when a live session identity is known
/// - `endSession(now:)` on explicit disconnect
/// - `ingestSnapshot(_:)` at 1 Hz with allowlisted stage counters
/// - `recordBreadcrumb(_:)` Settings enter/exit, assist, scene, surface, decoder, path, command category
/// - `recordRepair(_:)` requested / blocked / locallySent / peerResponse / pictureRestored
/// - `noteDecoderGeneration(_:)` / `noteSocketGeneration(_:)`
/// - `noteExhausted(now:)` when the repair owner spends its budget
/// - `noteUnexpectedDisconnect(now:)` for BLE/path loss before ages exist
/// - `reportExtras()` from Share Diagnostics (journal-independent)
struct FeedIncidentSessionSummary: Equatable, Codable {
    var sessionID: String
    var healthyExposureSeconds: Double
    var incidentCount: Int
    var outcome: String
    var sourceRevision: String
    var recordedAt: Date? = Date()
    var appVersion: String? = nil
    var appBuild: String? = nil
    var testSource: FeedIncidentTestSource? = nil
    var buildIdentity: String? = nil
}

enum FeedIncidentRuntime {
    private static let queue = DispatchQueue(label: "opv.feed-incident", qos: .utility)
    private static let gate = NSLock()
    private static let extrasLock = NSLock()
    private static var recorder = FeedIncidentRecorder()
    private static var store: FeedIncidentStore?
    private static var latestSnapshot: FeedIncidentSnapshot?
    private static var snapshotScheduled = false
    private static var pendingDecoderGeneration: Int?
    private static var pendingSocketGeneration: Int?
    private static var sessionContext: FeedIncidentSessionContext?
    private static var lastSummaryCheckpoint: TimeInterval = 0
    private static var extrasCache: [(name: String, body: String)] = []
    /// Queue-confined export of the incident bundles on disk; nil reloads them.
    private static var storeExtras: [(name: String, body: String)]?

    static func install() {
        queue.async {
            _ = preparedStore()
            _ = try? store?.markInterrupted(now: Date())
            if let root = store?.directory { FeedSessionSummaryStore.markInterrupted(root: root) }
            ReliabilityReporting.setFinalizedSpoolLoader {
                let dir = DiagnosticCenter.diagnosticsDirectory?
                    .appendingPathComponent("incidents", isDirectory: true)
                guard let dir else { return [] }
                return FeedIncidentStore(directory: dir).loadAll().filter {
                    ReliabilityReporting.isFinalized($0)
                }
            }
            ReliabilityReporting.setSessionSummaryLoader {
                guard
                    let root = DiagnosticCenter.diagnosticsDirectory?
                        .appendingPathComponent("incidents", isDirectory: true)
                else { return [] }
                return FeedSessionSummaryStore.load(root: root).filter { $0.outcome != "live" }
            }
            refreshExtrasCache()
            ReliabilityReporting.enqueueFinalizedFromSpool()
        }
    }

    static func beginSession(_ context: FeedIncidentSessionContext) {
        queue.async {
            persist(recorder.beginSession(context))
            ReliabilityReporting.enqueueFinalizedFromSpool()
            sessionContext = context
            lastSummaryCheckpoint = 0
            persistSessionSummary(outcome: "live")
        }
    }

    static func endSession(now: TimeInterval) {
        queue.async {
            persist(recorder.endSession(now: now))
            persistSessionSummary(
                outcome: summaryOutcome(
                    incidentCount: recorder.incidentCount,
                    exposure: recorder.healthyExposureSeconds))
            ReliabilityReporting.enqueueFinalizedFromSpool()
            sessionContext = nil
        }
    }

    /// Latest-wins 1 Hz ingest. Does not enqueue one disk write per snapshot.
    static func ingestSnapshot(_ snapshot: FeedIncidentSnapshot) {
        gate.lock()
        latestSnapshot = snapshot
        let schedule = !snapshotScheduled
        snapshotScheduled = true
        gate.unlock()
        if schedule {
            queue.async { drainSnapshot() }
        }
    }

    static func recordBreadcrumb(_ breadcrumb: FeedIncidentBreadcrumb) {
        queue.async {
            recorder.recordBreadcrumb(breadcrumb)
            ReliabilityReporting.noteBreadcrumb(breadcrumb)
        }
    }

    static func recordRepair(_ repair: FeedRepairRecord) {
        queue.async {
            persist(recorder.recordRepair(repair))
            ReliabilityReporting.noteRepair(repair)
        }
    }

    static func noteTestSource(_ source: FeedIncidentTestSource) {
        queue.async {
            recorder.noteTestSource(source)
            if var context = sessionContext, source.rank > context.testSource.rank {
                context.testSource = source
                sessionContext = context
            }
        }
    }

    static func noteDecoderGeneration(_ generation: Int) {
        scheduleGeneration { pendingDecoderGeneration = generation }
    }

    static func noteSocketGeneration(_ generation: Int) {
        scheduleGeneration { pendingSocketGeneration = generation }
    }

    static func noteExhausted(now: TimeInterval) {
        queue.async { persist(recorder.noteExhausted(now: now)) }
    }

    static func noteUnexpectedDisconnect(now: TimeInterval) {
        queue.async { persist(recorder.noteUnexpectedDisconnect(now: now)) }
    }

    /// Memory snapshot of extras. Does not wait on disk.
    static func reportExtras() -> [(name: String, body: String)] {
        extrasLock.lock()
        let copy = extrasCache
        extrasLock.unlock()
        return copy
    }

    /// Typed incident export. Completes off the live path; never writes on MainActor.
    static func exportVendorBundles(completion: @escaping (URL?) -> Void) {
        queue.async {
            let extras = preparedStore()?.exportExtras() ?? []
            let body =
                extras.first { $0.name == "incidents.txt" }?.body
                ?? "OpenPocketCine feed incidents\ncount=0"
            let url = DiagnosticCenter.diagnosticsDirectory?
                .appendingPathComponent("incidents-share.txt")
            if let url {
                try? body.write(to: url, atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Removes local incident bundles. Does not purge the SDK cache.
    static func deleteStoredIncidents(completion: @escaping () -> Void) {
        queue.async {
            try? preparedStore()?.deleteAll()
            if let root = store?.directory { FeedSessionSummaryStore.deleteAll(root: root) }
            if let dir = preparedStore()?.directory {
                try? FileManager.default.removeItem(
                    at: dir.appendingPathComponent("session-summary.json"))
            }
            storeExtras = nil
            extrasLock.lock()
            extrasCache = []
            extrasLock.unlock()
            DispatchQueue.main.async { completion() }
        }
    }

    static func summaryOutcome(incidentCount: Int, exposure: TimeInterval) -> String {
        if incidentCount > 0 { return "ended" }
        if exposure > 0 { return "healthy" }
        return "no-exposure"
    }

    static func seedExtrasCacheForTests(_ extras: [(name: String, body: String)]) {
        extrasLock.lock()
        extrasCache = extras
        extrasLock.unlock()
    }

    private static func scheduleGeneration(_ update: () -> Void) {
        gate.lock()
        update()
        let schedule = !snapshotScheduled
        snapshotScheduled = true
        gate.unlock()
        if schedule {
            queue.async { drainSnapshot() }
        }
    }

    private static func drainSnapshot() {
        gate.lock()
        let snapshot = latestSnapshot
        latestSnapshot = nil
        let decoderGen = pendingDecoderGeneration
        pendingDecoderGeneration = nil
        let socketGen = pendingSocketGeneration
        pendingSocketGeneration = nil
        snapshotScheduled = false
        gate.unlock()
        if let decoderGen { recorder.noteDecoderGeneration(decoderGen) }
        if let socketGen { recorder.noteSocketGeneration(socketGen) }
        if let snapshot {
            persist(recorder.recordSnapshot(snapshot))
            if snapshot.monotonicNow - lastSummaryCheckpoint >= 30 {
                lastSummaryCheckpoint = snapshot.monotonicNow
                persistSessionSummary(outcome: "live")
            }
        }
    }

    private static func persist(_ job: FeedIncidentPersistenceJob?) {
        guard let job = job, let store = preparedStore() else { return }
        try? store.persist(job)
        storeExtras = nil
        refreshExtrasCache()
    }

    private static func persistSessionSummary(outcome: String) {
        guard let summary = currentSessionSummary(outcome: outcome) else { return }
        guard let dir = preparedStore()?.directory else { return }
        FeedSessionSummaryStore.persist(summary, root: dir)
        // Summaries live outside the incident bundles, so the 30 s live checkpoint
        // does not reload and re-decode every stored incident.
        refreshExtrasCache()
        if summary.outcome != "live" { ReliabilityReporting.noteSessionSummary(summary) }
    }

    private static func currentSessionSummary(outcome: String? = nil)
        -> FeedIncidentSessionSummary?
    {
        guard let sessionContext else { return nil }
        return FeedIncidentSessionSummary(
            sessionID: sessionContext.sessionID,
            healthyExposureSeconds: recorder.healthyExposureSeconds,
            incidentCount: recorder.incidentCount,
            outcome: outcome
                ?? recorder.openHeader?.outcome.rawValue
                ?? summaryOutcome(
                    incidentCount: recorder.incidentCount,
                    exposure: recorder.healthyExposureSeconds),
            sourceRevision: sessionContext.sourceRevision,
            appVersion: sessionContext.appVersion, appBuild: sessionContext.appBuild,
            testSource: sessionContext.testSource,
            buildIdentity: sessionContext.buildIdentity)
    }

    private static func refreshExtrasCache() {
        if storeExtras == nil { storeExtras = preparedStore()?.exportExtras() }
        var extras = storeExtras ?? []
        if let summary = currentSessionSummary(),
            let data = try? FeedIncidentJSON.encoder().encode(summary),
            let body = String(data: data, encoding: .utf8)
        {
            extras.append(("session-summary.json", body))
        }
        extrasLock.lock()
        extrasCache = extras
        extrasLock.unlock()
    }

    private static func preparedStore() -> FeedIncidentStore? {
        if let store = store { return store }
        guard let dir = DiagnosticCenter.diagnosticsDirectory else { return nil }
        let incidents = dir.appendingPathComponent("incidents", isDirectory: true)
        let created = FeedIncidentStore(directory: incidents)
        store = created
        return created
    }
}
