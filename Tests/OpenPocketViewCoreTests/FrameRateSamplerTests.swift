import Foundation
import Testing

@testable import OpenPocketViewCore

@Test func frameRateSamplerReportsZeroBeforeAnyFrames() {
    let sampler = FrameRateSampler()
    #expect(sampler.currentFPS == 0)
}

@Test func frameRateSamplerMeasuresInstantaneousRateFromTwoFrames() {
    var sampler = FrameRateSampler()
    sampler.recordFrame(at: 0)
    // 33.33ms later — ~30 fps.
    sampler.recordFrame(at: 0.033_333)
    #expect(abs(sampler.currentFPS - 30.0) < 0.5)
}

@Test func frameRateSamplerSmoothsOverRecentWindow() {
    var sampler = FrameRateSampler(windowSize: 8)
    // Inter-frame intervals alternating 0.020s (50fps) and 0.040s (25fps) → average 0.030s → ~33.3fps.
    var t = 0.0
    sampler.recordFrame(at: t)
    for _ in 0..<6 {
        t += 0.020
        sampler.recordFrame(at: t)
        t += 0.040
        sampler.recordFrame(at: t)
    }
    #expect(abs(sampler.currentFPS - 33.3) < 1.5)
}

@Test func frameRateSamplerIgnoresNonMonotonicTimestamps() {
    var sampler = FrameRateSampler()
    sampler.recordFrame(at: 0.1)
    sampler.recordFrame(at: 0.133)
    // A stale/out-of-order or zero-delta frame must not corrupt the rate or divide by zero.
    sampler.recordFrame(at: 0.0)
    #expect(sampler.currentFPS > 0)
    #expect(abs(sampler.currentFPS - 30.0) < 0.5)
}

@Test func frameRateSamplerFormattedReportsTwoDecimals() {
    var sampler = FrameRateSampler()
    sampler.recordFrame(at: 0)
    sampler.recordFrame(at: 0.040)
    #expect(sampler.formatted == "25.00")
}

@Test func frameRateSamplerThrottlesDisplayedReadout() {
    var sampler = FrameRateSampler(windowSize: 30, displayRefreshInterval: 1.0)
    sampler.recordFrame(at: 0)
    sampler.recordFrame(at: 0.04)  // first interval publishes immediately (~25 fps)
    #expect(abs(sampler.displayFPS - 25.0) < 0.1)

    // Feed 50 fps frames for ~0.9 s. The true rate moves, but under the 1 s refresh the displayed
    // readout must hold steady instead of flickering frame-to-frame.
    var t = 0.04
    while t < 0.96 {
        t += 0.02
        sampler.recordFrame(at: t)
    }
    #expect(abs(sampler.displayFPS - 25.0) < 0.1)  // readout still throttled
    #expect(sampler.currentFPS > 45)  // underlying average already ~50

    // Past the 1 s mark the readout republishes and catches up.
    while t < 1.30 {
        t += 0.02
        sampler.recordFrame(at: t)
    }
    #expect(abs(sampler.displayFPS - 50.0) < 2.0)
}

@Test func frameRateSamplerPublishesSilenceAndMeasuresResumedRun() {
    var sampler = FrameRateSampler()
    sampler.recordFrame(at: 0)
    sampler.recordFrame(at: 0.04)
    #expect(sampler.formatted == "25.00")
    sampler.age(at: 2.04)
    #expect(sampler.formatted == "0.00")
    sampler.recordFrame(at: 3)
    sampler.recordFrame(at: 3.04)
    #expect(sampler.formatted == "25.00")
}

@Test func frameRateSamplerDoesNotRewindAfterStaleInput() {
    var sampler = FrameRateSampler()
    sampler.recordFrame(at: 1)
    sampler.recordFrame(at: 1.04)
    sampler.recordFrame(at: 0)
    sampler.recordFrame(at: 1.08)
    #expect(abs(sampler.currentFPS - 25) < 0.001)
}
