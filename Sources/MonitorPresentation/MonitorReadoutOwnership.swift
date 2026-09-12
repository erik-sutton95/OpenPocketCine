import Foundation

/// A capture strip admits one pointer before its hold delay reveals a drum.
/// Releasing an old pointer cannot clear a newer reservation, and a new touch
/// invalidates any previous pointer's deferred command intent.
public struct MonitorReadoutOwnership: Equatable, Sendable {
    public private(set) var owner: UUID?
    private var revision: UInt64 = 0

    public init() {}

    public mutating func acquire(_ identity: UUID) -> UInt64? {
        guard owner == nil else { return nil }
        revision &+= 1
        owner = identity
        return revision
    }

    public func owns(_ identity: UUID) -> Bool { owner == identity }

    public mutating func release(_ identity: UUID) {
        if owner == identity { owner = nil }
    }

    public func permitsDeferredCommit(_ capturedRevision: UInt64) -> Bool {
        owner == nil && revision == capturedRevision
    }
}
