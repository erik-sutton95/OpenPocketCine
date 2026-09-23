import Foundation

/// On-device incident spool. Journal-independent. No upload.
public struct FeedIncidentStore: Sendable {
    public enum StorageError: Error { case bundleTooLarge }
    public var directory: URL
    public var limits: FeedIncidentLimits

    public init(directory: URL, limits: FeedIncidentLimits = .production) {
        self.directory = directory
        self.limits = limits
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    public func persist(_ job: FeedIncidentPersistenceJob, now: Date = Date()) throws {
        var bundle = job.bundle
        bundle = Self.enforceSize(bundle, maxBytes: limits.maxBundleBytes)
        try write(bundle)
        try applyRetention(now: now)
    }

    public func loadAll() -> [FeedIncidentBundle] {
        urls().compactMap { load(from: $0) }
            .sorted { $0.header.startedAtWallClock > $1.header.startedAtWallClock }
    }

    /// Marks leftover open incidents as process-interrupted, not as a crash.
    @discardableResult
    public func markInterrupted(now: Date = Date()) throws -> [String] {
        try applyRetention(now: now)
        var changed: [String] = []
        for url in urls() {
            guard var bundle = load(from: url), bundle.header.outcome == .open else { continue }
            bundle.header.outcome = .interrupted
            try write(bundle)
            changed.append(bundle.header.incidentID)
        }
        return changed
    }

    public func applyRetention(now: Date) throws {
        var entries: [(url: URL, started: Date, bytes: Int)] = []
        for url in urls() {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let bytes = values?.fileSize ?? 0
            let started = load(from: url)?.header.startedAtWallClock ?? now
            if now.timeIntervalSince(started) > limits.ttl {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            entries.append((url, started, bytes))
        }
        entries.sort { $0.started < $1.started }
        var total = entries.reduce(0) { $0 + $1.bytes }
        while entries.count > limits.maxBundles || total > limits.maxSpoolBytes,
            let oldest = entries.first
        {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
            entries.removeFirst()
        }
    }

    public func deleteAll() throws {
        for url in urls() {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func exportExtras() -> [(name: String, body: String)] {
        FeedIncidentExport.extras(from: loadAll())
    }

    private func write(_ bundle: FeedIncidentBundle) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            FeedIncidentFileNaming.incident(id: bundle.header.incidentID))
        let data = try FeedIncidentCoding.encoder().encode(bundle)
        guard data.count <= limits.maxBundleBytes else { throw StorageError.bundleTooLarge }
        try data.write(to: url, options: .atomic)
    }

    private func load(from url: URL) -> FeedIncidentBundle? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= limits.maxBundleBytes, let data = try? Data(contentsOf: url)
        else { return nil }
        return try? FeedIncidentCoding.decoder().decode(FeedIncidentBundle.self, from: data)
    }

    private func urls() -> [URL] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles])) ?? []
        return files.filter {
            $0.lastPathComponent.hasPrefix("incident-") && $0.pathExtension == "json"
        }
    }

    static func enforceSize(_ bundle: FeedIncidentBundle, maxBytes: Int) -> FeedIncidentBundle {
        var current = bundle
        for _ in 0..<6 {
            guard encodedSize(current) > maxBytes else { return current }
            current.header.evictions += 1
            if current.during.count > 8 {
                current.during = FeedIncidentSampling.downsample(current.during, keep: 8)
                continue
            }
            if current.prelude.count > 8 {
                current.prelude = FeedIncidentSampling.downsample(current.prelude, keep: 8)
                continue
            }
            if current.aftermath.count > 4 {
                current.aftermath = FeedIncidentSampling.downsample(current.aftermath, keep: 4)
                continue
            }
            if current.breadcrumbs.count > 4 {
                current.breadcrumbs = Array(current.breadcrumbs.suffix(4))
                continue
            }
            if current.repairs.count > 4 {
                current.repairs = Array(current.repairs.suffix(4))
                continue
            }
            current.during = []
            current.prelude = Array(current.prelude.suffix(2))
            current.aftermath = Array(current.aftermath.suffix(2))
        }
        return current
    }

    private static func encodedSize(_ bundle: FeedIncidentBundle) -> Int {
        (try? FeedIncidentCoding.encoder().encode(bundle).count) ?? Int.max
    }
}

/// Journal-independent incident text and vendor-neutral envelope.
public enum FeedIncidentExport: Sendable {
    public static func extras(from bundles: [FeedIncidentBundle]) -> [(
        name: String, body: String
    )] {
        var extras: [(name: String, body: String)] = []
        extras.append(("incidents.txt", text(from: bundles)))
        for bundle in bundles {
            if let data = try? FeedIncidentCoding.encoder().encode(bundle),
                let body = String(data: data, encoding: .utf8)
            {
                extras.append(
                    (
                        FeedIncidentFileNaming.incident(id: bundle.header.incidentID),
                        PrivacyRedactor.redact(body)
                    ))
            }
        }
        return extras
    }

    public static func text(from bundles: [FeedIncidentBundle]) -> String {
        var lines = [
            "OpenPocketCine feed incidents (typed snapshots, no journal)",
            "count=\(bundles.count) schema=\(FeedIncidentSchema.version)",
        ]
        for bundle in bundles {
            let header = bundle.header
            lines.append("---")
            lines.append(
                "id=\(header.incidentID) kind=\(header.kind.rawValue) stage=\(header.failingStage.rawValue) outcome=\(header.outcome.rawValue)"
            )
            lines.append(
                "session=\(header.sessionID) started=\(ISO8601DateFormatter().string(from: header.startedAtWallClock)) gap=\(String(format: "%.3f", header.worstGapSeconds))s"
            )
            lines.append(
                "release=\(header.appVersion)(\(header.appBuild)) rev=\(header.sourceRevision) identity=\(header.resolvedBuildIdentity) source=\(header.resolvedTestSource.rawValue) os=\(header.osName) \(header.osVersion) hw=\(header.hardwareClass)"
            )
            lines.append(
                "camera=\(header.cameraFamily) fw=\(header.cameraFirmware ?? "none") decoderGen=\(header.decoderGeneration) socketGen=\(header.socketGeneration) assist=\(header.assistState)"
            )
            if let errorClass = header.errorClass {
                lines.append("errorClass=\(errorClass)")
            }
            lines.append(
                "snapshots prelude=\(bundle.prelude.count) during=\(bundle.during.count) aftermath=\(bundle.aftermath.count) repairs=\(bundle.repairs.count) breadcrumbs=\(bundle.breadcrumbs.count) evictions=\(header.evictions) healthySeconds=\(String(format: "%.1f", header.healthyExposureSeconds))"
            )
            if header.processInterrupted {
                lines.append("process=interrupted")
            }
        }
        return PrivacyRedactor.redact(lines.joined(separator: "\n"))
    }

    /// Coarse, searchable picture-gap tag. Exact seconds stay in extras.
    public static func gapBucket(_ seconds: TimeInterval) -> String {
        let edges: [TimeInterval] = [2, 5, 10, 20, 40, 120]
        guard let upper = edges.first(where: { seconds < $0 }) else { return "120s+" }
        let lower = edges.last(where: { $0 < upper }) ?? 0
        return "\(Int(lower))-\(Int(upper))s"
    }

    public static func envelope(from bundle: FeedIncidentBundle) -> FeedIncidentVendorEnvelope {
        let header = bundle.header
        // The 1 Hz snapshot opens an incident up to a tick after its first repair.
        let own = bundle.repairs.filter { $0.monotonicAt >= header.startedAtMonotonic - 1.5 }
        let grouping = FeedIncidentGrouping(
            schemaVersion: header.schemaVersion,
            failingStage: header.failingStage.rawValue,
            errorClass: header.errorClass ?? "none",
            outcome: header.outcome.rawValue,
            release: "\(header.appVersion)(\(header.appBuild))",
            os: "\(header.osName) \(header.osVersion)",
            hardwareClass: header.hardwareClass,
            cameraFirmware: header.cameraFirmware ?? "none",
            assistState: header.assistState)
        return FeedIncidentVendorEnvelope(
            schemaVersion: header.schemaVersion,
            eventName: "feed.incident",
            grouping: grouping,
            incidentID: header.incidentID,
            sessionID: header.sessionID,
            kind: header.kind.rawValue,
            worstGapSeconds: header.worstGapSeconds,
            healthyExposureSeconds: header.healthyExposureSeconds,
            decoderGeneration: header.decoderGeneration,
            socketGeneration: header.socketGeneration,
            testSource: header.resolvedTestSource.rawValue,
            buildIdentity: header.resolvedBuildIdentity,
            trigger: own.lazy.compactMap(\.reason).first ?? "none",
            recoveredBy: header.outcome == .recovered ? own.last?.action ?? "none" : "none")
    }
}
