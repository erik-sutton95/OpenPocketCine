import Foundation

/// A bounded, latest-target mailbox for native gimbal control on the UDP queue.
/// Ownership prevents a late target/stop from affecting another controller.
public struct GimbalNativeTargetStream: Sendable {
    public private(set) var token: UInt64?
    private var pending: Duml.Frame?
    private var lastPayload: [UInt8]?
    private var submittedAt: TimeInterval = 0
    private var emittedAt: TimeInterval?

    public init() {}

    public mutating func begin(token: UInt64) {
        _ = cancel()
        self.token = token
    }

    @discardableResult
    public mutating func submit(_ frame: Duml.Frame, token: UInt64, now: TimeInterval) -> Bool {
        guard self.token == token, now.isFinite,
            frame.cmdSet == 4, frame.cmdId == 0x14, frame.payload.count == 8 else { return false }
        submittedAt = now
        guard frame.payload != lastPayload else { return true }
        lastPayload = frame.payload
        pending = frame
        return true
    }

    /// Returns one target at most; never replays a backlog after a scheduling gap.
    public mutating func next(now: TimeInterval, connectionReady: Bool = true) -> Duml.Frame? {
        guard token != nil, now.isFinite, let frame = pending else { return nil }
        guard now >= submittedAt, now - submittedAt <= 0.2 else {
            pending = nil
            lastPayload = nil
            return nil
        }
        guard connectionReady else { return nil }
        if let emittedAt, now - emittedAt < GimbalStick.streamInterval { return nil }
        pending = nil
        emittedAt = now
        return frame
    }

    /// A supplied stale token cannot cancel the current owner.
    @discardableResult
    public mutating func cancel(token: UInt64? = nil) -> Bool {
        if let token, self.token != token { return false }
        let wasActive = self.token != nil
        self.token = nil
        pending = nil
        lastPayload = nil
        emittedAt = nil
        return wasActive
    }
}
