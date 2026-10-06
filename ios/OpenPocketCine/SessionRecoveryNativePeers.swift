#if DEBUG
import Foundation
import OpenCineDJIApple

/// Opt-in SIMULATED dependencies for tracing the actual recovery owner.
/// This supplies clocks, actual discovery/native boundaries and synthetic source facts, never
/// the recovery/connect workflow. Ordinary app composition continues to use its real owners.
@MainActor
struct SessionRecoveryNativePeers {
    struct Picture {
        var sourceAt: Date?
        var presentedAt: Date?
    }

    var now: () -> ContinuousClock.Instant
    var wallNow: () -> Date
    var uptime: () -> TimeInterval
    var sleep: @Sendable (Duration) async throws -> Void
    var jitter: () -> Double
    var waitUntilPoweredOn: () async -> Bool
    var scan: () -> AsyncStream<DjiAppleSighting>
    var stopScan: () -> Void
    var picture: () -> Picture
    var disposeEndpoint: () -> Void
}
#endif
