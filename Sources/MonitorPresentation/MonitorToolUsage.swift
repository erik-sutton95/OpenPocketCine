import Foundation

/// Frecency ranking for collapsed View Assist favorites (frequency × recency).
/// Same family as Firefox/VS Code: exponential decay with a 36-hour half-life.
/// Empty stores fall back to `fieldMonitorSeed`. Persisted by the shell.
public struct MonitorToolUsage: Equatable, Sendable, Codable {
    public var scores: [String: Double]
    public var counts: [String: Int]
    public var lastUsed: [String: Double]
    public var clock: Double

    /// Half-life of a use, in seconds. A tool used once 36 hours ago scores half.
    public static let halfLife: Double = 36 * 3_600

    public init(
        scores: [String: Double] = [:], counts: [String: Int] = [:],
        lastUsed: [String: Double] = [:], clock: Double = 0
    ) {
        self.scores = scores
        self.counts = counts
        self.lastUsed = lastUsed
        self.clock = clock
    }

    /// First-run collapsed order before the operator has used anything.
    public static let fieldMonitorSeed = [
        "PEAK": 6, "FALSE": 5, "ZEBRA": 4, "LUT": 4, "WAVE": 3,
        "GUIDES": 2, "GRID": 2, "HISTO": 2, "VECTOR": 1, "PARADE": 1,
        "LIGHTS": 1, "CROSS": 1, "MIRROR": 1, "AUDIO": 1,
    ]

    public mutating func recordUse(
        of id: String, seed: [String: Int] = [:], at now: Double = Date().timeIntervalSince1970
    ) {
        _ = seed
        decay(to: now)
        scores[id] = (scores[id] ?? 0) + 1
        let previous = counts[id] ?? 0
        counts[id] = previous == Int.max ? previous : previous + 1
        lastUsed[id] = now
    }

    public mutating func decay(to now: Double) {
        guard now.isFinite else { return }
        if clock <= 0 {
            clock = now
            return
        }
        guard now > clock else { return }
        let factor = pow(0.5, (now - clock) / Self.halfLife)
        if factor < 1 {
            for key in scores.keys { scores[key] = (scores[key] ?? 0) * factor }
        }
        clock = now
    }

    /// Equal scores keep the catalog's declaration order. Removed tools and
    /// repeated IDs cannot occupy a quick slot.
    public func rankedIDs(
        in catalog: [String], seed: [String: Int] = [:],
        now: Double = Date().timeIntervalSince1970
    ) -> [String] {
        var snapshot = self
        snapshot.decay(to: now)
        var seen: Set<String> = []
        let unique = catalog.enumerated().filter { seen.insert($0.element).inserted }
        if snapshot.counts.isEmpty {
            return unique.sorted { lhs, rhs in
                let left = seed[lhs.element] ?? 0
                let right = seed[rhs.element] ?? 0
                return left == right ? lhs.offset < rhs.offset : left > right
            }.map(\.element)
        }
        return unique.sorted { lhs, rhs in
            let ls = snapshot.scores[lhs.element] ?? 0
            let rs = snapshot.scores[rhs.element] ?? 0
            if abs(ls - rs) > 1e-9 { return ls > rs }
            let lt = snapshot.lastUsed[lhs.element] ?? 0
            let rt = snapshot.lastUsed[rhs.element] ?? 0
            if lt != rt { return lt > rt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
