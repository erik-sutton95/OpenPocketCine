import Testing

@testable import OpenPocketViewCore

struct LensSwapWatchTests {
    /// Nine steady 20 kB pictures, 33 ms apart, ending at `t`.
    private func primed(until t: Double = 0) -> LensSwapWatch {
        var w = LensSwapWatch()
        for i in 0..<9 {
            _ = w.observe(bytes: 20_000, keyframe: false, nowMs: t - Double(9 - i) * 33)
        }
        return w
    }

    @Test func spotsTheCutInsideTheWindow() {
        var w = primed()
        w.arm(nowMs: 0)
        #expect(w.observe(bytes: 21_000, keyframe: false, nowMs: 33) == .none)
        #expect(
            w.observe(bytes: 60_000, keyframe: false, nowMs: 120)
                == .swap(afterMs: 120, bytes: 60_000, baseline: 20_000))
        #expect(!w.isArmed)
    }

    @Test func aSpikeBeforeTheBodyCanActIsNotTheCut() {
        var w = primed()
        w.arm(nowMs: 0)
        #expect(w.observe(bytes: 60_000, keyframe: false, nowMs: 50) == .none)
        #expect(w.isArmed)
    }

    @Test func needsBothTheRatioAndTheBytes() {
        var small = LensSwapWatch()
        for i in 0..<9 { _ = small.observe(bytes: 4_000, keyframe: false, nowMs: Double(i)) }
        small.arm(nowMs: 100)
        // 2.5× the median, but only 6 kB over it: ordinary motion on a quiet picture.
        #expect(small.observe(bytes: 10_000, keyframe: false, nowMs: 220) == .none)

        var w = primed()
        w.arm(nowMs: 0)
        // 6 kB over and 1.3×: short on both counts on a busy picture.
        #expect(w.observe(bytes: 26_000, keyframe: false, nowMs: 120) == .none)
    }

    @Test func keyframesAndParameterSetsNeverMarkTheSwap() {
        var w = primed()
        w.arm(nowMs: 0)
        #expect(w.observe(bytes: 90_000, keyframe: true, nowMs: 110) == .none)
        #expect(w.observe(bytes: 120, keyframe: false, nowMs: 115) == .none)
        // The intra picture right after the parameter sets.
        #expect(w.observe(bytes: 90_000, keyframe: false, nowMs: 116) == .none)
        #expect(w.isArmed)
    }

    @Test func expiresWithoutACut() {
        var w = primed()
        w.arm(nowMs: 0)
        #expect(w.observe(bytes: 20_000, keyframe: false, nowMs: 300) == .none)
        #expect(w.observe(bytes: 20_000, keyframe: false, nowMs: 460) == .expired(baseline: 20_000))
        #expect(!w.isArmed)
    }

    @Test func noBaselineNoSwap() {
        var w = LensSwapWatch()
        w.arm(nowMs: 0)
        #expect(w.observe(bytes: 60_000, keyframe: false, nowMs: 120) == .none)
    }
}
