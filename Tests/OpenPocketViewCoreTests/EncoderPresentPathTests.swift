import Testing

@testable import OpenPocketViewCore

@Suite struct EncoderPresentPathTests {
    @Test func firstFormatIsNotAChange() {
        #expect(
            EncoderPresentPath.parameterSetsChanged(
                hadFormat: false,
                previousVPS: nil, previousSPS: nil, previousPPS: nil,
                nextVPS: [1], nextSPS: [2], nextPPS: [3]) == false)
    }

    @Test func identicalSetsAreNotAChange() {
        #expect(
            EncoderPresentPath.parameterSetsChanged(
                hadFormat: true,
                previousVPS: [1], previousSPS: [2], previousPPS: [3],
                nextVPS: [1], nextSPS: [2], nextPPS: [3]) == false)
    }

    @Test func newSPSIsAChange() {
        #expect(
            EncoderPresentPath.parameterSetsChanged(
                hadFormat: true,
                previousVPS: [1], previousSPS: [2], previousPPS: [3],
                nextVPS: [1], nextSPS: [9], nextPPS: [3]))
    }

    @Test func feedAspectUsesRasterAndFallsBack() {
        #expect(abs(EncoderPresentPath.feedAspect(width: 1920, height: 1080) - 16.0 / 9.0) < 0.001)
        #expect(abs(EncoderPresentPath.feedAspect(width: 1080, height: 1920) - 9.0 / 16.0) < 0.001)
        #expect(EncoderPresentPath.feedAspect(width: 0, height: 1080) == 16.0 / 9.0)
    }

    @Test func verticalRasterIsThePocketScreenFlip() {
        #expect(EncoderPresentPath.isVertical(width: 1080, height: 1920))
        #expect(!EncoderPresentPath.isVertical(width: 1920, height: 1080))
        #expect(!EncoderPresentPath.isVertical(width: 0, height: 1920))
    }

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

    @Test func sameRasterSpsMustNotTearOrHoldIDR() {
        #expect(
            !EncoderPresentPath.shouldRebuildDecoderAfterParameterChange(
                pictureSizeChanged: false, accessUnitHasIDR: false),
            "zoom/FORMAT VPS on a live 720p GOP must not tear the decoder")
        #expect(
            !EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
                pictureSizeChanged: false, accessUnitHasIDR: false),
            "holding IDR without 0x09/0xa8 blacks the well while HUD/gimbal stay up")
        #expect(
            FeedWatchdog.shouldPresentSample(
                hasPicture: true, awaitingIDR: false, isIDR: false),
            "P-frames after a same-raster SPS must still present")
    }

    @Test func screenFlipWithoutIDRRebuildsAndHolds() {
        #expect(
            EncoderPresentPath.shouldRebuildDecoderAfterParameterChange(
                pictureSizeChanged: true, accessUnitHasIDR: false))
        #expect(
            EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
                pictureSizeChanged: true, accessUnitHasIDR: false))
        #expect(
            !EncoderPresentPath.shouldBeginIDRHoldAfterParameterChange(
                pictureSizeChanged: true, accessUnitHasIDR: true),
            "IDR in this AU already cut the GOP")
    }
}
