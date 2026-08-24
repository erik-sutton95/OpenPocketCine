import Testing

@testable import OpenPocketViewCore

@Suite struct FeedPresentPolicyTests {
    @Test func freezeThresholdMatchesWatchdogStall() {
        #expect(FeedPresentPolicy.freezeThreshold == FeedWatchdog.stallThreshold)
        #expect(FeedPresentPolicy.freezeThreshold == 2)
    }

    @Test func shouldRenderRequiresVisibleEnabledDrawable() {
        #expect(
            FeedPresentPolicy.shouldRender(
                attached: true, enabled: true, hidden: false, hasDrawable: true))
        #expect(
            !FeedPresentPolicy.shouldRender(
                attached: false, enabled: true, hidden: false, hasDrawable: true))
        #expect(
            !FeedPresentPolicy.shouldRender(
                attached: true, enabled: false, hidden: false, hasDrawable: true))
        #expect(
            !FeedPresentPolicy.shouldRender(
                attached: true, enabled: true, hidden: true, hasDrawable: true))
        #expect(
            !FeedPresentPolicy.shouldRender(
                attached: true, enabled: true, hidden: false, hasDrawable: false))
    }

    @Test func overlayMayScheduleBakeWhileHidden() {
        #expect(FeedPresentPolicy.shouldScheduleBake(enabled: true, hasDrawable: true))
        #expect(!FeedPresentPolicy.shouldScheduleBake(enabled: false, hasDrawable: true))
        #expect(!FeedPresentPolicy.shouldScheduleBake(enabled: true, hasDrawable: false))
    }

    @Test func duplicateTimestampSkipsUnknownZero() {
        #expect(!FeedPresentPolicy.isDuplicateFrameTime(0, lastPresentedNs: 0))
        #expect(!FeedPresentPolicy.isDuplicateFrameTime(1_000, lastPresentedNs: 0))
        #expect(!FeedPresentPolicy.isDuplicateFrameTime(0, lastPresentedNs: 1_000))
        #expect(FeedPresentPolicy.isDuplicateFrameTime(1_000, lastPresentedNs: 1_000))
        #expect(!FeedPresentPolicy.isDuplicateFrameTime(2_000, lastPresentedNs: 1_000))
    }

    @Test func freezeIsAgeNotMissingClock() {
        #expect(!FeedPresentPolicy.isFrozen(secondsSinceLastPresent: nil))
        #expect(!FeedPresentPolicy.isFrozen(secondsSinceLastPresent: 1.9))
        #expect(FeedPresentPolicy.isFrozen(secondsSinceLastPresent: 2))
        #expect(FeedPresentPolicy.isFrozen(secondsSinceLastPresent: 8))
    }

    @Test func overlayBakeDoesNotStealReplaceOwnership() {
        #expect(
            !FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: true))
        #expect(
            !FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: false, lastPresentWasOverlay: false))
        #expect(
            FeedPresentPolicy.replaceOwnsPicture(
                hasPresentedFrame: true, lastPresentWasOverlay: false))
    }

    @Test func unhideMetalBeforeReplaceBakeOnly() {
        #expect(FeedPresentPolicy.unhideMetalBeforeBake(overlay: false))
        #expect(!FeedPresentPolicy.unhideMetalBeforeBake(overlay: true))
    }

    @Test func monitorGradePrefersProxy() {
        #expect(FeedPresentPolicy.preferProxyForMonitorGrade(hasProxy: true))
        #expect(!FeedPresentPolicy.preferProxyForMonitorGrade(hasProxy: false))
        #expect(FeedPresentPolicy.maxWorkingWidth == 1440)
    }

    @Test func flushIsDisconnectOrFailedLayerWithReplacement() {
        #expect(
            FeedPresentPolicy.shouldFlushDisplayedImage(
                disconnecting: true, layerFailed: false, nextFrameReady: false))
        #expect(
            !FeedPresentPolicy.shouldFlushDisplayedImage(
                disconnecting: false, layerFailed: false, nextFrameReady: false),
            "stall keeps the last picture")
        #expect(
            !FeedPresentPolicy.shouldFlushDisplayedImage(
                disconnecting: false, layerFailed: true, nextFrameReady: false),
            "failed layer without a replacement is already black — do not double-flush")
        #expect(
            FeedPresentPolicy.shouldFlushDisplayedImage(
                disconnecting: false, layerFailed: true, nextFrameReady: true))
    }

    @Test func serialGateRefusesOverlap() {
        var gate = SerialSessionGate()
        let first = gate.begin()
        let overlapping = gate.begin()
        #expect(first)
        #expect(!overlapping, "overlapping 0x09/0xa8 is a black well")
        #expect(gate.inFlight)
        gate.end()
        let after = gate.begin()
        #expect(after)
        gate.end()
        #expect(!gate.inFlight)
    }
}
