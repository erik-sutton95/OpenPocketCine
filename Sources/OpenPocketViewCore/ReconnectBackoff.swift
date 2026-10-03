import Foundation
import OpenCineCore

/// Jittered exponential backoff for reconnect retries. OpenZCine `ReconnectBackoff`.
public struct ReconnectBackoff: Sendable, Equatable {
    public var baseSeconds: Double
    public var maxSeconds: Double
    public var multiplier: Double
    public var jitterFraction: Double

    public init(
        baseSeconds: Double = 0.5,
        maxSeconds: Double = 30,
        multiplier: Double = 2,
        jitterFraction: Double = 0.3
    ) {
        self.baseSeconds = baseSeconds
        self.maxSeconds = maxSeconds
        self.multiplier = multiplier
        self.jitterFraction = jitterFraction
    }

    public func delaySeconds(forAttempt attempt: Int, jitter: Double) -> Double {
        RetryBackoff(
            initialDelay: baseSeconds, maximumDelay: maxSeconds,
            multiplier: multiplier, jitterFraction: jitterFraction
        ).delay(forAttempt: attempt, jitter: jitter)
    }
}
