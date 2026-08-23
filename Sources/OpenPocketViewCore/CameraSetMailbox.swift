import Foundation

/// Latest-wins SET mailbox and ACK gate for live camera control.
///
/// One generation on the wire per opcode, except `0x02/0xB8` which pipelines at
/// 20 Hz without waiting for ACK (Mimo pinch). Slider / wheel scrubbing replaces
/// pending instead of enqueueing. After a UDP-dead stall, a late BLE ACK is
/// accepted only when its seq still belongs to the open generation; superseded
/// seqs drop. Live-control ACKs are never parked for hold-replay.
public struct CameraSetMailbox: Equatable, Sendable {
    /// Max SET rate for coalesced (slider / wheel) writes. Chip taps are urgent.
    public static let coalesceHold: TimeInterval = 0.1
    /// Mimo pinch is 20 Hz (`50 ms` between `0A 4E` sliders). Next slider
    /// launches on this cadence even if the previous ACK is still outstanding.
    public static let zoomCoalesceHold: TimeInterval = 0.05
    /// `0x02/0xB8` slider / pinch. Other sliders keep `coalesceHold`.
    public static let zoomOpcodeKey: UInt16 = Duml.opcodeKey(set: 0x02, cmd: 0xB8)

    public static func coalesceHold(for key: UInt16) -> TimeInterval {
        key == zoomOpcodeKey ? zoomCoalesceHold : coalesceHold
    }

    /// Pinch must track the fingers, not the ACK. Other opcodes stay one-in-flight.
    public static func pipelinesWhileOpen(_ key: UInt16) -> Bool {
        key == zoomOpcodeKey
    }

    public enum Offer: Equatable, Sendable {
        /// Caller should transmit now (idle, urgent, or late-window superseded).
        case launch
        /// Same opcode is busy or rate-limited; keep only this latest pending.
        case coalescePending
    }

    public enum Ack: Equatable, Sendable {
        case accept
        case acceptLate
        case dropSuperseded
        case dropUnknown
    }

    public enum Timeout: Equatable, Sendable {
        case subscribeMatches
        case waitLate
        case launchPending
        case idle
    }

    /// Only a timeout of the latest open SET (no subscribe match, no pending
    /// replacement) is uplink evidence. A superseded shutter / ISO wheel step
    /// is latest-wins, not a half-dead socket. Zoom sliders are fire-and-forget
    /// — a missing 0xB8 ACK is not a dead uplink.
    public static func timeoutImpliesUplinkFailure(_ result: Timeout, key: UInt16 = 0) -> Bool {
        result == .waitLate && !pipelinesWhileOpen(key)
    }

    public enum PendingLaunch: Equatable, Sendable {
        case immediate
        case afterHold
        case none
    }

    private struct Generation: Equatable, Sendable {
        var seqs: Set<UInt16> = []
        var awaitingLate = false
    }

    private var open: [UInt16: Generation] = [:]
    /// Pending latest-wins; `true` = chip / discrete, skip the coalesce hold.
    private var pending: [UInt16: Bool] = [:]
    private var superseded: [UInt16: Set<UInt16>] = [:]
    private var lastLaunch: [UInt16: TimeInterval] = [:]

    public init() {}

    public mutating func reset() {
        open.removeAll()
        pending.removeAll()
        superseded.removeAll()
        lastLaunch.removeAll()
    }

    public func hasOpen(_ key: UInt16) -> Bool { open[key] != nil }

    public func isAwaitingLate(_ key: UInt16) -> Bool { open[key]?.awaitingLate == true }

    public func holdRemaining(key: UInt16, now: TimeInterval) -> TimeInterval {
        guard let last = lastLaunch[key] else { return 0 }
        return max(0, Self.coalesceHold(for: key) - (now - last))
    }

    /// Queue or launch a SET. `urgent` is a chip tap / discrete write.
    /// Does not open a generation — `beginLaunch` / `noteTransmit` do that.
    public mutating func offer(key: UInt16, urgent: Bool, now: TimeInterval) -> Offer {
        if let gen = open[key], !gen.awaitingLate {
            if Self.pipelinesWhileOpen(key) {
                return offerPipelined(key: key, urgent: urgent, now: now)
            }
            pending[key] = (pending[key] ?? false) || urgent
            return .coalescePending
        }
        let rateLimited =
            !urgent
            && open[key] == nil
            && lastLaunch[key].map { now - $0 < Self.coalesceHold(for: key) } == true
        if rateLimited {
            pending[key] = (pending[key] ?? false) || urgent
            return .coalescePending
        }
        pending[key] = nil
        return .launch
    }

    /// Zoom: 20 Hz latest-wins on the wire. Do not sit on the open ACK.
    private mutating func offerPipelined(key: UInt16, urgent: Bool, now: TimeInterval) -> Offer {
        let held =
            !urgent
            && lastLaunch[key].map { now - $0 < Self.coalesceHold(for: key) } == true
        if held {
            pending[key] = (pending[key] ?? false) || urgent
            return .coalescePending
        }
        pending[key] = nil
        return .launch
    }

    /// Open a generation for a pending SET that is now going on the wire.
    public mutating func beginLaunch(key: UInt16, now: TimeInterval) {
        if open[key] != nil { supersedeOpen(key) }
        pending[key] = nil
        lastLaunch[key] = now
        open[key] = Generation()
    }

    public mutating func noteTransmit(key: UInt16, seq: UInt16) {
        if open[key] == nil { open[key] = Generation() }
        open[key]?.seqs.insert(seq)
        superseded[key]?.remove(seq)
    }

    /// Late BLE ACKs match seq+key. Only a newer SET for the same key supersedes.
    public mutating func decideAck(key: UInt16, seq: UInt16) -> Ack {
        if let gen = open[key] {
            let matches = gen.seqs.contains(seq)
            if matches {
                let late = gen.awaitingLate
                open[key] = nil
                return late ? .acceptLate : .accept
            }
            if superseded[key]?.contains(seq) == true {
                return .dropSuperseded
            }
            return .dropUnknown
        }
        if superseded[key]?.contains(seq) == true {
            return .dropSuperseded
        }
        return .dropUnknown
    }

    public mutating func timeout(key: UInt16, subscribeMatches: Bool) -> Timeout {
        guard open[key] != nil else { return .idle }
        if subscribeMatches {
            open[key] = nil
            return pending[key] != nil ? .launchPending : .subscribeMatches
        }
        if pending[key] != nil {
            supersedeOpen(key)
            return .launchPending
        }
        open[key]?.awaitingLate = true
        return .waitLate
    }

    public mutating func pendingLaunch(key: UInt16, now: TimeInterval) -> PendingLaunch {
        guard let urgent = pending[key] else { return .none }
        if urgent || holdRemaining(key: key, now: now) <= 0 {
            pending[key] = nil
            return .immediate
        }
        return .afterHold
    }

    private mutating func supersedeOpen(_ key: UInt16) {
        if let seqs = open[key]?.seqs, !seqs.isEmpty {
            var held = superseded[key] ?? []
            held.formUnion(seqs)
            if held.count > 64 {
                held = Set(held.sorted().suffix(32))
            }
            superseded[key] = held
        }
        open[key] = nil
    }
}
