/// Spots the picture a Pocket 3 Med-Tele lens cut makes in the live feed.
///
/// The body sends no marker for the swap and reports it 220–600 ms late, but on
/// a Pocket 3 the cut is always one access unit 2–5× the size of the ones before
/// it, 107–145 ms after the command (smaller spikes come earlier, before the
/// body can have acted). The new lens is the picture after it, so the live view
/// can fade back in without waiting for the status push.
///
/// The Android decoder carries the same rule in Kotlin (`HevcDecoder.watchForLensSwap`);
/// the constants must stay in step.
public struct LensSwapWatch: Sendable {
    /// Longest after the MT command the swap frame can still come in.
    public static let windowMs: Double = 450
    /// Sooner than this the body cannot have acted on the command yet.
    public static let minMs: Double = 95
    /// An access unit the swap cut makes: this far over the recent median, both ways.
    public static let spikeRatio: Double = 1.4
    public static let spikeBytes = 8_000
    /// Parameter sets come alone and are tiny.
    static let parameterSetBytes = 200
    static let history = 9

    public enum Outcome: Equatable, Sendable {
        case none
        /// The cut came in `afterMs` after the command.
        case swap(afterMs: Double, bytes: Int, baseline: Int)
        /// The window closed without one.
        case expired(baseline: Int)
    }

    private var recent: [Int] = []
    private var recentCount = 0
    private var afterParameterSets = false
    private var armedAt: Double?
    private var baseline = 0

    public init() {}

    public var isArmed: Bool { armedAt != nil }

    /// The MT command just went out: look for its cut from here.
    public mutating func arm(nowMs: Double) {
        baseline = 0
        armedAt = nowMs
    }

    /// Feed every access unit, armed or not, so the baseline is ready when the
    /// command goes out.
    public mutating func observe(bytes: Int, keyframe: Bool, nowMs: Double) -> Outcome {
        // Parameter sets come alone, and the picture right after them is intra:
        // both are big for their own reasons, so neither can mark a swap or set
        // the baseline.
        let parameterSets = bytes < Self.parameterSetBytes
        let skip = parameterSets || afterParameterSets || keyframe
        afterParameterSets = parameterSets
        var outcome = Outcome.none
        if let from = armedAt {
            let t = nowMs - from
            if baseline == 0 { baseline = median() }
            if t > Self.windowMs {
                armedAt = nil
                outcome = .expired(baseline: baseline)
            } else if !skip, t >= Self.minMs, baseline > 0,
                Double(bytes) >= Double(baseline) * Self.spikeRatio,
                bytes >= baseline + Self.spikeBytes
            {
                armedAt = nil
                outcome = .swap(afterMs: t, bytes: bytes, baseline: baseline)
            }
        }
        if !skip {
            if recent.count < Self.history {
                recent.append(bytes)
            } else {
                recent[recentCount % Self.history] = bytes
            }
            recentCount += 1
        }
        return outcome
    }

    private func median() -> Int {
        guard !recent.isEmpty else { return 0 }
        return recent.sorted()[recent.count / 2]
    }
}
