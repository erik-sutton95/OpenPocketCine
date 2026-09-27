import Testing

@testable import OpenPocketViewCore

@Suite("Session recovery policy")
struct SessionRecoveryPolicyTests {
    @Test func successRequiresNewSourceAndNewPresentation() {
        for (source, present, expected) in [
            (nil, nil, false), (9.0, 12.0, false), (12.0, 9.0, false),
            (10.0, 12.0, false), (11.0, 11.5, true), (12.0, 12.0, true),
            (13.0, 12.0, false), (Double.nan, 12.0, false), (Double.infinity, 12.0, false),
        ] as [(Double?, Double?, Bool)] {
            #expect(
                SessionRecoveryPolicy.hasFreshPicture(
                    attemptStartedAt: 10, now: 12, lastSourceFrameAt: source,
                    lastPresentedAt: present) == expected)
        }
        #expect(
            !SessionRecoveryPolicy.hasFreshPicture(
                attemptStartedAt: 10, now: 15, lastSourceFrameAt: 11, lastPresentedAt: 15))
    }

    @Test func firstAttemptIsImmediate() {
        let policy = SessionRecoveryPolicy.monitor
        #expect(policy.decision(afterFailedAttempts: 0, jitter: 0.5) == .retry(afterSeconds: 0))
        #expect(policy.state(afterFailedAttempts: 0) == .retrying(attempt: 1, maxAttempts: 8))
    }

    @Test func laterAttemptsBackOff() {
        let policy = SessionRecoveryPolicy.monitor
        #expect(policy.decision(afterFailedAttempts: 1, jitter: 0.5) == .retry(afterSeconds: 0.5))
        #expect(policy.decision(afterFailedAttempts: 2, jitter: 0.5) == .retry(afterSeconds: 1))
        #expect(policy.decision(afterFailedAttempts: 3, jitter: 0.5) == .retry(afterSeconds: 2))
        #expect(policy.decision(afterFailedAttempts: 4, jitter: 0.5) == .retry(afterSeconds: 4))
    }

    @Test func stopsAtBudget() {
        let policy = SessionRecoveryPolicy.monitor
        #expect(policy.decision(afterFailedAttempts: 7, jitter: 0.5) != .stop)
        #expect(policy.decision(afterFailedAttempts: 8, jitter: 0.5) == .stop)
        #expect(policy.decision(afterFailedAttempts: 99, jitter: 0.5) == .stop)
        #expect(policy.state(afterFailedAttempts: 8) == .waitingForOperator(attemptsMade: 8))
    }

    @Test func zeroAttemptPolicyNeverRetries() {
        let policy = SessionRecoveryPolicy(maxAutomaticAttempts: 0)
        #expect(policy.decision(afterFailedAttempts: 0, jitter: 0.5) == .stop)
        #expect(policy.state(afterFailedAttempts: 0) == .waitingForOperator(attemptsMade: 0))
    }

    @Test func negativeFailuresClamp() {
        let policy = SessionRecoveryPolicy.monitor
        #expect(policy.decision(afterFailedAttempts: -3, jitter: 0.5) == .retry(afterSeconds: 0))
        #expect(policy.state(afterFailedAttempts: -3) == .retrying(attempt: 1, maxAttempts: 8))
    }

    @Test func onlyBleAndSoftAPStartSessionRecovery() {
        #expect(SessionRecoveryPolicy.shouldBegin(.bleDropped))
        #expect(SessionRecoveryPolicy.shouldBegin(.softAPLost))
        #expect(
            SessionRecoveryPolicy.shouldBegin(.datalinkLost),
            "watchdog rejoin missed its handshake — bounded recovery, not a nil datalink")
        #expect(SessionRecoveryPolicy.shouldBegin(.operatorRetry))
        #expect(!SessionRecoveryPolicy.shouldBegin(.feedWatchdogStall))
        #expect(!SessionRecoveryPolicy.shouldBegin(.commandTimeout))
        #expect(!SessionRecoveryPolicy.shouldBegin(.firstPicture))
    }
}

@Suite("Session drop storm guard")
struct SessionDropStormGuardTests {
    @Test func isolatedDropsPass() {
        var guardState = SessionDropStormGuard()
        let first = guardState.noteDrop(now: 0)
        let second = guardState.noteDrop(now: 10)
        #expect(first == false)
        #expect(second == false)
        #expect(guardState.dropsInWindow == 2)
    }

    @Test func clusteredDropsPause() {
        var guardState = SessionDropStormGuard()
        _ = guardState.noteDrop(now: 0)
        _ = guardState.noteDrop(now: 15)
        let paused = guardState.noteDrop(now: 30)
        #expect(paused)
        #expect(guardState.dropsInWindow == SessionDropStormGuard.pauseAfterDrops)
    }

    @Test func oldDropsAgeOut() {
        var guardState = SessionDropStormGuard()
        _ = guardState.noteDrop(now: 0)
        _ = guardState.noteDrop(now: 10)
        let paused = guardState.noteDrop(now: 10 + SessionDropStormGuard.windowSeconds + 1)
        #expect(paused == false)
        #expect(guardState.dropsInWindow == 1)
    }

    @Test func resetClearsLedger() {
        var guardState = SessionDropStormGuard()
        _ = guardState.noteDrop(now: 0)
        _ = guardState.noteDrop(now: 5)
        guardState.reset()
        #expect(guardState.dropsInWindow == 0)
        let paused = guardState.noteDrop(now: 6)
        #expect(paused == false)
    }
}

@Suite("Session recovery copy")
struct SessionRecoveryCopyTests {
    @Test(arguments: [
        (
            SessionRecoveryState.retrying(attempt: 3, maxAttempts: 8), "Reconnecting…",
            ["Pocket 4 Pro", "attempt 3 of 8"]
        ),
        (.waitingForOperator(attemptsMade: 8), "Camera disconnected", ["8 tries", "held, not live"]),
        (
            .pausedAfterRepeatedDrops(drops: 3), "Connection keeps dropping",
            ["3 times", "protect the camera", "held, not live"]
        ),
        (.waitingForOperator(attemptsMade: 1), "Camera disconnected", ["1 try"]),
    ])
    func copyNamesStateAndCount(state: SessionRecoveryState, title: String, phrases: [String]) {
        #expect(SessionRecoveryCopy.title(state) == title)
        let detail = SessionRecoveryCopy.detail(state, deviceName: "Pocket 4 Pro")
        for phrase in phrases {
            #expect(detail.contains(phrase))
        }
        #expect(!detail.localizedCaseInsensitiveContains("Nikon"))
        #expect(!detail.localizedCaseInsensitiveContains("OpenZCine"))
    }
}
