import Foundation

/// A reversible selection sweep over the catalog's displayed order. Only newly
/// crossed indices change; selections outside the sweep retain their prior state.
public struct MonitorMediaDragSelection: Sendable {
    public private(set) var selectedIDs: Set<String>
    private let ids: [String]
    private let original: Set<String>
    private let origin: Int
    private let selects: Bool
    private var endpoint: Int

    public init?(orderedIDs: [String], originID: String, selectedIDs: Set<String>) {
        guard let index = orderedIDs.firstIndex(of: originID) else { return nil }
        ids = orderedIDs
        original = selectedIDs
        self.selectedIDs = selectedIDs
        origin = index
        endpoint = index
        selects = !selectedIDs.contains(originID)
        apply(index, sweeping: true)
    }

    /// Returns false when the pointer remains in the same item. Callers need not
    /// publish selection or rebuild a set on every pointer/display callback.
    @discardableResult public mutating func move(to index: Int) -> Bool {
        let next = min(ids.count - 1, max(0, index))
        guard next != endpoint else { return false }
        let oldLow = min(origin, endpoint)
        let oldHigh = max(origin, endpoint)
        let newLow = min(origin, next)
        let newHigh = max(origin, next)
        if oldLow < newLow {
            for i in oldLow..<newLow { apply(i, sweeping: false) }
        }
        if newHigh < oldHigh {
            for i in (newHigh + 1)...oldHigh { apply(i, sweeping: false) }
        }
        if newLow < oldLow {
            for i in newLow..<oldLow { apply(i, sweeping: true) }
        }
        if oldHigh < newHigh {
            for i in (oldHigh + 1)...newHigh { apply(i, sweeping: true) }
        }
        endpoint = next
        return true
    }

    private mutating func apply(_ index: Int, sweeping: Bool) {
        let id = ids[index]
        if sweeping ? selects : original.contains(id) {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }
}

/// Native scroll hosts integrate this velocity against their display clock.
public enum MonitorMediaSelectionScroll {
    public static func velocity(pointerY: Double, viewportHeight: Double) -> Double {
        guard pointerY.isFinite, viewportHeight.isFinite, viewportHeight > 0 else { return 0 }
        let edge = min(56, viewportHeight / 3)
        if pointerY < edge {
            let strength = min(1, max(0, (edge - pointerY) / edge))
            return -720 * strength * strength
        }
        if pointerY > viewportHeight - edge {
            let strength = min(1, max(0, (pointerY - viewportHeight + edge) / edge))
            return 720 * strength * strength
        }
        return 0
    }
}
