import Foundation
import OpenCineAppKit
import Sentry

/// OpenCine's reporting runtime on the Sentry SDK: the SDK options, the runtime's calls, and the
/// privacy rules applied to every event and breadcrumb the SDK sends (crashes included).
final class SentryReliabilitySink: ReliabilityReportingSink, @unchecked Sendable {
    /// The SDK's dedicated session, kept while the SDK runs. Main thread.
    private var sdkSession: URLSession?

    var isEnabled: Bool { SentrySDK.isEnabled }

    func start(dsn: String, cacheRoot: URL) {
        let session = AppReliabilityURLProtocol.makeSDKSession()
        sdkSession = session
        SentrySDK.start(options: Self.makeOptions(dsn: dsn, urlSession: session, cacheRoot: cacheRoot))
    }

    func close() {
        SentrySDK.close()
        sdkSession = nil
    }

    func flush(timeout: TimeInterval) {
        SentrySDK.flush(timeout: timeout)
    }

    func addBreadcrumb(category: String, message: String, data: [String: String]?) {
        let breadcrumb = Breadcrumb(level: .info, category: category)
        breadcrumb.message = message
        breadcrumb.data = data
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    func setTags(_ tags: [String: String]) {
        SentrySDK.configureScope { scope in
            for (key, value) in tags { scope.setTag(value: value, key: key) }
        }
    }

    func capture(_ event: ReliabilityEvent, attachment: Data, attachmentName: String) {
        let sentryEvent = Self.event(event)
        SentrySDK.capture(event: sentryEvent) { scope in
            scope.clearAttachments()
            scope.addAttachment(
                Attachment(data: attachment, filename: attachmentName, contentType: "application/json"))
            Self.applyOriginalTags(sentryEvent.tags, to: scope)
        }
    }

    static func makeOptions(
        dsn: String, urlSession: URLSession,
        cacheRoot: URL = AppDiagnostics.reporting.sdkCacheRoot
    ) -> Options {
        let options = Options()
        options.dsn = dsn
        options.releaseName = AppDiagnostics.host.release()
        // Cocoa overwrites event.dist when this option is set. Queued reports
        // retain their original build; native events use the SDK bundle fallback.
        options.environment = AppDiagnostics.host.environment
        options.urlSession = urlSession
        options.maxCacheItems = 30
        options.maxAttachmentSize = 256 * 1_024
        options.cacheDirectoryPath = cacheRoot.path
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
        options.enableWatchdogTerminationTracking = AppDiagnostics.host.tracksWatchdogTerminations
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        options.maxBreadcrumbs = 32
        let privacy = AppDiagnostics.reporting.privacy
        options.beforeBreadcrumb = { privacy.scrubBreadcrumb($0) }
        options.beforeSend = { event in
            guard AppDiagnostics.consent.isOptedIn else { return nil }
            // Fatal/watchdog events from a prior run already carry persisted
            // tags; Cocoa skips applyToEvent for isFatalEvent. Never fill
            // current-run origin onto missing tags.
            return privacy.scrub(event)
        }
        return options
    }

    /// The typed event as the SDK's. A scrubbed event keeps no breadcrumbs of the SDK's scope.
    static func event(_ event: ReliabilityEvent) -> Event {
        let level: SentryLevel =
            switch event.level {
            case .info: .info
            case .warning: .warning
            case .error: .error
            }
        let sentryEvent = Event(level: level)
        sentryEvent.eventId = SentryId(uuidString: event.eventID)
        sentryEvent.timestamp = event.timestamp
        sentryEvent.releaseName = event.release
        sentryEvent.dist = event.dist
        sentryEvent.message = SentryMessage(formatted: event.message)
        sentryEvent.fingerprint = event.fingerprint
        sentryEvent.tags = event.tags
        sentryEvent.extra = event.extra
        sentryEvent.context = event.context
        if !event.attachesRecentBreadcrumbs { sentryEvent.breadcrumbs = [] }
        return sentryEvent
    }

    /// Capture-scope tags from the current run must not replace persisted origin.
    static func applyOriginalTags(_ tags: [String: String]?, to scope: Scope) {
        guard let tags else { return }
        for (key, value) in tags {
            scope.setTag(value: value, key: key)
        }
    }
}

extension ReliabilityReportingPrivacy {
    func scrubBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        guard Self.keepsBreadcrumb(category: breadcrumb.category, message: breadcrumb.message)
        else { return nil }
        breadcrumb.data = Self.breadcrumbData(breadcrumb.data)
        return breadcrumb
    }

    func scrub(_ event: Event) -> Event {
        event.user = nil
        event.request = nil
        event.breadcrumbs = Array((event.breadcrumbs ?? []).compactMap(scrubBreadcrumb).suffix(32))
        event.serverName = nil
        event.transaction = nil
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: message(formatted, fingerprint: event.fingerprint))
        }
        if let tags = event.tags { event.tags = self.tags(tags) }
        if let extra = event.extra { event.extra = Self.extra(extra) }
        if let context = event.context { event.context = Self.context(context) }
        if let exceptions = event.exceptions {
            for exception in exceptions {
                // Exception reasons can contain arbitrary user/application
                // data. Preserve type, mechanism and symbolication, not text.
                if exception.value != nil { exception.value = "Native exception" }
                scrub(frames: exception.stacktrace?.frames)
            }
        }
        if let threads = event.threads {
            for thread in threads {
                scrub(frames: thread.stacktrace?.frames)
            }
        }
        scrub(frames: event.stacktrace?.frames)
        return event
    }

    private func scrub(frames: [Frame]?) {
        guard let frames else { return }
        for frame in frames {
            frame.vars = nil
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            if let file = frame.fileName {
                frame.fileName = redact(file)
            }
            if let symbol = frame.function {
                frame.function = redact(symbol)
            }
        }
    }
}
