import Foundation

/// Presentation-only logarithmic lens ring. All limits and stops come from the
/// camera adapter; this type knows nothing about lenses or command encodings.
public struct MonitorZoomScale: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public static let angularSpan = 210.0 * Double.pi / 180

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum.isFinite && minimum > 0 ? minimum : 1
        self.maximum = maximum.isFinite ? max(self.minimum, maximum) : self.minimum
    }

    public func position(_ value: Double) -> Double {
        guard maximum > minimum, value.isFinite else { return 0 }
        return log(min(maximum, max(minimum, value)) / minimum) / log(maximum / minimum)
    }

    public func value(at position: Double) -> Double {
        guard position.isFinite else { return minimum }
        return minimum * pow(maximum / minimum, min(1, max(0, position)))
    }

    public func dragged(from value: Double, angleDelta: Double) -> Double {
        guard angleDelta.isFinite else { return self.value(at: position(value)) }
        return self.value(at: position(value) - angleDelta / Self.angularSpan)
    }
}

/// One pointer lifetime owns one continuous-edit transaction. A changed viewport
/// or lens range cancels that lifetime; old pointer coordinates cannot restart it.
public struct MonitorZoomDrag: Equatable, Sendable {
    public private(set) var anchor: Double?
    private var cancelled = false

    public init() {}

    /// True only when a new edit transaction begins.
    public mutating func begin(at value: Double) -> Bool {
        guard !cancelled, anchor == nil, value.isFinite else { return false }
        anchor = value
        return true
    }

    /// End the current edit while rejecting updates until this pointer lifts.
    public mutating func cancel() -> Bool {
        let wasEditing = anchor != nil
        anchor = nil
        cancelled = true
        return wasEditing
    }

    /// UIKit may end or cancel a gesture. Both release its editing ownership.
    public mutating func end() -> Bool {
        let wasEditing = anchor != nil
        anchor = nil
        cancelled = false
        return wasEditing
    }
}
