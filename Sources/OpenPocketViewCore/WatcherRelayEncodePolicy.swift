import Foundation

/// Bounded encode admission, adapted from OpenZCine's RelayEncodeLane.
/// Dropping before encode preserves the reference chain; dropping after encode requires an IDR.
public struct WatcherRelayEncodePolicy: Sendable {
    public private(set) var inFlight = 0
    public static let capacity = 2
    private var lastKeyAt: TimeInterval = -.infinity

    public init() {}

    public mutating func admit() -> Bool {
        guard inFlight < Self.capacity else { return false }
        inFlight += 1
        return true
    }

    public mutating func complete() { inFlight = max(0, inFlight - 1) }

    /// A peer's repeated request must never reset this cooldown.
    public mutating func forceKeyframe(requested: Bool, now: TimeInterval) -> Bool {
        guard requested, now - lastKeyAt >= 1 else { return false }
        lastKeyAt = now
        return true
    }
}
