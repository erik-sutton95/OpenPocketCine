import Foundation
import OpenPocketViewCore
import Sentry

enum ReliabilityReportingConsent {
    static let defaultsKey = "opc.reliabilityReporting.optIn"
    static var defaults: UserDefaults = .standard

    static var hasDecision: Bool { defaults.object(forKey: defaultsKey) != nil }

    static var isOptedIn: Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setOptedIn(_ on: Bool) {
        defaults.set(on, forKey: defaultsKey)
    }

    static func resetForTests() {
        defaults.removeObject(forKey: defaultsKey)
    }
}

enum ReliabilityReportingDSN {
    static func configured() -> String? {
        let candidates = [
            Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
            ProcessInfo.processInfo.environment["SENTRY_DSN"],
        ]
        for raw in candidates {
            if let value = validated(raw) { return value }
        }
        return nil
    }

    static func validated(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("YOUR_"), !trimmed.contains("example") else {
            return nil
        }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            return nil
        }
        guard let host = url.host, !host.isEmpty else { return nil }
        guard let user = url.user, !user.isEmpty else { return nil }
        guard url.password == nil, url.query == nil, url.fragment == nil,
            let project = url.path.split(separator: "/").last,
            !project.isEmpty, project.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return trimmed
    }

    static var isAvailable: Bool { configured() != nil }
}

enum ReliabilityReportingPrivacy {
    static let extraAllowlist: Set<String> = [
        "schemaVersion", "failingStage", "errorClass", "outcome", "kind",
        "incidentCount", "sourceRevision", "hardwareClass", "cameraFirmware", "assistState",
        "decoderGeneration",
        "socketGeneration", "worstGapSeconds", "healthyExposureSeconds", "incidentCount",
        "testSource", "buildIdentity", "trigger", "recoveredBy",
    ]

    static let contextAllowlist: [String: Set<String>] = [
        "os": ["name", "version", "build"],
        "device": ["family", "model", "arch", "free_memory", "memory_size", "thermal_state"],
        "app": ["app_version", "app_build", "build_type", "app_memory", "in_foreground"],
        "feed": [
            "schemaVersion", "failingStage", "errorClass", "outcome", "kind",
            "assistState", "hardwareClass", "testSource", "buildIdentity", "cameraFamily",
            "trigger", "recoveredBy", "worstGapSeconds",
        ],
    ]

    static func eventID(fromIncidentID raw: String) -> SentryId {
        let hex = raw.filter { $0.isHexDigit }
        if hex.count >= 32 {
            let slice = String(hex.prefix(32))
            return SentryId(uuidString: slice)
        }
        if let uuid = UUID(uuidString: raw) {
            return SentryId(uuid: uuid)
        }
        var padded = hex
        while padded.count < 32 { padded.append("0") }
        return SentryId(uuidString: String(padded.prefix(32)))
    }

    static func fingerprint(schema: Int, kind: String, stage: String, errorClass: String)
        -> [String]
    {
        [
            "feed-incident",
            "schema:\(schema)",
            "kind:\(FeedIncidentPrivacyToken.token(kind))",
            "stage:\(FeedIncidentPrivacyToken.token(stage))",
            "errorClass:\(FeedIncidentPrivacyToken.token(errorClass))",
        ]
    }

    static func validatedEnvelope(from bundle: FeedIncidentBundle) -> FeedIncidentVendorEnvelope? {
        let envelope = FeedIncidentExport.envelope(from: bundle)
        guard envelope.schemaVersion >= 1 else { return nil }
        guard envelope.eventName == "feed.incident" else { return nil }
        let id = envelope.incidentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != "unknown" else { return nil }
        let stage = envelope.grouping.failingStage
        guard FeedIncidentFailingStage(rawValue: stage) != nil else { return nil }
        return envelope
    }

    static let tagAllowlist: Set<String> = [
        "failingStage", "errorClass", "outcome", "kind",
        "sourceRevision", "cameraFamily", "cameraFirmware", "hardwareClass",
        "testSource", "buildIdentity", "trigger", "recoveredBy", "gap",
    ]

    static func scrubBreadcrumb(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        guard breadcrumb.category == "feed",
            let message = breadcrumb.message,
            FeedIncidentNativeBreadcrumb.isAllowedMessage(message)
        else { return nil }
        var strings: [String: String] = [:]
        if let data = breadcrumb.data {
            for (key, value) in data {
                if let text = value as? String { strings[key] = text }
            }
        }
        let kept = FeedIncidentNativeBreadcrumb.sanitized(strings)
        breadcrumb.data = kept.isEmpty ? nil : kept
        return breadcrumb
    }

    static func scrub(_ event: Event) -> Event {
        event.user = nil
        event.request = nil
        event.breadcrumbs = Array((event.breadcrumbs ?? []).compactMap(scrubBreadcrumb).suffix(32))
        event.serverName = nil
        event.transaction = nil
        if let formatted = event.message?.formatted {
            let isTypedFeedEvent =
                event.fingerprint?.first == "feed-incident"
                || event.fingerprint?.first == "feed-session"
            event.message = SentryMessage(
                formatted: isTypedFeedEvent
                    ? PrivacyRedactor.redact(formatted) : "Application diagnostic")
        }
        if var tags = event.tags {
            tags = tags.filter { tagAllowlist.contains($0.key) }
            for key in tags.keys {
                let limit = (key == "sourceRevision" || key == "buildIdentity") ? 64 : 32
                tags[key] = PrivacyRedactor.redact(String((tags[key] ?? "").prefix(limit)))
            }
            event.tags = tags.isEmpty ? nil : tags
        }
        if var extra = event.extra {
            extra = extra.filter { extraAllowlist.contains($0.key) }
            event.extra = extra.isEmpty ? nil : extra
        }
        if var context = event.context {
            var kept: [String: [String: Any]] = [:]
            for (section, values) in context {
                guard let allow = contextAllowlist[section] else { continue }
                let filtered = values.filter { allow.contains($0.key) }
                if !filtered.isEmpty { kept[section] = filtered }
            }
            event.context = kept.isEmpty ? nil : kept
        }
        if let exceptions = event.exceptions {
            for exception in exceptions {
                // Exception reasons can contain arbitrary user/application
                // data. Preserve type, mechanism and symbolication, not text.
                if exception.value != nil { exception.value = "Native exception" }
                redact(frames: exception.stacktrace?.frames)
            }
        }
        if let threads = event.threads {
            for thread in threads {
                redact(frames: thread.stacktrace?.frames)
            }
        }
        redact(frames: event.stacktrace?.frames)
        return event
    }

    private static func redact(frames: [Frame]?) {
        guard let frames else { return }
        for frame in frames {
            frame.vars = nil
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            if let file = frame.fileName {
                frame.fileName = PrivacyRedactor.redact(file)
            }
            if let symbol = frame.function {
                frame.function = PrivacyRedactor.redact(symbol)
            }
        }
    }

    static func typedJSON(from bundle: FeedIncidentBundle) -> Data? {
        guard validatedEnvelope(from: bundle) != nil else { return nil }
        guard let data = try? FeedIncidentCoding.encoder().encode(bundle) else { return nil }
        if data.count > 262_144 { return nil }
        return data
    }
}

enum FeedIncidentPrivacyToken {
    static func token(_ raw: String) -> String {
        let clipped = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        return PrivacyRedactor.redact(clipped)
    }
}
