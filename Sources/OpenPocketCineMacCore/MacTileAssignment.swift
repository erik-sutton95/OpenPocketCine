import Foundation

/// Four stable Multiview slots. A camera occupies at most one slot, and a fifth camera is refused.
public struct MacTileBoard: Equatable, Sendable {
    public static let capacity = 4
    public private(set) var cameraIDs: [UUID?]

    public init(cameraIDs: [UUID?]? = nil) {
        let ids = cameraIDs ?? Array(repeating: nil, count: Self.capacity)
        precondition(ids.count == Self.capacity)
        self.cameraIDs = ids
    }

    public var firstEmptyIndex: Int? {
        cameraIDs.firstIndex { $0 == nil }
    }

    /// Assigns `id` to the first empty slot. Returns nil when the camera is already assigned or the board is full.
    public func adding(_ id: UUID) -> MacTileBoard? {
        guard !cameraIDs.contains(id), let index = firstEmptyIndex else { return nil }
        var next = self
        next.cameraIDs[index] = id
        return next
    }

    /// Clears one slot and leaves every other assignment where it is.
    public func removing(at index: Int) -> MacTileBoard {
        guard cameraIDs.indices.contains(index) else { return self }
        var next = self
        next.cameraIDs[index] = nil
        return next
    }
}
