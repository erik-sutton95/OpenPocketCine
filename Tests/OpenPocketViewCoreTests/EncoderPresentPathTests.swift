import Testing

@testable import OpenPocketViewCore

// Parameter-set policy is tested in OpenCineCore (OpenCineMediaTests). These cover the DJI
// live-view enable and its watchdog coupling.
@Suite struct EncoderPresentPathTests {
    @Test func parameterChangeDoesNotReEnableWhenAUAlreadyHasIDR() {
        #expect(
            EncoderPresentPath.shouldRequestEnableAfterParameterChange(accessUnitHasIDR: false),
            "new sets without IDR still need 0x09/0xa8")
        #expect(
            !EncoderPresentPath.shouldRequestEnableAfterParameterChange(accessUnitHasIDR: true),
            "camera already cut the GOP — a second enable hangs the hold")
    }

    @Test func parameterChangeDoesNotEnableWhileUDPVideoIsAlive() {
        #expect(
            !EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR: false, udpReceiveAlive: true),
            "format SET VPS on a live socket is not a dead encoder — 0x09/0xa8 cuts the GOP")
        #expect(
            !EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR: false,
                udpReceiveAlive: false,
                secondsSinceLastEnable: 2.0),
            "debounce to escalateAfter so a SET storm is one enable, not one per hop")
        #expect(
            EncoderPresentPath.shouldRequestEnableAfterParameterChange(
                accessUnitHasIDR: false,
                udpReceiveAlive: false,
                secondsSinceLastEnable: 5.0))
    }

    @Test func pPicturesStillPresentAfterSameRasterSPS() {
        #expect(
            FeedWatchdog.shouldPresentSample(
                hasPicture: true, awaitingIDR: false, isIDR: false),
            "P-frames after a same-raster SPS must still present")
    }

    /// OpenCineMedia keeps the freeze threshold as its own constant; it must stay the watchdog stall.
    @Test func freezeThresholdMatchesWatchdogStall() {
        #expect(FeedPresentPolicy.freezeThreshold == FeedWatchdog.stallThreshold)
    }
}
