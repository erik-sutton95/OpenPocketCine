import Foundation

/// Constant-space timing counters. Callers supply one monotonic clock and publish
/// windows at a low rate; no per-frame logging or retained timestamp arrays.
public struct DeliveryCadence: Sendable {
    public struct Window: Sendable {
        public let events: Int
        public let hertz: Double
        public let maximumGapMilliseconds: Double
    }

    private var startedAt: TimeInterval
    private var lastEventAt: TimeInterval?
    private var count = 0
    private var maximumGap: TimeInterval = 0

    public init(startedAt: TimeInterval) {
        self.startedAt = startedAt.isFinite ? startedAt : 0
    }

    public mutating func note(at now: TimeInterval) {
        guard now.isFinite, now >= startedAt else { return }
        if let lastEventAt {
            guard now >= lastEventAt else { return }
            maximumGap = max(maximumGap, now - lastEventAt)
        } else {
            maximumGap = max(maximumGap, now - startedAt)
        }
        lastEventAt = now
        count += 1
    }

    public mutating func takeWindow(at now: TimeInterval) -> Window? {
        guard now.isFinite, now > startedAt,
            lastEventAt.map({ now >= $0 }) ?? true
        else { return nil }
        let elapsed = now - startedAt
        // Include silence at the end of a window, even when no event arrives.
        let gap = max(maximumGap, now - (lastEventAt ?? startedAt))
        let window = Window(
            events: count, hertz: Double(count) / elapsed,
            maximumGapMilliseconds: gap * 1_000)
        startedAt = now
        count = 0
        maximumGap = 0
        return window
    }
}
