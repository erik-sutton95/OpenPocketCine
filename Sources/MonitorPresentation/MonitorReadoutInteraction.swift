import Foundation

/// Pointer policy for a capture readout. It owns no camera values or timers;
/// the native gesture supplies movement and the 280 ms hold event.
public struct MonitorReadoutInteraction: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, pressing, drumming, cancelled }
    public enum Outcome: Equatable, Sendable {
        case tap
        case commit(translation: Double)
        case cancelled
    }
    public static let holdMilliseconds = 280
    public static let dragThreshold: Double = 14
    public static let tapSlop: Double = 8
    public private(set) var phase: Phase = .idle
    public private(set) var translation: Double = 0
    private var x: Double = 0
    private var y: Double = 0
    private var origin: Double = 0

    public init() {}

    public mutating func begin() {
        phase = .pressing
        x = 0
        y = 0
        origin = 0
        translation = 0
    }

    /// Returns true exactly when movement first opens the temporary drum. That
    /// first 14 pt arms it; subsequent travel starts from the newly seated value.
    @discardableResult public mutating func move(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite else {
            cancel()
            return false
        }
        self.x = x
        self.y = y
        if phase == .pressing {
            if abs(y) > Self.dragThreshold && abs(y) > abs(x) {
                cancel()
                return false
            }
            if abs(x) > Self.dragThreshold {
                phase = .drumming
                origin = x
                translation = 0
                return true
            }
        } else if phase == .drumming {
            translation = x - origin
        }
        return false
    }

    @discardableResult public mutating func hold() -> Bool {
        guard phase == .pressing else { return false }
        phase = .drumming
        translation = x
        return true
    }

    public mutating func end() -> Outcome {
        let outcome: Outcome
        switch phase {
        case .pressing:
            outcome = abs(x) <= Self.tapSlop && abs(y) <= Self.tapSlop ? .tap : .cancelled
        case .drumming: outcome = .commit(translation: translation)
        case .idle, .cancelled: outcome = .cancelled
        }
        phase = .idle
        return outcome
    }

    public mutating func cancel() {
        phase = .cancelled
        translation = 0
    }
}
