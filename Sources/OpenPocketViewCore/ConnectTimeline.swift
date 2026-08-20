import Foundation

/// Monotonic connect-path marks from a recorded t0.
///
/// `line()` is `connect:` with no marks, otherwise
/// `connect: gatt=0.40s pair=1.10s path=3.20s` in insertion order.
public struct ConnectTimeline: Sendable {
    private let t0: TimeInterval
    private var marks: [(name: String, at: TimeInterval)] = []

    public init(now: TimeInterval) {
        t0 = now
    }

    public mutating func mark(_ name: String, now: TimeInterval) {
        marks.append((name, now))
    }

    public func line() -> String {
        if marks.isEmpty { return "connect:" }
        let body = marks.map { mark in
            "\(mark.name)=\(String(format: "%.2f", mark.at - t0))s"
        }.joined(separator: " ")
        return "connect: \(body)"
    }
}
