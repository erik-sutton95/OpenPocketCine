import Testing

@testable import OpenPocketViewCore

struct WatcherRelayRecoveryTests {
    @Test func joiningAndRetriesHaveFiniteDeadlines() {
        var policy = WatcherRelayRecovery(now: 0)
        #expect(policy.tick(now: 14) == .none)
        #expect(policy.tick(now: 15) == .none)
        #expect(policy.retryCount == 1)
        #expect(policy.tick(now: 16) == .reconnect)
        #expect(policy.tick(now: 31) == .none)
        #expect(policy.tick(now: 33) == .reconnect)
        #expect(policy.tick(now: 48) == .none)
        #expect(policy.tick(now: 52) == .reconnect)
        #expect(policy.tick(now: 67) == .exhausted)
        #expect(policy.tick(now: 100) == .none)
    }
    @Test func telemetryCannotHidePictureStall() {
        var policy = WatcherRelayRecovery(now: 0)
        policy.connected(now: 1)
        for time in 2...11 { policy.received(now: Double(time)) }
        #expect(policy.tick(now: 11) == .none)
        #expect(policy.retryCount == 1)
        #expect(policy.tick(now: 12) == .reconnect)
    }
    @Test func retryBudgetRequiresContinuousPictures() {
        var policy = WatcherRelayRecovery(now: 0)
        _ = policy.disconnected(now: 0)
        #expect(policy.tick(now: 1) == .reconnect)
        policy.connected(now: 1)
        policy.received(now: 11, picture: true)
        #expect(policy.retryCount == 1)
        for time in 12...21 { policy.received(now: Double(time), picture: true) }
        #expect(policy.retryCount == 0)
    }
    @Test func repeatedCallbacksDoNotMultiplyRetriesAndLeaveCancelsThem() {
        var policy = WatcherRelayRecovery(now: 0)
        _ = policy.disconnected(now: 1)
        _ = policy.disconnected(now: 1.1)
        #expect(policy.retryCount == 1)
        policy.stop()
        #expect(policy.tick(now: 50) == .none)
    }
    @Test func shortHandshakesDoNotResetRetryBudget() {
        var policy = WatcherRelayRecovery(now: 0)
        for index in 1...3 {
            let now = Double(index * 10)
            _ = policy.disconnected(now: now)
            #expect(policy.tick(now: now + 4) == .reconnect)
            policy.connected(now: now + 4)
            policy.received(now: now + 5, picture: true)
            #expect(policy.retryCount == index)
        }
        #expect(policy.disconnected(now: 40) == .exhausted)
    }
}

extension WatcherRelayRecoveryTests {
    @Test func growingBacklogIsDetectedWithUnrelatedMonotonicClocks() {
        var freshness = WatcherRelayFrameFreshness()
        #expect({ !freshness.isFallingBehind(encodedAt: 10000, receivedAt: 20) }())
        #expect({ !freshness.isFallingBehind(encodedAt: 10001, receivedAt: 21.1) }())
        #expect({ freshness.isFallingBehind(encodedAt: 10002, receivedAt: 22.8) }())
        #expect({ !freshness.isFallingBehind(encodedAt: nil, receivedAt: 30) }())
    }
    @Test func fasterDeliveryUpdatesTheBaseline() {
        var freshness = WatcherRelayFrameFreshness()
        #expect({ !freshness.isFallingBehind(encodedAt: 1, receivedAt: 21) }())
        #expect({ !freshness.isFallingBehind(encodedAt: 2, receivedAt: 21.5) }())
        #expect({ freshness.isFallingBehind(encodedAt: 3, receivedAt: 23.3) }())
    }
}
