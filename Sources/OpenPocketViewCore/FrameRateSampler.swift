import Foundation

/// Rolling measurement of live-view frame delivery rate.
///
/// Copied from OpenZCine `Sources/OpenZCineCore/FrameRateSampler.swift`. Records frame
/// timestamps and derives an average inter-frame interval over a sliding window. The
/// *displayed* rate is additionally throttled to refresh about once per second, so the
/// top-bar readout reads steadily instead of flickering at the video frame rate.
/// Timestamps are abstract `Double` seconds (from `CACurrentMediaTime` /
/// `Date.timeIntervalSinceReferenceDate`) so the sampler is fully testable without a
/// live camera.
public struct FrameRateSampler: Sendable {
    private let windowSize: Int
    private let displayInterval: Double
    private var intervals: [Double] = []
    private var lastTimestamp: Double?
    private var lastDisplayTimestamp: Double?
    private var displayedFPS: Double = 0

    /// Creates a sampler.
    /// - Parameters:
    ///   - windowSize: Number of inter-frame intervals to average (default 30 ≈ one second of
    ///     frames at typical live-view rates).
    ///   - displayRefreshInterval: Minimum seconds between updates to the *displayed* rate
    ///     (default 1.0). The rolling average keeps tracking every frame; only the readout is
    ///     throttled, which is the standard way to keep an FPS counter legible.
    public init(windowSize: Int = 30, displayRefreshInterval: Double = 1.0) {
        self.windowSize = max(1, windowSize)
        self.displayInterval = max(0, displayRefreshInterval)
    }

    /// Records a frame at the given timestamp. Non-monotonic or zero-delta timestamps are ignored
    /// so a stale or reordered frame can't corrupt the rate or divide by zero.
    public mutating func recordFrame(at timestamp: Double) {
        guard timestamp.isFinite else { return }
        if let previous = lastTimestamp, timestamp <= previous { return }
        defer { lastTimestamp = timestamp }
        guard let previous = lastTimestamp else { return }
        intervals.append(timestamp - previous)
        if intervals.count > windowSize { intervals.removeFirst() }
        // Republish the readout at a steady cadence (≈ once per second), not every frame, so the
        // value is legible. The first interval publishes immediately so a rate appears at once.
        if let last = lastDisplayTimestamp, timestamp - last < displayInterval { return }
        displayedFPS = currentFPS
        lastDisplayTimestamp = timestamp
    }

    /// Publish silence from the existing HUD timer even when no frame arrives.
    /// Clear the old window so resumed delivery is measured from the new run.
    public mutating func age(at timestamp: Double, staleAfter: Double = 2) {
        guard timestamp.isFinite, let lastTimestamp,
            timestamp - lastTimestamp >= staleAfter
        else { return }
        displayedFPS = 0
        intervals.removeAll(keepingCapacity: true)
        self.lastTimestamp = nil
        lastDisplayTimestamp = nil
    }

    /// Inter-frame intervals in the window. Zero until the second presented frame.
    public var intervalCount: Int { intervals.count }

    /// Instantaneous rate averaged over the recent window, recomputed every frame. `0` when no
    /// intervals have been recorded yet.
    public var currentFPS: Double {
        guard !intervals.isEmpty else { return 0 }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        return 1.0 / average
    }

    /// The throttled, display-ready rate — refreshed about once per second so it reads steadily.
    public var displayFPS: Double { displayedFPS }

    /// `displayFPS` formatted to two decimal places (e.g. `"25.00"`), suitable for the top-bar
    /// FPS readout.
    public var formatted: String {
        String(format: "%.2f", displayedFPS)
    }
}
