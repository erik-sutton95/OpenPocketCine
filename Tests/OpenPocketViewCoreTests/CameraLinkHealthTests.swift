import Testing

@testable import OpenPocketViewCore

@Suite("Camera link health scoring")
struct CameraLinkHealthTests {
    @Test func disconnected() {
        let s = CameraLinkHealthScorer.score(.init(phase: .disconnected))
        #expect(s.linkHealthScore == 0)
    }

    @Test func healthyStreaming() {
        let s = CameraLinkHealthScorer.score(
            .init(
                phase: .streaming, ptpRoundTripMilliseconds: 45,
                liveViewFPS: 29.5, targetLiveViewFPS: 30, secondsSinceLastGoodFrame: 0.03))
        #expect(s.linkHealthScore >= 80)
    }

    @Test func pocketLiveViewTargetIsPreviewRateNotRecordingFormat() {
        #expect(LiveViewLink.targetFPS == 25)
        let healthy = CameraLinkHealthScorer.score(
            .init(
                phase: .streaming,
                liveViewFPS: 25,
                targetLiveViewFPS: LiveViewLink.targetFPS,
                secondsSinceLastGoodFrame: 0.04))
        #expect(healthy.linkHealthScore >= 70)
        var bars = LinkSignalBars()
        #expect(bars.update(score: healthy.linkHealthScore) >= 3)
    }

    @Test func fpsChipLabelMatchesOpenZCineStates() {
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .idle, recovering: false, formattedFPS: "25.00", measuredFPS: 0)
                == "—")
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .openingDatalink, recovering: false, formattedFPS: "25.00",
                measuredFPS: 0) == "LINK")
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .live, recovering: false, formattedFPS: "25.00", measuredFPS: 25)
                == "25.00")
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .live, recovering: true, formattedFPS: "25.00", measuredFPS: 25)
                == "RECOV")
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .failed("timeout"), recovering: false, formattedFPS: "25.00",
                measuredFPS: 25) == "FAIL")
        // Simulator clip: idle phase but frames are arriving.
        #expect(
            LiveViewLink.fpsChipLabel(
                connection: .idle, recovering: false, formattedFPS: "25.00", measuredFPS: 25)
                == "25.00")
    }

    @Test func cameraLinkPhaseUsesMeasuredDelivery() {
        #expect(
            LiveViewLink.cameraLinkPhase(
                connection: .idle, recovering: false, measuredFPS: 0) == .disconnected)
        #expect(
            LiveViewLink.cameraLinkPhase(
                connection: .idle, recovering: false, measuredFPS: 25) == .streaming)
        #expect(
            LiveViewLink.cameraLinkPhase(
                connection: .live, recovering: true, measuredFPS: 12) == .recovering)
        #expect(
            LiveViewLink.cameraLinkPhase(
                connection: .failed("x"), recovering: false, measuredFPS: 25) == .disconnected)
    }

    @Test func feedWarmupCoversFrozenFirstFrame() {
        #expect(
            LiveFeedWarmup.isWarming(
                hasPresentedPicture: false, measuredFPS: 0, recovering: false),
            "no picture yet")
        #expect(
            LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 0, recovering: false),
            "one IDR with no rate is still warming")
        #expect(
            LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 25, rollingIntervals: 1,
                recovering: false, secondsSinceLastPresented: 0.05),
            "two leftover GOP frames must not lift the plate")
        #expect(
            !LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 25,
                rollingIntervals: LiveFeedWarmup.minimumRollingIntervals,
                recovering: false, secondsSinceLastPresented: 2.0),
            "AF-C hunt / stall keeps the last frame — do not put Waiting back")
        #expect(
            !LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 25,
                rollingIntervals: LiveFeedWarmup.minimumRollingIntervals,
                recovering: true, secondsSinceLastPresented: 0.2),
            "mid-session recover keeps the last frame")
        #expect(
            !LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 25,
                rollingIntervals: LiveFeedWarmup.minimumRollingIntervals,
                recovering: false, secondsSinceLastPresented: 0.2),
            "rolling picture lifts the plate")
    }
}
