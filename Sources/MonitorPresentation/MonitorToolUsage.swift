import Foundation

/// Session-local usage for the collapsed assist palette. Enabling a tool is
/// independent of ranking it; only an explicit operator interaction adds use.
public struct MonitorToolUsage: Equatable, Sendable {
    private var counts: [String: Int] = [:]

    public init() {}

    /// The Field Monitor reference's starting preferences. Hosts inject this
    /// explicitly and can substitute a seed for a different tool inventory.
    public static let fieldMonitorSeed = [
        "PEAK": 6, "FALSE": 5, "ZEBRA": 4, "LUT": 4, "WAVE": 3,
        "GUIDES": 2, "GRID": 2, "HISTO": 2, "VECTOR": 1, "PARADE": 1,
        "LIGHTS": 1, "CROSS": 1, "MIRROR": 1, "AUDIO": 1,
    ]

    public mutating func recordUse(of id: String, seed: [String: Int] = [:]) {
        let previous = max(0, counts[id] ?? seed[id] ?? 0)
        counts[id] = previous == Int.max ? previous : previous + 1
    }

    /// Equal counts keep the catalog's declaration order. Removed tools and
    /// repeated IDs cannot occupy a quick slot; unseeded tools start at zero.
    public func rankedIDs(in catalog: [String], seed: [String: Int] = [:]) -> [String] {
        var seen: Set<String> = []
        return catalog.enumerated()
            .filter { seen.insert($0.element).inserted }
            .sorted { lhs, rhs in
                let left = counts[lhs.element] ?? seed[lhs.element] ?? 0
                let right = counts[rhs.element] ?? seed[rhs.element] ?? 0
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
    }
}
