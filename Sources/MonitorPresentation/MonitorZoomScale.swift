import Foundation

/// Presentation-only logarithmic lens ring. All limits and stops come from the
/// camera adapter; this type knows nothing about lenses or command encodings.
public struct MonitorZoomScale: Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double
    public static let angularSpan = 210.0 * Double.pi / 180
    public static let tickIncrement = 0.01
    /// Equal-angle minor ticks across the full ring. Hub still steps hundredths.
    public static let minorTickCount = 18
    public static let labeledTicks = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0]
    /// Integer majors the slow disc magnet can rest on. 1.5× is labeled, not whole.
    public static let wholeStops = [1.0, 2.0, 3.0, 4.0, 6.0, 9.0, 12.0]
    /// Max hundredths of travel in one pointer sample to count as "very slow".
    public static let slowSnapStep = 0.025
    /// Attract when this close to a whole stop.
    public static let slowSnapIn = 0.03
    /// Stay on a whole stop until the unconstrained value leaves this far.
    public static let slowSnapHold = 0.06

    public static func minorTickPositions() -> [Double] {
        (0...minorTickCount).map { Double($0) / Double(minorTickCount) }
    }

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

    public func dragged(from value: Double, angleDelta: Double, current: Double? = nil)
        -> Double
    {
        guard angleDelta.isFinite else { return quantized(self.value(at: position(value))) }
        let next = quantized(self.value(at: position(value) - angleDelta / Self.angularSpan))
        guard let current else { return next }
        return slowSnap(next, current: quantized(current))
    }

    /// Light magnet on 2× / 3× / 4× … only when the pointer is barely moving.
    public func slowSnap(_ next: Double, current: Double) -> Double {
        let here = quantized(current)
        let there = quantized(next)
        guard abs(there - here) <= Self.slowSnapStep else { return there }
        let stops = Self.wholeStops.filter { $0 >= minimum - 0.001 && $0 <= maximum + 0.001 }
        if let held = stops.first(where: { abs(here - $0) < Self.tickIncrement / 2 }) {
            return abs(there - held) < Self.slowSnapHold ? quantized(held) : there
        }
        if let stop = stops.first(where: { abs(there - $0) <= Self.slowSnapIn }) {
            return quantized(stop)
        }
        return there
    }

    public func quantized(_ value: Double) -> Double {
        guard value.isFinite else { return minimum }
        let clamped = min(maximum, max(minimum, value))
        let snapped = (clamped / Self.tickIncrement).rounded() * Self.tickIncrement
        return min(maximum, max(minimum, snapped))
    }

    public func dialLabel(_ value: Double) -> String {
        String(format: "%.2f×", quantized(value))
    }

    public func isLabeledTick(_ value: Double, marks: [Double] = Self.labeledTicks) -> Bool {
        let tick = quantized(value)
        return marks.contains { abs(quantized($0) - tick) < Self.tickIncrement / 2 }
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
