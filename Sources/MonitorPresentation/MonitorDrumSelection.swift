import Foundation

/// Pure gesture geometry; camera settings are committed by the host only after
/// the drag ends. Fractional detents are visual feedback, never transport writes.
public enum MonitorDrumSelection {
    public static let pointsPerValue: Double = 56

    public static func position(origin: Int, translation: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let maximum = Double(count - 1)
        let raw = Double(origin) - (translation.isFinite ? translation : 0) / pointsPerValue
        let clamped = min(maximum, max(0, raw))
        return clamped - 0.55 * sin(2 * .pi * clamped) / (2 * .pi)
    }

    public static func settledIndex(origin: Int, translation: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(
            count - 1,
            max(0, Int(position(origin: origin, translation: translation, count: count).rounded())))
    }

    /// A drag commits only after crossing a detent. The visual origin may be a
    /// fallback for unknown camera state; resting there never selects it.
    /// Explicit taps and accessibility adjustments bypass this drag policy.
    public static func changedIndex(origin: Int, translation: Double, count: Int) -> Int? {
        guard let index = settledIndex(origin: origin, translation: translation, count: count),
            index != min(max(0, count - 1), max(0, origin))
        else { return nil }
        return index
    }
}

/// The source and layout context at pointer-down own the whole gesture. Hosts
/// supply a live identity so invalidation is checked even before UI redraw.
public struct MonitorDrumDrag<Identity: Equatable>: Equatable {
    public private(set) var origin: String?
    private var identity: Identity?
    private var cancelled = false

    public init() {}

    public mutating func begin(selection: String, identity: Identity) -> Bool {
        guard !cancelled else { return false }
        if origin != nil {
            guard self.identity == identity else {
                cancel(pointerIsActive: true)
                return false
            }
        } else {
            origin = selection
            self.identity = identity
        }
        return true
    }

    public mutating func end(identity: Identity) -> String? {
        let result = !cancelled && self.identity == identity ? origin : nil
        reset()
        return result
    }

    public mutating func cancel(pointerIsActive: Bool) {
        origin = nil
        identity = nil
        cancelled = pointerIsActive
    }

    public mutating func reset() {
        origin = nil
        identity = nil
        cancelled = false
    }
}

extension MonitorDrumDrag: Sendable where Identity: Sendable {}
