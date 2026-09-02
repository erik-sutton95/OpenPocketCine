import Foundation

/// Whether an interrupted camera session is being recovered, and how the operator is told.
///
/// The monitor stays up on the last frame, automatic retries run bounded, and when the
/// budget is spent the operator — not the app — decides what happens next.
public enum SessionRecoveryState: Equatable, Sendable {
    case idle
    /// An automatic reconnect is running (or waiting out its backoff). `attempt` is 1-based.
    case retrying(attempt: Int, maxAttempts: Int)
    /// The automatic budget is spent. The operator chooses: retry, or leave the monitor.
    case waitingForOperator(attemptsMade: Int)
    /// Reconnects kept succeeding but the session kept dying young.
    case pausedAfterRepeatedDrops(drops: Int)

    public var isRecovering: Bool { self != .idle }
}

/// Cross-run damping for sessions that reconnect cleanly but keep dying.
public struct SessionDropStormGuard: Sendable, Equatable {
    private var dropTimesSeconds: [Double] = []

    public init() {}

    public static let windowSeconds: Double = 120
    public static let pauseAfterDrops = 3

    public mutating func noteDrop(now: Double) -> Bool {
        dropTimesSeconds.append(now)
        dropTimesSeconds.removeAll { now - $0 > Self.windowSeconds }
        return dropTimesSeconds.count >= Self.pauseAfterDrops
    }

    public var dropsInWindow: Int { dropTimesSeconds.count }

    public mutating func reset() { dropTimesSeconds.removeAll() }
}

public enum SessionRecoveryDecision: Equatable, Sendable {
    case retry(afterSeconds: Double)
    case stop
}

/// What started bounded session recovery. Feed stall / SET timeout / first
/// picture are `FeedWatchdog` — starting this on those GOP-cuts a live well.
public enum SessionRecoveryTrigger: Equatable, Sendable {
    case bleDropped
    case softAPLost
    /// The watchdog's last rung (new handshake) missed while SoftAP was still
    /// up. Without this the shell sat on a nil datalink in Reconnecting.
    case datalinkLost
    case operatorRetry
    case feedWatchdogStall
    case commandTimeout
    case firstPicture
}

/// Shared reconnect rule: when to retry a dropped camera session, how long to back off,
/// and when to stop and ask the operator.
public struct SessionRecoveryPolicy: Sendable, Equatable {
    public var backoff: ReconnectBackoff
    public var maxAutomaticAttempts: Int

    public init(
        backoff: ReconnectBackoff = ReconnectBackoff(baseSeconds: 0.5, maxSeconds: 8),
        maxAutomaticAttempts: Int = 8
    ) {
        self.backoff = backoff
        self.maxAutomaticAttempts = max(0, maxAutomaticAttempts)
    }

    /// Retry at once, then 0.5s → 8s jittered, giving up after 8 attempts.
    /// Long enough to ride out a camera power cycle; short enough that a
    /// camera that is gone stops burning the radio.
    public static let monitor = SessionRecoveryPolicy()

    public static func shouldBegin(_ trigger: SessionRecoveryTrigger) -> Bool {
        switch trigger {
        case .bleDropped, .softAPLost, .datalinkLost, .operatorRetry: true
        case .feedWatchdogStall, .commandTimeout, .firstPicture: false
        }
    }

    public func decision(afterFailedAttempts failures: Int, jitter: Double)
        -> SessionRecoveryDecision
    {
        let failed = max(0, failures)
        guard failed < maxAutomaticAttempts else { return .stop }
        guard failed > 0 else { return .retry(afterSeconds: 0) }
        return .retry(afterSeconds: backoff.delaySeconds(forAttempt: failed - 1, jitter: jitter))
    }

    public func state(afterFailedAttempts failures: Int) -> SessionRecoveryState {
        let failed = max(0, failures)
        guard failed < maxAutomaticAttempts else {
            return .waitingForOperator(attemptsMade: failed)
        }
        return .retrying(attempt: failed + 1, maxAttempts: maxAutomaticAttempts)
    }
}

/// Operator-facing recovery copy. Never names a sister app or another brand.
public enum SessionRecoveryCopy {
    public static func title(_ state: SessionRecoveryState) -> String {
        switch state {
        case .idle: return ""
        case .retrying: return "Reconnecting…"
        case .waitingForOperator: return "Camera disconnected"
        case .pausedAfterRepeatedDrops: return "Connection keeps dropping"
        }
    }

    public static func detail(_ state: SessionRecoveryState, deviceName: String) -> String {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let camera = name.isEmpty ? "The camera" : name
        switch state {
        case .idle:
            return ""
        case .retrying(let attempt, let maxAttempts):
            return
                "\(camera) dropped off. Holding the last frame — attempt \(attempt) of \(maxAttempts)."
        case .waitingForOperator(let attemptsMade):
            let tries = attemptsMade == 1 ? "1 try" : "\(attemptsMade) tries"
            return "\(camera) didn't come back after \(tries). The frame below is held, not live."
        case .pausedAfterRepeatedDrops(let drops):
            return
                "\(camera) reconnected but dropped \(drops) times in quick succession. Automatic retries are paused to protect the camera. The frame below is held, not live."
        }
    }

    public static let heldFrameBadge = "NO LINK"
}
