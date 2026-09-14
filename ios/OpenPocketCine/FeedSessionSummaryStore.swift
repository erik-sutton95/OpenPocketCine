import Foundation

/// Small, separate denominator records survive sessions without a dropout.
/// The incident runtime calls this only on its utility writer queue.
enum FeedSessionSummaryStore {
    private static func directory(_ root: URL) -> URL {
        root.appendingPathComponent("sessions", isDirectory: true)
    }

    static func persist(_ summary: FeedIncidentSessionSummary, root: URL, now: Date = Date()) {
        guard let id = UUID(uuidString: summary.sessionID),
            let data = try? FeedIncidentJSON.encoder().encode(summary), data.count <= 4_096
        else { return }
        let dir = directory(root)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("\(id.uuidString).json"), options: .atomic)
        let files = urls(root).sorted {
            modified($0) > modified($1)
        }
        for (index, url) in files.enumerated()
        where index >= 20 || now.timeIntervalSince(modified(url)) > 604_800 {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func load(root: URL) -> [FeedIncidentSessionSummary] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls(root).compactMap { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size <= 4_096, let data = try? Data(contentsOf: url)
            else { return nil }
            return try? decoder.decode(FeedIncidentSessionSummary.self, from: data)
        }
    }

    static func markInterrupted(root: URL) {
        for var summary in load(root: root) where summary.outcome == "live" {
            summary.outcome = "interrupted"
            persist(summary, root: root)
        }
    }

    static func deleteAll(root: URL) {
        try? FileManager.default.removeItem(at: directory(root))
    }

    private static func urls(_ root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: directory(root),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []).filter { $0.pathExtension == "json" }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }
}
