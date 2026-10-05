import Testing

@testable import OpenPocketViewCore

@Suite("DjiReconnectBackoff")
struct ReconnectBackoffTests {
    /// Base 0.5 s doubling to a 30 s cap, spread +/-30% by jitter; negative attempts are the first.
    @Test(arguments: [
        (0, 0.5, 0.5), (1, 0.5, 1.0), (2, 0.5, 2.0), (3, 0.5, 4.0), (20, 0.5, 30.0),
        (3, 0.0, 2.8), (3, 1.0, 5.2), (20, 1.0, 30.0), (-3, 0.5, 0.5),
    ])
    func delayGrowsClampsAndJitters(attempt: Int, jitter: Double, expected: Double) {
        let backoff = DjiReconnectBackoff(
            baseSeconds: 0.5, maxSeconds: 30, multiplier: 2, jitterFraction: 0.3)
        #expect(abs(backoff.delaySeconds(forAttempt: attempt, jitter: jitter) - expected) < 1e-9)
    }

    @Test func jitterSampleIsClampedToUnitRange() {
        let backoff = DjiReconnectBackoff(
            baseSeconds: 1, maxSeconds: 30, multiplier: 2, jitterFraction: 0.5)
        #expect(
            backoff.delaySeconds(forAttempt: 0, jitter: -1)
                == backoff.delaySeconds(forAttempt: 0, jitter: 0))
        #expect(
            backoff.delaySeconds(forAttempt: 0, jitter: 2)
                == backoff.delaySeconds(forAttempt: 0, jitter: 1))
    }

    @Test func legacyStandaloneAndMonitorDefaultsRemainCompatible() {
        var backoff = DjiReconnectBackoff()
        #expect(backoff.maxSeconds == 30)
        #expect(backoff.delaySeconds(forAttempt: 20, jitter: 0.5) == 30)
        #expect(SessionRecoveryPolicy.monitor.backoff.maxSeconds == 8)
        #expect(
            SessionRecoveryPolicy.monitor.decision(afterFailedAttempts: 7, jitter: 1)
                == .retry(afterSeconds: 8))
        backoff.baseSeconds = 2
        backoff.maxSeconds = 20
        backoff.multiplier = 3
        backoff.jitterFraction = 0
        #expect(backoff.delaySeconds(forAttempt: 1, jitter: 1) == 6)
    }
}
