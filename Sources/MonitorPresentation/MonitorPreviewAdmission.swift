import Foundation

/// One preview job across changing inspectors. The native owner supplies a
/// monotonic clock and serialization; this policy retains no image or task.
public struct MonitorPreviewAdmission: Sendable {
    public struct Ticket: Equatable, Sendable {
        fileprivate let owner: UUID
        fileprivate let epoch: UInt64
        fileprivate let serial: UInt64
    }

    public static let minimumIntervalNanoseconds: UInt64 = 200_000_000

    private var owner: UUID?
    private var epoch: UInt64 = 0
    private var serial: UInt64 = 0
    private var busy: Ticket?
    private var lastAdmission: UInt64?

    public init() {}

    public mutating func activate(owner: UUID) {
        self.owner = owner
        epoch &+= 1
    }

    /// Source or option changes invalidate adoption, never the occupied slot.
    public mutating func invalidate(owner: UUID) {
        guard self.owner == owner else { return }
        epoch &+= 1
    }

    public mutating func deactivate(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        epoch &+= 1
    }

    /// Drops busy/early requests. Switching owners cannot reset the cadence or
    /// enqueue a second job behind a cancelled operation that is still running.
    public mutating func acquire(
        owner: UUID, nowNanoseconds: UInt64,
        minimumIntervalNanoseconds: UInt64 = Self.minimumIntervalNanoseconds
    ) -> Ticket? {
        guard self.owner == owner, busy == nil else { return nil }
        if let lastAdmission {
            guard nowNanoseconds >= lastAdmission,
                nowNanoseconds - lastAdmission >= minimumIntervalNanoseconds
            else { return nil }
        }
        serial &+= 1
        let ticket = Ticket(owner: owner, epoch: epoch, serial: serial)
        busy = ticket
        lastAdmission = nowNanoseconds
        return ticket
    }

    public func isCurrent(_ ticket: Ticket) -> Bool {
        owner == ticket.owner && epoch == ticket.epoch && serial == ticket.serial
    }

    /// Call only after native work and its pending delivery/discard finish.
    /// A late completion cannot clear a newer job, even within the same epoch.
    public mutating func complete(_ ticket: Ticket) {
        if busy == ticket { busy = nil }
    }
}
