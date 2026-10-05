import Foundation
import OpenCineMedia

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
        FeedIncidentExport.extras(from: loadAll(), product: "OpenPocketCine")
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
