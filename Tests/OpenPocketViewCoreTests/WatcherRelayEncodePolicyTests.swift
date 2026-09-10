import Testing

@testable import OpenPocketViewCore

struct WatcherRelayEncodePolicyTests {
    @Test func repeatedWatcherRequestsRespectKeyframeCooldown() {
        var policy = WatcherRelayEncodePolicy()
        let forced = (0..<100).filter { tick in
            policy.forceKeyframe(requested: true, now: Double(tick) / 25)
        }
        #expect(forced == [0, 25, 50, 75])
    }

    @Test func slowEncoderHasTwoSlotsAndCannotBorrowExtraCapacity() {
        var policy = WatcherRelayEncodePolicy()
        #expect(policy.admit() == true)
        #expect(policy.admit() == true)
        for _ in 0..<1_000 { #expect(policy.admit() == false) }
        #expect(policy.inFlight == 2)
        policy.complete()
        #expect(policy.admit() == true)
        for _ in 0..<10 { policy.complete() }
        #expect(policy.inFlight == 0)
        #expect(policy.admit() == true)
        #expect(policy.admit() == true)
        #expect(policy.admit() == false)
    }
}
