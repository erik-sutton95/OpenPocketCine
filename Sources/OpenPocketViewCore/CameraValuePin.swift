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
    ///
    /// `confirms` decides when the body has answered the ask. Exact equality
    /// suits the enum-shaped controls; zoom hands in `CamFov.matches`, because
    /// its live factor is derived from a lens position and lands a hair off the
    /// number that was asked for.
    public static func reconcile(
        _ pin: inout Self?, reported: Value?, now: TimeInterval,
        confirms: (Value, Value) -> Bool = { $0 == $1 }
    ) -> Value? {
        guard let current = pin else { return nil }
        let answered = reported.map { confirms($0, current.expected) } ?? false
        guard now < current.deadline, !answered else {
            pin = nil
            return nil
        }
        return current.expected
    }
}
