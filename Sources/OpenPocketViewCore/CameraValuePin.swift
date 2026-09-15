import Foundation

/// A requested camera value survives older telemetry for a bounded settle window.
/// `reported` must come from this frame, never from an optimistic merged status.
public struct CameraValuePin<Value: Equatable & Sendable>: Sendable {
    public let id = UUID()
    public let expected: Value
    public let deadline: TimeInterval

    public init(_ expected: Value, now: TimeInterval, settle: TimeInterval = 2) {
        self.expected = expected
        self.deadline = now + settle
    }

    /// Returns the held value, or releases the pin on confirmation/expiry.
    public static func reconcile(
        _ pin: inout Self?, reported: Value?, now: TimeInterval
    ) -> Value? {
        guard let current = pin else { return nil }
        guard now < current.deadline, reported != current.expected else {
            pin = nil
            return nil
        }
        return current.expected
    }
}
