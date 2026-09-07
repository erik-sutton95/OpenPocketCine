import Foundation

/// Shared encode ladder. Operator Broadcast priority is `ceilingIndex` (0 = highest quality).
public struct WatcherRelayBitrate: Equatable, Sendable {
    public static let ladder = [10_000_000, 7_000_000, 4_500_000, 3_000_000]
    public static let stepDownSaturation = 0.3
    public static let stepUpSaturation = 0.05
    public static let windowSeconds: TimeInterval = 5
    public static let stepUpAfterCleanSeconds: TimeInterval = 30

    public var ceilingIndex: Int
    public private(set) var rungIndex: Int
    private var windowStartedAt: TimeInterval
    private var ticksInWindow = 0
    private var saturatedTicksInWindow = 0
    private var previousTickSaturated = false
    private var cleanSince: TimeInterval

    public init(ceilingIndex: Int = 0, now: TimeInterval = 0) {
        self.ceilingIndex = Self.clamp(ceilingIndex)
        self.rungIndex = self.ceilingIndex
        self.windowStartedAt = now
        self.cleanSince = now
    }

    public var bitsPerSecond: Int {
        let i = max(rungIndex, ceilingIndex)
        return Self.ladder[min(i, Self.ladder.count - 1)]
    }

    public static func shouldSkipEncode(allPeersSaturated: Bool) -> Bool {
        allPeersSaturated
    }

    public mutating func recordTick(saturated: Bool, cameraStarving: Bool, now: TimeInterval)
        -> Int?
    {
        let full = saturated || cameraStarving
        ticksInWindow += 1
        if full && previousTickSaturated { saturatedTicksInWindow += 1 }
        previousTickSaturated = full
        guard now - windowStartedAt >= Self.windowSeconds, ticksInWindow > 0 else { return nil }

        let saturation = Double(saturatedTicksInWindow) / Double(ticksInWindow)
        ticksInWindow = 0
        saturatedTicksInWindow = 0
        windowStartedAt = now
        ceilingIndex = Self.clamp(ceilingIndex)

        if saturation > Self.stepDownSaturation {
            cleanSince = now
            if rungIndex < Self.ladder.count - 1 {
                rungIndex += 1
                return bitsPerSecond
            }
            return nil
        }
        if saturation > Self.stepUpSaturation {
            cleanSince = now
            return nil
        }
        if rungIndex > ceilingIndex, now - cleanSince >= Self.stepUpAfterCleanSeconds {
            rungIndex -= 1
            cleanSince = now
            return bitsPerSecond
        }
        return nil
    }

    private static func clamp(_ index: Int) -> Int {
        min(max(0, index), ladder.count - 1)
    }
}
