import Foundation

/// Low-rate SoftAP-loss ownership; separate from encoder/decoder stall repair.
/// Shells supply monotonic time and route a confirmed loss to SessionRecovery.
public struct CameraPathRecovery: Sendable, Equatable {
    /// Matches Android CameraApJoiner's existing network reassociation grace.
    public static let reassociationGrace: TimeInterval = 8
    private var absentSince: TimeInterval?
    private var requestedRecovery = false

    public init() {}

    public mutating func reset() {
        absentSince = nil
        requestedRecovery = false
    }

    public mutating func tick(
        now: TimeInterval, pathReady: Bool, videoFresh: Bool,
        sessionActive: Bool, repairInFlight: Bool
    ) -> Bool {
        guard now.isFinite, sessionActive, !pathReady, !videoFresh else {
            reset()
            return false
        }
        if now < (absentSince ?? now) { reset() }
        if absentSince == nil { absentSince = now }
        guard !repairInFlight, !requestedRecovery,
            let absentSince, now - absentSince >= Self.reassociationGrace
        else { return false }
        requestedRecovery = true
        return true
    }
}
