import Testing

@testable import OpenPocketViewCore

@Suite("Session recovery policy")
struct SessionRecoveryPolicyTests {
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

    @Test func delayIsCapped() {
        let policy = SessionRecoveryPolicy.monitor
        guard case .retry(let seconds) = policy.decision(afterFailedAttempts: 7, jitter: 1) else {
            Issue.record("expected a retry before the attempt budget is spent")
            return
        }
        #expect(seconds <= policy.backoff.maxSeconds)
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

    @Test func recoveringFlag() {
        #expect(SessionRecoveryState.idle.isRecovering == false)
        #expect(SessionRecoveryState.retrying(attempt: 1, maxAttempts: 8).isRecovering)
        #expect(SessionRecoveryState.waitingForOperator(attemptsMade: 8).isRecovering)
        #expect(SessionRecoveryState.pausedAfterRepeatedDrops(drops: 3).isRecovering)
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
    @Test func retryingCopy() {
        let state = SessionRecoveryState.retrying(attempt: 3, maxAttempts: 8)
        #expect(SessionRecoveryCopy.title(state) == "Reconnecting…")
        let detail = SessionRecoveryCopy.detail(state, deviceName: "Pocket 4 Pro")
        #expect(detail.contains("Pocket 4 Pro"))
        #expect(detail.contains("attempt 3 of 8"))
        #expect(!detail.localizedCaseInsensitiveContains("Nikon"))
        #expect(!detail.localizedCaseInsensitiveContains("OpenZCine"))
    }

    @Test func exhaustedCopy() {
        let state = SessionRecoveryState.waitingForOperator(attemptsMade: 8)
        #expect(SessionRecoveryCopy.title(state) == "Camera disconnected")
        let detail = SessionRecoveryCopy.detail(state, deviceName: "Pocket 4 Pro")
        #expect(detail.contains("8 tries"))
        #expect(detail.contains("held, not live"))
    }

    @Test func stormPauseCopy() {
        let state = SessionRecoveryState.pausedAfterRepeatedDrops(drops: 3)
        #expect(SessionRecoveryCopy.title(state) == "Connection keeps dropping")
        let detail = SessionRecoveryCopy.detail(state, deviceName: "Pocket 4 Pro")
        #expect(detail.contains("3 times"))
        #expect(detail.contains("protect the camera"))
        #expect(detail.contains("held, not live"))
    }

    @Test func singleTryCopy() {
        let detail = SessionRecoveryCopy.detail(
            .waitingForOperator(attemptsMade: 1), deviceName: "Pocket 4 Pro")
        #expect(detail.contains("1 try"))
    }

    @Test func heldFrameBadge() {
        #expect(SessionRecoveryCopy.heldFrameBadge == "NO LINK")
    }
}
