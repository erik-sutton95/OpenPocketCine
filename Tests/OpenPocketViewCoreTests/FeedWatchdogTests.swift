import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct FeedWatchdogTests {
    @Test func ignoresHitchShorterThanStall() {
        var dog = FeedWatchdog()
        #expect(dog.tick(Self.snap(now: 10, frameAge: 1.5)) == .none)
        #expect(dog.stage == .idle)
    }

    @Test func waitsForFirstPictureWhileVideoFlows() {
        var dog = FeedWatchdog()
        #expect(
            dog.tick(Self.snap(now: 10, frameAge: 8, videoAge: 0.3, sawPicture: false)) == .none)
        #expect(dog.stage == .idle)
    }

    @Test func packetsFlowingDoNotRejoinWhenPresentStuck() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 10, frameAge: 2.6, videoAge: 0.0)
        snap.lastAccessUnitAge = 0.0
        snap.lastBleNotifyAge = 0.2
        #expect(dog.tick(snap) == .none)
        #expect(dog.stage == .idle)
        snap.displayedImageRemoved = true
        snap.lastDecodedFrameAge = 4
        #expect(dog.tick(snap) == .none, "black + healthy UDP must not escalate to reconnect")
        #expect(dog.stage == .idle)
    }

    @Test func staleAccessUnitsAreIgnoredWhenVideoPacketsFlow() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 10, frameAge: 0.2, videoAge: 0.1)
        snap.lastAccessUnitAge = 2.5
        #expect(dog.tick(snap) == .none, "UDP packets flowing ⇒ do not resend enable")
        #expect(dog.stage == .idle)
    }

    @Test func udpSilentWithBleAliveRebuildsUDPImmediately() {
        var dog = FeedWatchdog()
        let snap = Self.snap(
            now: 10, frameAge: 7.9, videoAge: 7.9, statusAge: 7.9,
            bleAge: 0.1, tcpPokeReady: true)
        #expect(dog.tick(snap) == .reopenDatalink)
        #expect(dog.stage == .reopenDatalink)
        #expect(dog.isRecovering)
    }

    @Test func afcHuntWithFreshStatusDoesNotTearUDP() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 4.2, videoAge: 4.2, statusAge: 0.3, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        snap.secondsSinceFocusTrackSet = 1.0
        #expect(
            dog.tick(snap) == .none,
            "AF-C pulse hunt pauses HEVC; status still on 9004 is not a dead socket")
        #expect(dog.stage == .idle)
        #expect(!dog.isRecovering)
        #expect(FeedWatchdog.controlReceiveAlive(snap))
        #expect(FeedWatchdog.socketAlive(snap))
        #expect(!FeedWatchdog.udpReceiveAlive(snap))
    }

    @Test func encoderPauseWithFreshStatusResendsEnable() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 4.2, videoAge: 4.2, statusAge: 0.3, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "young status + stale HEVC past GOP/AF-C grace is an encoder pause")
        #expect(dog.stage == .resendEnable)

        snap.now = 11
        #expect(
            dog.tick(snap) == .none,
            "escalateAfter (5s) between enables — do not 1 Hz loop")
        #expect(dog.stage == .resendEnable)
    }

    @Test func enableThatProducesNoHEVCDoesNotRebuildUDPWhileStatusIsYoung() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 2.8, videoAge: 2.8, statusAge: 0.0, bleAge: 70)
        snap.secondsSinceLastEnable = 20
        #expect(dog.tick(snap) == .resendLiveViewEnable)
        #expect(dog.stage == .resendEnable)

        // Physical #148: 2 s later status still 0.0 s. Diagnoser stays
        // encoderPaused / resendEnable. Reopening UDP here left lastVideo=none.
        snap.now = 12.1
        snap.lastDecodedFrameAge = 4.9
        snap.lastVideoPacketAge = 4.9
        snap.lastAccessUnitAge = 4.9
        snap.lastStatusAge = 0.0
        snap.secondsSinceLastEnable = 2.1
        #expect(
            !FeedWatchdog.shouldHoldForGOPReset(
                secondsSinceLastEnable: 2.1, lastVideoPacketAge: 4.9))
        #expect(
            dog.tick(snap) == .none,
            "young status means the 9004 socket is alive — do not rebuild UDP at 2s")
        #expect(dog.stage == .resendEnable)

        snap.now = 15.1
        snap.lastDecodedFrameAge = 7.9
        snap.lastVideoPacketAge = 7.9
        snap.lastAccessUnitAge = 7.9
        snap.lastStatusAge = 0.0
        snap.secondsSinceLastEnable = 5.1
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "still encoder-paused after escalateAfter — one more enable, not a 5-tuple tear")
        #expect(dog.stage == .resendEnable)
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 2.1,
                secondsSinceLastRebuild: nil,
                pathReady: true,
                lastBleNotifyAge: 70,
                hadVideo: true,
                holdEnableCount: 1,
                lastVideoPacketAge: 4.9),
            "do not spam 0x09/0xa8 while videoPkts are frozen")
    }

    @Test func gopResetSilenceDoesNotRebuildUDP() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 10, frameAge: 3.0, videoAge: 3.0, bleAge: 0.2)
        snap.secondsSinceLastEnable = 2.5
        #expect(dog.tick(snap) == .none, "2.5s after 0x09/0xa8 is the GOP cut, not a dead socket")
        #expect(dog.stage == .idle)
        #expect(FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: 2.5))
        #expect(FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: 7.9))
        #expect(!FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: 8.0))
        #expect(!FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: nil))
        #expect(
            FeedWatchdog.shouldHoldForGOPReset(
                secondsSinceLastEnable: 2.5, lastVideoPacketAge: 0.4),
            "HEVC after enable is the IDR gap")
        #expect(
            !FeedWatchdog.shouldHoldForGOPReset(
                secondsSinceLastEnable: 1.0, lastVideoPacketAge: 3.8),
            "video died before this enable — not an IDR gap")

        snap.secondsSinceLastEnable = 8.1
        snap.lastStatusAge = 8.1
        #expect(dog.tick(snap) == .reopenDatalink, "past IDR grace and still silent — then rebuild")
    }

    @Test func afcTrackSetSilenceDoesNotRebuildUDP() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 10, frameAge: 3.0, videoAge: 3.0, bleAge: 0.2)
        snap.secondsSinceFocusTrackSet = 1.8
        #expect(dog.tick(snap) == .none, "AF-C 0x3B SET can pause HEVC — do not flash Reconnecting")
        #expect(dog.stage == .idle)
        #expect(!dog.isRecovering)
        #expect(FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 0))
        #expect(FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 3.9))
        #expect(!FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 4.0))
        #expect(!FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: nil))
        #expect(!FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: -0.1))

        snap.secondsSinceFocusTrackSet = 4.1
        snap.lastStatusAge = 4.1
        #expect(
            dog.tick(snap) == .reopenDatalink, "past AF-C grace and still silent — then rebuild")
    }

    @Test func assistDecoderStartRequestsIDROnlyOnce() {
        #expect(
            FeedWatchdog.shouldRequestKeyFrameForDecoderStart(
                startingHardwareDecoder: true, hasFormat: true, hasPicture: true))
        #expect(
            !FeedWatchdog.shouldRequestKeyFrameForDecoderStart(
                startingHardwareDecoder: false, hasFormat: true, hasPicture: true),
            "LUT/PEAK/WAVE off is not a GOP reset")
        #expect(
            !FeedWatchdog.shouldRequestKeyFrameForDecoderStart(
                startingHardwareDecoder: true, hasFormat: true, hasPicture: false))
        #expect(
            !FeedWatchdog.shouldRequestKeyFrameForDecoderStart(
                startingHardwareDecoder: true, hasFormat: false, hasPicture: true))
    }

    @Test func udpSilentDoesNotTearVTOrFullRejoin() {
        var dog = FeedWatchdog()
        var now: TimeInterval = 10
        var snap = Self.snap(
            now: now, frameAge: 13, videoAge: 13, statusAge: 13,
            bleAge: 0.2, tcpPokeReady: true)
        #expect(dog.tick(snap) == .reopenDatalink)

        now += FeedWatchdog.escalateAfter
        snap.now = now
        snap.lastDecodedFrameAge = 18
        snap.lastVideoPacketAge = 18
        snap.lastAccessUnitAge = 18
        #expect(dog.tick(snap) == .none, "second UDP pause must not fullRejoin SoftAP")
        #expect(dog.stage == .cooldown)
        #expect(!dog.isRecovering)
    }

    @Test func firstConnectFrozenVideoRebuildsUDP() {
        var dog = FeedWatchdog()
        #expect(
            dog.tick(
                Self.snap(
                    now: 10, frameAge: 10, videoAge: 2.1, statusAge: 2.1,
                    sawPicture: false, bleAge: 0.3, hadVideo: true))
                == .reopenDatalink)
        #expect(dog.stage == .reopenDatalink)
    }

    /// First picture: no 0x02 yet. A leftover rebuild / nil receive clock is
    /// not a live flap — resend `0x09/0xa8`, do not hold or fullRejoin.
    @Test func neverGotVideoResendsEnableEvenAfterRebuild() {
        #expect(
            !FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 0.4, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: false))
        #expect(
            FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 2, secondsSinceLastRebuild: 0.4,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: false))
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 1, secondsSinceLastRebuild: 0.4,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: false))

        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 10, videoAge: nil, sawPicture: false, bleAge: 0.2,
            hadVideo: false)
        snap.lastVideoPacketAge = nil
        snap.secondsSinceLastRebuild = 0.4
        #expect(dog.tick(snap) == .resendLiveViewEnable)
        #expect(dog.stage == .resendEnable)
        #expect(dog.tick(snap) != .fullSessionRejoin)
    }

    /// First handshake miss is a UDP rebind, not a SoftAP tear / operator kick.
    @Test func firstHandshakeSilenceDoesNotFullRejoin() {
        var dog = FeedWatchdog()
        let snap = Self.snap(
            now: 10, frameAge: 10, videoAge: 10, statusAge: 10,
            sawPicture: false, bleAge: 0.2, tcpPokeReady: true)
        let action = dog.tick(snap)
        #expect(action != .fullSessionRejoin)
        #expect(action == .reopenDatalink)
        #expect(!CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: true))
    }

    @Test func stallRebuildsUDPThenCooldownWithoutVTLadder() {
        var dog = FeedWatchdog()
        var now: TimeInterval = 100

        #expect(
            dog.tick(Self.snap(now: now, frameAge: 2.1, statusAge: 2.1, bleAge: 0.2))
                == .reopenDatalink)
        #expect(dog.stage == .reopenDatalink)
        #expect(dog.isRecovering)

        now += FeedWatchdog.escalateAfter - 0.5
        #expect(dog.tick(Self.snap(now: now, frameAge: 6, statusAge: 6, bleAge: 0.2)) == .none)
        #expect(dog.stage == .reopenDatalink)

        now += 0.6
        #expect(dog.tick(Self.snap(now: now, frameAge: 7, statusAge: 7, bleAge: 0.2)) == .none)
        #expect(dog.stage == .cooldown)
        #expect(!dog.isRecovering)

        now += 1
        #expect(dog.tick(Self.snap(now: now, frameAge: 8, statusAge: 8, bleAge: 0.2)) == .none)
        #expect(dog.stage == .cooldown)

        now += FeedWatchdog.cooldownDuration
        #expect(
            dog.tick(Self.snap(now: now, frameAge: 25, statusAge: 25, bleAge: 0.2)) == .none,
            "BLE + SoftAP still up — do not flap UDP after cooldown")
        #expect(dog.stage == .cooldown)
    }

    /// Command-timeout rebuild tears video, stamps a fake lastPacket, watchdog
    /// resets to idle, then rebuilds every 2s. After one rebuild, hold.
    @Test func afterOneUDPRebuildDoesNotFlapOnTwoSecondCadence() {
        var dog = FeedWatchdog()
        var now: TimeInterval = 10
        #expect(
            dog.tick(Self.snap(now: now, frameAge: 2.6, statusAge: 2.6, bleAge: 0.2))
                == .reopenDatalink)

        now += 0.1
        var fakeFresh = Self.snap(now: now, frameAge: 2.7, videoAge: 0.1, bleAge: 0.2)
        fakeFresh.secondsSinceLastRebuild = 0.1
        #expect(dog.tick(fakeFresh) == .none, "stamped lastPacket must not start another rebuild")
        #expect(dog.stage == .idle)

        now += 2.5
        var stall = Self.snap(now: now, frameAge: 5.2, videoAge: 2.6, statusAge: 2.6, bleAge: 0.2)
        stall.secondsSinceLastRebuild = 2.6
        #expect(dog.tick(stall) == .none, "2s stall after a rebuild is not another UDP tear-down")
        #expect(dog.stage == .cooldown)
        #expect(dog.tick(stall) != .fullSessionRejoin)
    }

    @Test func recentRebuildWithBleAndPathHoldsBind() {
        #expect(
            FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 2.6, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: true))
        #expect(
            !FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: nil, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: true))
        #expect(
            !FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 2.6, pathReady: true, lastBleNotifyAge: 8,
                hadVideo: true))
        #expect(
            !FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 2.6, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: false),
            "neverGotVideo must not inherit the post-video 60s hold")
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: 2.6,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true),
            "one recover 0x09/0xa8 is enough after a rebuild")
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 1, lastVideoPacketAge: 0.2),
            "UDP video flowing — 0x09/0xa8 GOP-cuts a live picture (still holding for IDR)")
        #expect(
            FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 1, lastVideoPacketAge: 5),
            "missed IDR and HEVC silent — one extra enable at 5s")
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 2),
            "already retried this hold — do not 1 Hz loop")
        #expect(
            FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 60, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 2),
            "dead camera after the one retry — 60s backoff")
    }

    @Test func framesReturningResetToIdle() {
        var dog = FeedWatchdog()
        #expect(
            dog.tick(Self.snap(now: 10, frameAge: 3, statusAge: 3, bleAge: 0.2))
                == .reopenDatalink)
        #expect(dog.tick(Self.snap(now: 11, frameAge: 0.2, videoAge: 0.1)) == .none)
        #expect(dog.stage == .idle)
        #expect(!dog.isRecovering)
    }

    @Test func deadFlowSkipsToReopenDatalink() {
        var dog = FeedWatchdog()
        #expect(
            dog.tick(Self.snap(now: 10, frameAge: 3, statusAge: 3, flowHealthy: false, bleAge: 0.2))
                == .reopenDatalink)
        #expect(dog.stage == .reopenDatalink)
    }

    @Test func wedgedDecoderDoesNotTearVTWhileUDPPaused() {
        var dog = FeedWatchdog()
        #expect(
            dog.tick(
                Self.snap(now: 10, frameAge: 3, statusAge: 3, decoderFailed: true, bleAge: 0.2))
                == .reopenDatalink,
            "UDP pause + BLE up ⇒ rebuild UDP, do not rebuild VT")
        #expect(dog.stage == .reopenDatalink)
    }

    @Test func stallLogNamesAgesAndStates() {
        var dog = FeedWatchdog()
        let snap = Self.snap(now: 10, frameAge: 3.2, videoAge: 3.1, statusAge: 3.1)
        _ = dog.tick(snap)
        let line = dog.stallLogLine(snap)
        #expect(line.contains("feed: stall"))
        #expect(line.contains("lastFrame=3.2"))
        #expect(line.contains("lastVideo=3.1"))
        #expect(line.contains("lastStatus=3.1"))
        #expect(line.contains("flow=ready"))
        #expect(line.contains("stage=reopenDatalink"))
        #expect(line.contains("recoverBlack=0"))
        #expect(!line.contains("feed: black"))
    }

    @Test func blackLogWhenRecoverWipedTheLayer() {
        var dog = FeedWatchdog()
        let snap = Self.snap(now: 10, frameAge: 4, displayedImageRemoved: true)
        _ = dog.tick(snap)
        let line = dog.stallLogLine(snap)
        #expect(line.contains("feed: black"))
        #expect(line.contains("recoverBlack=1"))
        #expect(line.contains("lastFrame=4.0"))
        #expect(line.contains("flow=ready"))
    }

    @Test func recoverDoesNotFlushToBlackBeforeNextFrame() {
        #expect(!FeedWatchdog.shouldFlushDisplayedImage(nextFrameReady: false))
        #expect(FeedWatchdog.shouldFlushDisplayedImage(nextFrameReady: true))
        #expect(
            !FeedWatchdog.shouldPresentSample(
                hasPicture: false, awaitingIDR: false, isIDR: false))
        #expect(
            !FeedWatchdog.shouldPresentSample(
                hasPicture: true, awaitingIDR: true, isIDR: false))
        #expect(
            FeedWatchdog.shouldPresentSample(
                hasPicture: true, awaitingIDR: true, isIDR: true))
        #expect(
            FeedWatchdog.shouldPresentSample(
                hasPicture: true, awaitingIDR: false, isIDR: false))
        #expect(!FeedWatchdog.shouldSendRecoverEnable(pathReady: true, decoderReady: false))
        #expect(!FeedWatchdog.shouldSendRecoverEnable(pathReady: false, decoderReady: true))
        #expect(FeedWatchdog.shouldSendRecoverEnable(pathReady: true, decoderReady: true))
    }

    private static func snap(
        now: TimeInterval,
        frameAge: TimeInterval,
        videoAge: TimeInterval? = nil,
        statusAge: TimeInterval? = 0.2,
        flowHealthy: Bool = true,
        decoderFailed: Bool = false,
        sawPicture: Bool = true,
        displayedImageRemoved: Bool = false,
        bleAge: TimeInterval? = nil,
        tcpPokeReady: Bool = false,
        hadVideo: Bool = true
    ) -> FeedWatchdog.Snapshot {
        FeedWatchdog.Snapshot(
            now: now,
            lastDecodedFrameAge: frameAge,
            lastVideoPacketAge: videoAge ?? (hadVideo ? frameAge : nil),
            lastStatusAge: statusAge,
            flowHealthy: flowHealthy,
            pathReady: true,
            hasFormat: true,
            decoderFailed: decoderFailed,
            live: true,
            sawPicture: sawPicture,
            tcpPokeReady: tcpPokeReady,
            displayedImageRemoved: displayedImageRemoved,
            lastBleNotifyAge: bleAge,
            secondsSinceLastRebuild: nil,
            hadVideo: hadVideo
        )
    }
}
