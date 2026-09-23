import Foundation
import Network
import OpenPocketViewCore
import Sentry

/// Opt-in Sentry adapter, installed by the app and gated by camera-session activity.
/// Does not start without persisted consent and a valid https DSN. Does not mark
/// an incident delivered when it is only queued.
enum ReliabilityReporting {
    private static let queue = DispatchQueue(label: "opv.reliability", qos: .utility)
    private static let stateLock = NSLock()
    private static var startedStorage = false
    private static var sdkStarted: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return startedStorage
        }
        set {
            stateLock.lock()
            startedStorage = newValue
            stateLock.unlock()
        }
    }
    private static var pathMonitor: NWPathMonitor?
    private static var resumeScheduled = false
    private static var idlePollScheduled = false
    private static var sdkSession: URLSession?
    private static var resumeAttempt = 0
    private static var epoch: UInt64 = 0
    private static var captureHandler: ((Event, Data) -> Void)?
    private static var pendingCaptureIDs: Set<String> = []
    private static var pendingEventIDs: [String: String] = [:]
    private static var finalizedSpoolLoader: () -> [FeedIncidentBundle] = { [] }
    private static var sessionSummaryLoader: () -> [FeedIncidentSessionSummary] = { [] }
    static var sdkCacheRoot: URL = {
        let base =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("opc-reliability-sdk", isDirectory: true)
    }()

    static var isOptedIn: Bool { ReliabilityReportingConsent.isOptedIn }
    static var isAvailable: Bool { ReliabilityReportingDSN.isAvailable }

    static func noteBreadcrumb(_ source: FeedIncidentBreadcrumb) {
        guard isOptedIn, SentrySDK.isEnabled else { return }
        let breadcrumb = Breadcrumb(level: .info, category: "feed")
        breadcrumb.message = source.kind.rawValue
        let details = FeedIncidentNativeBreadcrumb.details(kind: source.kind, detail: source.detail)
        breadcrumb.data = details.isEmpty ? nil : details
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    static func noteRepair(_ repair: FeedRepairRecord) {
        guard isOptedIn, SentrySDK.isEnabled else { return }
        let breadcrumb = Breadcrumb(level: .info, category: "feed")
        breadcrumb.message = "repair"
        let details = FeedIncidentNativeBreadcrumb.details(repair: repair)
        breadcrumb.data = details.isEmpty ? nil : details
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    /// Once-only current-run scope upgrade. Does not rewrite queued/fatal tags.
    static func noteCurrentTestSource(_ source: FeedIncidentTestSource) {
        guard isOptedIn else { return }
        DispatchQueue.main.async {
            guard SentrySDK.isEnabled else { return }
            SentrySDK.configureScope { scope in
                scope.setTag(value: source.rawValue, key: "testSource")
            }
        }
    }

    static func install() {
        ReliabilityReportingURLProtocol.gate = ReliabilityReportingGate.shared
        ReliabilityReportingURLProtocol.onEnvelopeAccepted = { eventID in
            noteTransportSuccess(eventID: eventID)
        }
        if let dsn = ReliabilityReportingDSN.configured() {
            ReliabilityReportingURLProtocol.dsnHost = ReliabilityReportingHostPolicy.host(
                fromDSN: dsn)
        }
        applySDKState()
    }

    static func setCameraSessionActive(_ active: Bool) {
        ReliabilityReportingGate.shared.setCameraSessionActive(active)
        if active {
            ReliabilityReportingGate.shared.cancelPending()
        } else {
            if !sdkStarted, ReliabilityReportingConsent.isOptedIn {
                applySDKState()
            }
            enqueueFinalizedFromSpool()
            scheduleResumeIfIdle()
        }
    }

    static func setConsent(_ on: Bool) {
        bumpEpoch()
        ReliabilityReportingConsent.setOptedIn(on)
        if !on {
            ReliabilityReportingGate.shared.cancelPending(includeIndependent: false)
        }
        applySDKState()
    }

    static func setFinalizedSpoolLoader(_ loader: @escaping () -> [FeedIncidentBundle]) {
        queue.async { finalizedSpoolLoader = loader }
    }

    static func setSessionSummaryLoader(_ loader: @escaping () -> [FeedIncidentSessionSummary]) {
        queue.async { sessionSummaryLoader = loader }
    }

    static func isFinalized(_ bundle: FeedIncidentBundle) -> Bool {
        switch bundle.header.outcome {
        case .open: return false
        case .recovered, .interrupted, .exhausted, .suppressed: return true
        }
    }

    /// Enqueue a finalized incident once. Open/checkpoint/repair snapshots stay local.
    static func enqueueFinalized(_ bundle: FeedIncidentBundle) {
        let capturedEpoch = currentEpoch()
        queue.async { captureIfFinalized(bundle, epoch: capturedEpoch) }
    }

    static func enqueueFinalizedFromSpool() {
        let capturedEpoch = currentEpoch()
        queue.async {
            guard ReliabilityReportingConsent.isOptedIn, capturedEpoch == currentEpoch(),
                !ReliabilityReportingGate.shared.shouldBlockUpload
            else {
                return
            }
            for bundle in finalizedSpoolLoader() where isFinalized(bundle) {
                captureIfFinalized(bundle, epoch: capturedEpoch)
            }
            for summary in sessionSummaryLoader() {
                captureSessionSummary(summary, epoch: capturedEpoch)
            }
        }
    }

    /// Evolving local spool must not call this. Kept for tests of finalized enqueue.
    static func noteLocalCapture(_ bundle: FeedIncidentBundle) {
        enqueueFinalized(bundle)
    }

    /// A separate, bounded event includes sessions with no dropout.
    static func noteSessionSummary(_ summary: FeedIncidentSessionSummary) {
        let capturedEpoch = currentEpoch()
        queue.async {
            captureSessionSummary(summary, epoch: capturedEpoch)
        }
    }

    static func receipt(for incidentID: String) -> ReliabilityReportingReceipt? {
        ReliabilityReportingReceipts.load(incidentID: incidentID, root: sdkCacheRoot)
    }

    static func makeOptions(dsn: String, urlSession: URLSession) -> Options {
        let options = Options()
        options.dsn = dsn
        options.releaseName = ReliabilityReportingConfiguration.release()
        // Cocoa overwrites event.dist when this option is set. Queued reports
        // retain their original build; native events use the SDK bundle fallback.
        options.environment = ReliabilityReportingConfiguration.environment
        options.urlSession = urlSession
        options.maxCacheItems = 30
        options.maxAttachmentSize = 256 * 1_024
        options.cacheDirectoryPath = sdkCacheRoot.path
        options.sendDefaultPii = false
        options.enableSwizzling = false
        options.enableNetworkBreadcrumbs = false
        options.enableNetworkTracking = false
        options.enableAutoSessionTracking = false
        options.enableAutoBreadcrumbTracking = false
        options.enableAutoPerformanceTracing = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableMetricKit = false
        options.enableMetricKitRawPayload = false
        options.attachScreenshot = false
        options.attachStacktrace = false
        options.attachViewHierarchy = false
        options.reportAccessibilityIdentifier = false
        options.enableUserInteractionTracing = false
        options.enableUIViewControllerTracing = false
        options.enableTimeToFullDisplayTracing = false
        options.enablePersistingTracesWhenCrashing = false
        options.enableLogs = false
        options.enableMemoryIntrospection = false
        options.tracesSampleRate = 0
        options.tracesSampler = nil
        options.shutdownTimeInterval = 0
        options.enableCrashHandler = true
        options.enableAppHangTracking = true
        options.enableWatchdogTerminationTracking = true
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        options.maxBreadcrumbs = 32
        options.beforeBreadcrumb = { ReliabilityReportingPrivacy.scrubBreadcrumb($0) }
        options.beforeSend = { event in
            guard ReliabilityReportingConsent.isOptedIn else { return nil }
            // Fatal/watchdog events from a prior run already carry persisted
            // tags; Cocoa skips applyToEvent for isFatalEvent. Never fill
            // current-run origin onto missing tags.
            return ReliabilityReportingPrivacy.scrub(event)
        }
        return options
    }

    static func setCaptureHandlerForTests(_ handler: ((Event, Data) -> Void)?) {
        captureHandler = handler
    }

    private static func applySDKState() {
        let consent = ReliabilityReportingConsent.isOptedIn
        let dsn = ReliabilityReportingDSN.configured()
        if consent, let dsn {
            scheduleIdlePoll()
            observeInternetIfNeeded()
            // Install local crash/hang capture even when launching on camera Wi-Fi.
            // The dedicated transport independently blocks every upload.
            startSDK(dsn: dsn)
        } else {
            stopAndPurgeSDKOwned()
        }
    }

    private static func observeInternetIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                guard ReliabilityReportingConsent.isOptedIn else { return }
                if ReliabilityReportingGate.shared.shouldBlockUpload {
                    ReliabilityReportingGate.shared.cancelPending()
                } else if path.status == .satisfied {
                    if !sdkStarted, let dsn = ReliabilityReportingDSN.configured() {
                        startSDK(dsn: dsn)
                    }
                    enqueueFinalizedFromSpool()
                    scheduleResumeIfIdle()
                }
            }
        }
        monitor.start(queue: queue)
    }

    private static func startSDK(dsn: String) {
        guard !sdkStarted else {
            enqueueFinalizedFromSpool()
            return
        }
        let capturedEpoch = currentEpoch()
        ReliabilityReportingURLProtocol.dsnHost = ReliabilityReportingHostPolicy.host(fromDSN: dsn)
        let session = ReliabilityReportingURLProtocol.makeSDKSession()
        let options = makeOptions(dsn: dsn, urlSession: session)
        queue.async {
            guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn else {
                return
            }
            try? FileManager.default.createDirectory(
                at: sdkCacheRoot, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn
                else { return }
                if !sdkStarted {
                    sdkSession = session
                    SentrySDK.start(options: options)
                    SentrySDK.configureScope { scope in
                        scope.setTag(
                            value: Bundle.main.object(
                                forInfoDictionaryKey: "OPCSourceRevision") as? String ?? "unknown",
                            key: "sourceRevision")
                        scope.setTag(
                            value: FeedIncidentOrigin.currentTestSource().rawValue,
                            key: "testSource")
                        scope.setTag(
                            value: FeedIncidentOrigin.currentBuildIdentity(),
                            key: "buildIdentity")
                    }
                    sdkStarted = true
                }
                enqueueFinalizedFromSpool()
                scheduleResumeIfIdle()
            }
        }
    }

    private static func stopAndPurgeSDKOwned() {
        pathMonitor?.cancel()
        pathMonitor = nil
        ReliabilityReportingGate.shared.cancelPending(includeIndependent: false)
        let close = {
            if sdkStarted {
                SentrySDK.close()
                sdkStarted = false
            }
            sdkSession = nil
            // Ordered before a subsequent start's cache preparation, including
            // a rapid off/on toggle. Prior capture writes are epoch-invalidated.
            queue.async {
                ReliabilityReportingReceipts.purge(root: sdkCacheRoot)
                try? FileManager.default.removeItem(at: sdkCacheRoot)
            }
        }
        if Thread.isMainThread { close() } else { DispatchQueue.main.async(execute: close) }
    }

    private static func captureIfFinalized(
        _ bundle: FeedIncidentBundle, epoch capturedEpoch: UInt64
    ) {
        guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn else { return }
        guard isFinalized(bundle) else { return }
        guard let envelope = ReliabilityReportingPrivacy.validatedEnvelope(from: bundle) else {
            return
        }
        guard let json = ReliabilityReportingPrivacy.typedJSON(from: bundle) else { return }
        let eventID = ReliabilityReportingPrivacy.eventID(fromIncidentID: envelope.incidentID)
        let event = makeEvent(envelope: envelope, eventID: eventID)
        event.timestamp = bundle.header.startedAtWallClock
        event.releaseName = ReliabilityReportingConfiguration.release(
            version: bundle.header.appVersion, build: bundle.header.appBuild)
        event.dist = bundle.header.appBuild
        event.tags?["sourceRevision"] = bundle.header.sourceRevision
        event.tags?["cameraFamily"] = bundle.header.cameraFamily
        event.tags?["cameraFirmware"] = bundle.header.cameraFirmware ?? "unknown"
        event.tags?["hardwareClass"] = bundle.header.hardwareClass
        event.tags?["testSource"] = bundle.header.resolvedTestSource.rawValue
        event.tags?["buildIdentity"] = bundle.header.resolvedBuildIdentity
        capturePayload(event: event, json: json, id: envelope.incidentID, epoch: capturedEpoch)
    }

    private static func captureSessionSummary(_ summary: FeedIncidentSessionSummary, epoch: UInt64)
    {
        guard summary.outcome != "live", UUID(uuidString: summary.sessionID) != nil,
            summary.healthyExposureSeconds.isFinite, summary.healthyExposureSeconds >= 0,
            let json = try? FeedIncidentJSON.encoder().encode(summary), json.count <= 4_096
        else { return }
        let event = Event(level: .info)
        event.eventId = ReliabilityReportingPrivacy.eventID(fromIncidentID: summary.sessionID)
        event.timestamp = summary.recordedAt
        if let version = summary.appVersion, let build = summary.appBuild {
            event.releaseName = ReliabilityReportingConfiguration.release(
                version: version, build: build)
            event.dist = build
        } else {
            event.releaseName = "legacy-session-unknown-release"
        }
        event.message = SentryMessage(formatted: "Feed session summary")
        event.fingerprint = ["feed-session", "schema:1"]
        event.tags = [
            "kind": "sessionSummary", "outcome": summary.outcome,
            "sourceRevision": summary.sourceRevision,
            "testSource": (summary.testSource ?? .unknown).rawValue,
            "buildIdentity": FeedIncidentBuildIdentity.parse(summary.buildIdentity),
        ]
        event.extra = [
            "healthyExposureSeconds": summary.healthyExposureSeconds,
            "incidentCount": summary.incidentCount, "sourceRevision": summary.sourceRevision,
            "testSource": (summary.testSource ?? .unknown).rawValue,
            "buildIdentity": FeedIncidentBuildIdentity.parse(summary.buildIdentity),
        ]
        capturePayload(event: event, json: json, id: "session-" + summary.sessionID, epoch: epoch)
    }

    /// Disk runs on the reporting queue; SDK state/capture is checked on main.
    /// A queued receipt can be retried after five minutes if SDK cache eviction
    /// or an interrupted handoff lost it. Stable event IDs deduplicate delivery.
    private static func capturePayload(
        event: Event, json: Data, id: String, epoch capturedEpoch: UInt64
    ) {
        guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn,
            !ReliabilityReportingGate.shared.shouldBlockUpload
        else { return }
        ReliabilityReportingReceipts.applyTTL(root: sdkCacheRoot)
        if let receipt = ReliabilityReportingReceipts.load(incidentID: id, root: sdkCacheRoot),
            receipt.state == .confirmed || Date().timeIntervalSince(receipt.updatedAt) < 300
        {
            return
        }
        guard pendingCaptureIDs.insert(id).inserted else { return }
        pendingEventIDs[id] = event.eventId.sentryIdString
        DispatchQueue.main.async {
            guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn,
                sdkStarted || captureHandler != nil
            else {
                queue.async {
                    pendingCaptureIDs.remove(id)
                    pendingEventIDs.removeValue(forKey: id)
                }
                return
            }
            defer {
                queue.async {
                    pendingCaptureIDs.remove(id)
                    pendingEventIDs.removeValue(forKey: id)
                }
            }
            if let captureHandler {
                captureHandler(event, json)
            } else {
                SentrySDK.capture(event: event) { scope in
                    scope.clearAttachments()
                    scope.addAttachment(
                        Attachment(
                            data: json, filename: id + ".json", contentType: "application/json"))
                    applyOriginalTags(event.tags, to: scope)
                }
            }
            queue.async {
                guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn else {
                    return
                }
                // A fast transport can confirm before this queued write runs.
                guard
                    ReliabilityReportingReceipts.load(incidentID: id, root: sdkCacheRoot)?.state
                        != .confirmed
                else {
                    return
                }
                ReliabilityReportingReceipts.store(
                    ReliabilityReportingReceipt(
                        incidentID: id, eventID: event.eventId.sentryIdString,
                        state: .queued, updatedAt: Date()), root: sdkCacheRoot)
            }
        }
    }

    private static func bumpEpoch() {
        stateLock.lock()
        epoch += 1
        stateLock.unlock()
    }

    private static func currentEpoch() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return epoch
    }

    static func noteTransportSuccess(eventID: String) {
        let capturedEpoch = currentEpoch()
        queue.async {
            guard capturedEpoch == currentEpoch(), ReliabilityReportingConsent.isOptedIn else {
                return
            }
            for (id, pendingEventID) in pendingEventIDs where pendingEventID == eventID {
                ReliabilityReportingReceipts.store(
                    ReliabilityReportingReceipt(
                        incidentID: id, eventID: eventID,
                        state: .confirmed, updatedAt: Date()), root: sdkCacheRoot)
            }
            ReliabilityReportingReceipts.markConfirmed(eventID: eventID, root: sdkCacheRoot)
        }
    }

    private static func makeEvent(
        envelope: FeedIncidentVendorEnvelope, eventID: SentryId
    ) -> Event {
        let event = Event(level: .error)
        event.eventId = eventID
        // Kind is in the fingerprint, so the issue title stays stable per group.
        event.message = SentryMessage(
            formatted: "feed incident \(envelope.grouping.failingStage): \(envelope.kind)")
        event.fingerprint = ReliabilityReportingPrivacy.fingerprint(
            schema: envelope.schemaVersion,
            kind: envelope.kind,
            stage: envelope.grouping.failingStage,
            errorClass: envelope.grouping.errorClass)
        event.tags = [
            "failingStage": envelope.grouping.failingStage,
            "errorClass": envelope.grouping.errorClass,
            "outcome": envelope.grouping.outcome,
            "kind": envelope.kind,
            "testSource": envelope.testSource,
            "buildIdentity": envelope.buildIdentity,
            "trigger": envelope.trigger,
            "recoveredBy": envelope.recoveredBy,
            "gap": FeedIncidentExport.gapBucket(envelope.worstGapSeconds),
        ]
        event.extra = [
            "schemaVersion": envelope.schemaVersion,
            "failingStage": envelope.grouping.failingStage,
            "errorClass": envelope.grouping.errorClass,
            "outcome": envelope.grouping.outcome,
            "kind": envelope.kind,
            "hardwareClass": envelope.grouping.hardwareClass,
            "cameraFirmware": envelope.grouping.cameraFirmware,
            "assistState": envelope.grouping.assistState,
            "decoderGeneration": envelope.decoderGeneration,
            "socketGeneration": envelope.socketGeneration,
            "worstGapSeconds": envelope.worstGapSeconds,
            "healthyExposureSeconds": envelope.healthyExposureSeconds,
            "testSource": envelope.testSource,
            "buildIdentity": envelope.buildIdentity,
            "trigger": envelope.trigger,
            "recoveredBy": envelope.recoveredBy,
        ]
        event.context = [
            "feed": [
                "schemaVersion": envelope.schemaVersion,
                "failingStage": envelope.grouping.failingStage,
                "errorClass": envelope.grouping.errorClass,
                "outcome": envelope.grouping.outcome,
                "kind": envelope.kind,
                "assistState": envelope.grouping.assistState,
                "hardwareClass": envelope.grouping.hardwareClass,
                "testSource": envelope.testSource,
                "buildIdentity": envelope.buildIdentity,
                "trigger": envelope.trigger,
                "recoveredBy": envelope.recoveredBy,
                "worstGapSeconds": envelope.worstGapSeconds,
            ]
        ]
        return ReliabilityReportingPrivacy.scrub(event)
    }

    /// Capture-scope tags from the current run must not replace persisted origin.
    static func applyOriginalTags(_ tags: [String: String]?, to scope: Scope) {
        guard let tags else { return }
        for (key, value) in tags {
            scope.setTag(value: value, key: key)
        }
    }

    private static func scheduleIdlePoll() {
        guard !idlePollScheduled else { return }
        idlePollScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            idlePollScheduled = false
            guard ReliabilityReportingConsent.isOptedIn,
                let dsn = ReliabilityReportingDSN.configured()
            else { return }
            if !ReliabilityReportingGate.shared.shouldBlockUpload {
                startSDK(dsn: dsn)
                enqueueFinalizedFromSpool()
                scheduleResumeIfIdle()
            }
            scheduleIdlePoll()
        }
    }

    private static func scheduleResumeIfIdle() {
        guard !ReliabilityReportingGate.shared.shouldBlockUpload,
            ReliabilityReportingConsent.isOptedIn,
            sdkStarted, !resumeScheduled
        else { return }
        resumeScheduled = true
        let attempt = resumeAttempt
        resumeAttempt = min(resumeAttempt + 1, 6)
        let jitter = Double((attempt * 37) % 100) / 100
        let delay = ReliabilityReportingBackoff.delaySeconds(attempt: attempt, jitter: jitter)
        let capturedEpoch = currentEpoch()
        queue.asyncAfter(deadline: .now() + delay) {
            defer { DispatchQueue.main.async { resumeScheduled = false } }
            guard capturedEpoch == currentEpoch(),
                ReliabilityReportingConsent.isOptedIn,
                !ReliabilityReportingGate.shared.shouldBlockUpload,
                sdkStarted
            else { return }
            SentrySDK.flush(timeout: 2)
            DispatchQueue.main.async { resumeAttempt = 0 }
        }
    }
}
