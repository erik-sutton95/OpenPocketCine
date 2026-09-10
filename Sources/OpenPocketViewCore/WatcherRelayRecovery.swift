import Foundation

/// Bounded watcher-only retries. Never asks the camera for a keyframe or a new session.
public struct WatcherRelayRecovery: Sendable {
    public enum Action: Equatable, Sendable { case none, reconnect, exhausted }
    public static let maximumRetries = 3
    public static let joinTimeout: TimeInterval = 15
    public static let silenceTimeout: TimeInterval = 5
    public private(set) var retryCount = 0
    public private(set) var retryAt: TimeInterval?
    private var deadline: TimeInterval?
    private var pictureDeadline: TimeInterval?
    private var lastPicture: TimeInterval?
    private var stableSince: TimeInterval?
    private var accepted = false
    private var stopped = false

    public init(now: TimeInterval) { deadline = now + Self.joinTimeout }

    public mutating func connected(now: TimeInterval) {
        accepted = true
        stableSince = nil
        lastPicture = nil
        pictureDeadline = now + 10
        deadline = now + Self.silenceTimeout
        retryAt = nil
    }

    public mutating func received(now: TimeInterval, picture: Bool = false) {
        guard accepted, !stopped, retryAt == nil else { return }
        deadline = now + Self.silenceTimeout
        if picture {
            if lastPicture == nil || now - (lastPicture ?? now) > 2 { stableSince = now }
            lastPicture = now
            pictureDeadline = now + Self.silenceTimeout
            if let stableSince, now - stableSince >= 10 { retryCount = 0 }
        }
    }

    public mutating func disconnected(now: TimeInterval) -> Action {
        guard !stopped else { return .none }
        guard retryAt == nil else { return .none }
        accepted = false
        stableSince = nil
        lastPicture = nil
        pictureDeadline = nil
        deadline = nil
        guard retryCount < Self.maximumRetries else {
            stopped = true
            return .exhausted
        }
        retryAt = now + [1.0, 2.0, 4.0][retryCount]
        retryCount += 1
        return .none
    }

    public mutating func tick(now: TimeInterval) -> Action {
        guard !stopped else { return .none }
        if let retryAt, now >= retryAt {
            self.retryAt = nil
            deadline = now + Self.joinTimeout
            return .reconnect
        }
        if let pictureDeadline, now >= pictureDeadline { return disconnected(now: now) }
        if let deadline, now >= deadline { return disconnected(now: now) }
        return .none
    }

    public mutating func stop() {
        stopped = true
        pictureDeadline = nil
        deadline = nil
        retryAt = nil
    }
}

/// Measures growth in delivery delay without assuming synchronized device clocks.
/// A reconnect starts a fresh baseline; this is not an absolute glass-to-glass latency meter.
public struct WatcherRelayFrameFreshness: Sendable {
    public static let maximumAddedDelay: TimeInterval = 0.75
    private var minimumOffset: TimeInterval?
    public init() {}
    public mutating func isFallingBehind(encodedAt: TimeInterval?, receivedAt: TimeInterval) -> Bool
    {
        guard let encodedAt, encodedAt.isFinite, receivedAt.isFinite else { return false }
        let offset = receivedAt - encodedAt
        minimumOffset = min(minimumOffset ?? offset, offset)
        return offset - (minimumOffset ?? offset) > Self.maximumAddedDelay
    }
}
