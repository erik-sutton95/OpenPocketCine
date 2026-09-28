import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct FeedWatchdogTests {
    @Test func packetOnlyTrafficUsesBoundedEnableLadderWhenCompletePicturesStop() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 100, frameAge: 3, videoAge: 0.01)
        snap.lastAccessUnitAge = 3
        snap.decoderOutputExpected = true
        snap.lastDecoderOutputAge = 3
        #expect(dog.tick(snap) == .resendLiveViewEnable)
        snap.now = 101
        #expect(dog.tick(snap) == .none)
        snap.now = 105
        #expect(dog.tick(snap) == .reopenDatalink)
        snap.now = 106
        snap.lastAccessUnitAge = 0.01
        snap.lastDecoderOutputAge = 0.01
        snap.lastDecodedFrameAge = 0.01
        #expect(dog.tick(snap) == .none)
        #expect(dog.stage == .idle)
    }

    /// An established decoder without a format still owns one bounded repair.
    @Test(arguments: [true, false])
    func continuousInputWithSilentDecoderRequestsOneOwnedRepair(hasFormat: Bool) {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 100, frameAge: 3, videoAge: 0.01)
        snap.lastAccessUnitAge = 0.01
        snap.decoderOutputExpected = true
        snap.lastDecoderOutputAge = 3
        snap.hasFormat = hasFormat
        #expect(dog.tick(snap) == .rebuildVTSession)
        for second in 1..<16 {
            snap.now = 100 + Double(second)
            snap.lastDecoderOutputAge = 3 + Double(second)
            #expect(dog.tick(snap) == .none)
        }
        snap.now = 116
        #expect(dog.tick(snap) == .fullSessionRejoin)
    }

    /// Keep resending about every 2 s until an IRAP newer than the last
    /// request lands; two unanswered requests (about 4 s) rebuild the endpoint.
    @Test func decoderRepairResendsKeyframeThenRebuildsEndpoint() {
        func step(_ start: TimeInterval, _ enable: TimeInterval, _ irap: TimeInterval?, _ n: Int)
            -> FeedWatchdog.DecoderRepairStep
        {
            FeedWatchdog.decoderRepairStep(
                secondsSinceRepairStart: start, secondsSinceLastEnable: enable,
                secondsSinceLastIrap: irap, keyframeRequests: n)
        }
        #expect(step(1.9, 1.9, nil, 1) == .wait, "the camera answers in 0.1-1.1 s (#443)")
        #expect(step(2.0, 2.0, nil, 1) == .resendKeyframe)
        #expect(step(2.0, 2.0, 5.0, 1) == .resendKeyframe, "an IRAP older than the request")
        #expect(step(3.9, 1.9, nil, 2) == .wait)
        #expect(step(4.0, 2.0, nil, 2) == .rebuildEndpoint, "unanswered twice: endpoint, not 16 s")
        #expect(step(4.0, 2.0, 0.5, 2) == .wait, "answered: wait for output under the deadline")
        #expect(step(15.9, 15.9, 12.0, 1) == .wait)
        #expect(step(16.0, 16.0, 12.0, 1) == .deadline)
        #expect(step(16.0, 3.0, nil, 1) == .deadline, "blocked resends cannot outlive the deadline")
    }

    @Test func sessionRecoveryHoldsWhileVideoPacketsArrive() {
        #expect(FeedWatchdog.shouldHoldSessionRecovery(lastVideoPacketAge: 0.03))
        #expect(FeedWatchdog.shouldHoldSessionRecovery(lastVideoPacketAge: 1.9))
        #expect(!FeedWatchdog.shouldHoldSessionRecovery(lastVideoPacketAge: 2.0))
        #expect(!FeedWatchdog.shouldHoldSessionRecovery(lastVideoPacketAge: nil), "no datalink")
    }

    /// Video without picture cannot hold Bluetooth forever: the third repair
    /// deadline in one episode (~60 s) releases it to SessionRecovery.
    @Test func sessionHoldIsBoundedToThreeRepairCycles() {
        func next(_ previous: Int, picture: Bool = false, video: TimeInterval? = 0.05) -> Int {
            FeedWatchdog.nextSessionHoldCycles(
                lastVideoPacketAge: video, previousCycles: previous, pictureSinceLastCycle: picture)
        }
        #expect(FeedWatchdog.maxHeldRepairCycles == 3)
        #expect(next(0) == 1, "cycle 1: hold")
        #expect(next(1) == 2, "cycle 2: hold")
        #expect(next(2) == 0, "cycle 3: release to SessionRecovery and reset")
        #expect(next(0) == 1, "a released episode starts over")
        #expect(next(2, picture: true) == 1, "a presented picture resets the episode")
        #expect(next(1, video: 2.5) == 0, "no fresh video: never held")
        #expect(next(0, video: nil) == 0)
    }

    @Test func missingFormatDoesNotBypassStartupReadinessOrGrace() {
        let base: FeedWatchdog.Snapshot = {
            var snap = Self.snap(now: 100, frameAge: 3, videoAge: 0.01)
            snap.lastAccessUnitAge = 0.01
            snap.decoderOutputExpected = true
            snap.lastDecoderOutputAge = 3
            snap.hasFormat = false
            return snap
        }()
        let holds: [(inout FeedWatchdog.Snapshot) -> Void] = [
            { $0.sawPicture = false },
            { $0.decoderOutputExpected = false },
            { $0.repairReady = false },
            { $0.pathReady = false },
            { $0.secondsSinceCameraSet = 0.1 },
            { $0.secondsSinceLastEnable = 0.1 },
            { $0.gimbalStickHeld = true },
            { $0.zoomPinchActive = true },
            { $0.lastDecoderOutputAge = 0.01 },
        ]
        for hold in holds {
            var snap = base
            hold(&snap)
            var dog = FeedWatchdog()
            #expect(dog.tick(snap) == .none)
            #expect(dog.stage == .idle)
        }
    }

    @Test func decoderRepairRespectsReadinessAndResetsOnlyOnFreshOutput() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 100, frameAge: 3, videoAge: 0.01)
        snap.lastAccessUnitAge = 0.01
        snap.decoderOutputExpected = true
        snap.lastDecoderOutputAge = 3
        snap.repairReady = false
        #expect(dog.tick(snap) == .none)
        #expect(dog.stage == .idle)
        snap.repairReady = true
        #expect(dog.tick(snap) == .rebuildVTSession)
        snap.now = 101
        snap.lastDecoderOutputAge = 0.01
        #expect(dog.tick(snap) == .none)
        #expect(dog.stage == .idle)
    }

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
        #expect(!FeedWatchdog.udpReceiveAlive(snap))
    }

    @Test func zoomSlewWithFreshStatusDoesNotTearUDP() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 4.2, videoAge: 4.2, statusAge: 0.3, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        snap.secondsSinceZoomSet = 1.0
        #expect(
            dog.tick(snap) == .none,
            "zoom 0xB8 SET can pause HEVC; status still on 9004 is not a dead socket")
        #expect(dog.stage == .idle)
        #expect(!dog.isRecovering)

        snap.secondsSinceZoomSet = 4.1
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "past zoom grace with young status is an encoder pause")
    }

    /// Finger on the zoom disc or the gimbal stick holds the encoder-pause repair.
    @Test(arguments: [false, true])
    func heldControlDoesNotGopCutWhileFingerIsDown(gimbalStick: Bool) {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 8, videoAge: 8, statusAge: 0.3, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        if gimbalStick {
            snap.secondsSinceGimbalThrow = 8
            snap.gimbalStickHeld = true
        } else {
            snap.secondsSinceZoomSet = 8
            snap.zoomPinchActive = true
        }
        #expect(
            dog.tick(snap) == .none,
            "finger down: encoder pause must not GOP-cut or rebuild UDP")
        #expect(dog.stage == .idle)
        snap.gimbalStickHeld = false
        snap.zoomPinchActive = false
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "after lift, past control grace is an encoder pause")
    }

    @Test func gimbalThrowHoldsEncoderPauseEnable() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 4.2, videoAge: 4.2, statusAge: 0.3, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        snap.secondsSinceGimbalThrow = 1.0
        #expect(
            dog.tick(snap) == .none,
            "gimbal throw can pause HEVC; status still on 9004 is not a dead socket")
        #expect(GimbalStick.shouldHoldWatchdog(secondsSinceThrow: 0))
        #expect(GimbalStick.shouldHoldWatchdog(secondsSinceThrow: 2.9))
        #expect(!GimbalStick.shouldHoldWatchdog(secondsSinceThrow: 3.0))
        #expect(!GimbalStick.shouldHoldWatchdog(secondsSinceThrow: nil))
        #expect(
            GimbalStick.shouldHoldWatchdog(
                secondsSinceThrow: 0.1, lastVideoPacketAge: 4.2))
        #expect(
            !GimbalStick.shouldHoldWatchdog(
                secondsSinceThrow: 0.1, lastVideoPacketAge: 5.1),
            "held stick must not block recover once HEVC has been dead stall+grace")
        snap.secondsSinceGimbalThrow = 3.1
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "past gimbal grace with young status is an encoder pause")
        var held = Self.snap(
            now: 10, frameAge: 5.1, videoAge: 5.1, statusAge: 0.3, bleAge: 0.2)
        held.secondsSinceLastEnable = 20
        held.secondsSinceGimbalThrow = 0.1
        var heldDog = FeedWatchdog()
        #expect(
            heldDog.tick(held) == .resendLiveViewEnable,
            "25 Hz throw stamp must not freeze recover after 5s of dead HEVC")
    }

    @Test func packetsWithoutCompletePicturesDoNotRenewTheEnableHold() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 100, frameAge: 9, videoAge: 0.01)
        snap.lastAccessUnitAge = 9
        snap.decoderOutputExpected = true
        snap.lastDecoderOutputAge = 9
        snap.secondsSinceLastEnable = 5
        #expect(
            !FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: 5, lastVideoPacketAge: 9),
            "no complete AU since before the enable: it did not cut a GOP")
        #expect(
            dog.tick(snap) == .resendLiveViewEnable,
            "fresh fragments must not hold the 8 s GOP window for a stalled assembly")
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

    /// Changed timings (build 158): the unanswered enable escalates after
    /// `enableAnswerWindow` (1.5 s), not `escalateAfter` (5 s). 36 of 37
    /// transport stalls credited to the enable only recovered after the
    /// endpoint rebuild. The #148 rule is kept: the enable still goes first
    /// (a 2 s reopen *instead of* the enable left lastVideo=none), and the
    /// rebuild now negotiates a fresh endpoint and re-arms ingest.
    @Test func enableThatProducesNoHEVCRebuildsUDPAfterOneEnable() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 2.8, videoAge: 2.8, statusAge: 0.0, bleAge: 70)
        snap.secondsSinceLastEnable = 20
        #expect(dog.tick(snap) == .resendLiveViewEnable, "#148: enable first, never a 2 s reopen")
        #expect(dog.stage == .resendEnable)

        snap.now = 11.4
        snap.lastDecodedFrameAge = 4.2
        snap.lastVideoPacketAge = 4.2
        snap.lastAccessUnitAge = 4.2
        snap.lastStatusAge = 0.0
        snap.secondsSinceLastEnable = 1.4
        #expect(dog.tick(snap) == .none, "the enable still has its answer window")
        #expect(dog.stage == .resendEnable)

        snap.now = 11.5
        snap.lastDecodedFrameAge = 4.3
        snap.lastVideoPacketAge = 4.3
        snap.lastAccessUnitAge = 4.3
        snap.secondsSinceLastEnable = 1.5
        #expect(
            dog.tick(snap) == .reopenDatalink,
            "unanswered enable: endpoint rebuild at 1.5 s even with young status")
        #expect(dog.isRecovering)
        snap.now = 13.6
        snap.lastDecodedFrameAge = 6.4
        snap.lastVideoPacketAge = 6.4
        snap.lastAccessUnitAge = 6.4
        snap.secondsSinceLastEnable = 2.1
        snap.secondsSinceLastRebuild = 2.1
        #expect(
            dog.tick(snap) == .none,
            "recent rebuild: do not GOP-cut or flap UDP; shell already enabled")
        #expect(dog.isRecovering)
        snap.now = 16.6
        snap.lastDecodedFrameAge = 9.4
        snap.lastVideoPacketAge = 9.4
        snap.lastAccessUnitAge = 9.4
        snap.secondsSinceLastEnable = 5.1
        snap.secondsSinceLastRebuild = 5.1
        #expect(
            dog.tick(snap) == .fullSessionRejoin,
            "rebuild kept the session and 9004 stayed silent, new handshake, not a 60 s wait (#218)"
        )
        #expect(dog.stage == .fullRejoin)
        snap.now = 21.7
        snap.lastDecodedFrameAge = 14.5
        snap.lastVideoPacketAge = 14.5
        snap.lastAccessUnitAge = 14.5
        snap.secondsSinceLastEnable = 10.2
        snap.secondsSinceLastRebuild = 10.2
        #expect(dog.tick(snap) == .none, "rejoin fired, shell owns the new session")
        #expect(dog.stage == .cooldown)
        #expect(!dog.isRecovering, "Reconnecting chip must not stay up after the ladder ends")
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

    /// Zoom, AF-C, gimbal and SET grace still hold the faster reopen rung.
    @Test(arguments: [0, 1, 2, 3])
    func controlGraceHoldsTheFasterReopen(control: Int) {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 2.8, videoAge: 2.8, statusAge: 0.0, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        #expect(dog.tick(snap) == .resendLiveViewEnable)
        snap.now = 11.6
        snap.lastDecodedFrameAge = 4.4
        snap.lastVideoPacketAge = 4.4
        snap.lastAccessUnitAge = 4.4
        snap.secondsSinceLastEnable = 1.6
        switch control {
        case 0: snap.zoomPinchActive = true
        case 1: snap.gimbalStickHeld = true
        case 2: snap.secondsSinceFocusTrackSet = 0.5
        default: snap.secondsSinceCameraSet = 0.5
        }
        #expect(dog.tick(snap) == .none, "a control gesture can pause HEVC: hold the reopen")
        #expect(dog.stage == .resendEnable)
    }

    @Test func encoderPauseDoesNotFlapUDPWhenBleIsStale() {
        var dog = FeedWatchdog()
        var snap = Self.snap(
            now: 10, frameAge: 4.2, videoAge: 4.2, statusAge: 0.0, bleAge: 70)
        snap.secondsSinceLastEnable = 20
        #expect(dog.tick(snap) == .resendLiveViewEnable)
        snap.now = 15.1
        snap.lastDecodedFrameAge = 9.3
        snap.lastVideoPacketAge = 9.3
        snap.lastAccessUnitAge = 9.3
        snap.lastStatusAge = 0.0
        snap.secondsSinceLastEnable = 5.1
        snap.secondsSinceLastRebuild = 2.0
        #expect(
            dog.tick(snap) == .none,
            "status young + recent rebuild: BLE age must not disable the 60s backoff")
        snap.now = 18.2
        snap.lastDecodedFrameAge = 12.4
        snap.lastVideoPacketAge = 12.4
        snap.lastAccessUnitAge = 12.4
        snap.secondsSinceLastEnable = 8.2
        snap.secondsSinceLastRebuild = 5.1
        #expect(
            dog.tick(snap) == .fullSessionRejoin,
            "the recent rebuild had escalateAfter to prove itself — re-handshake, never a second bind"
        )
    }

    @Test func trackedSetHoldsStallRepairLikeAFC() {
        var dog = FeedWatchdog()
        var snap = Self.snap(now: 10, frameAge: 3.0, videoAge: 3.0, statusAge: 0.2, bleAge: 0.2)
        snap.secondsSinceLastEnable = 20
        snap.secondsSinceCameraSet = 1.5
        #expect(
            dog.tick(snap) == .none,
            "tracking box 0xA6 / record / FORMAT can pause HEVC — do not GOP-cut (#219)")
        #expect(dog.stage == .idle)
        #expect(FeedWatchdog.shouldHoldForCameraSet(secondsSinceSet: 3.9))
        #expect(!FeedWatchdog.shouldHoldForCameraSet(secondsSinceSet: 4.0))
        #expect(!FeedWatchdog.shouldHoldForCameraSet(secondsSinceSet: nil))
        #expect(
            !FeedWatchdog.shouldHoldForCameraSet(secondsSinceSet: 1.0, lastVideoPacketAge: 6.0),
            "HEVC dead stall+grace before this SET — a SET burst cannot block recover forever")
        snap.now = 13
        snap.lastDecodedFrameAge = 6.0
        snap.lastVideoPacketAge = 6.0
        snap.lastAccessUnitAge = 6.0
        snap.secondsSinceCameraSet = 4.5
        #expect(dog.tick(snap) == .resendLiveViewEnable, "grace over, status young — encoder pause")
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

    @Test func assistVTStartSendsEnableWhenIdentityAlreadyPresented() {
        #expect(
            FeedWatchdog.shouldSendEnableForAssistVTStart(
                secondsSinceLastEnable: 0.4, hasPresentedPicture: true, liveViewEnableSends: 1),
            "identity already consumed the live-start IDR — new VT still needs a PLI")
        #expect(
            !FeedWatchdog.shouldSendEnableForAssistVTStart(
                secondsSinceLastEnable: 0.4, hasPresentedPicture: false, liveViewEnableSends: 1),
            "first enable still in flight — wait for that IDR")
        #expect(
            !FeedWatchdog.shouldSendEnableForAssistVTStart(
                secondsSinceLastEnable: 0.4, hasPresentedPicture: true, liveViewEnableSends: 2),
            "rapid A/B assist toggles collapse to one enable")
        #expect(
            FeedWatchdog.shouldSendEnableForAssistVTStart(
                secondsSinceLastEnable: 1.0, hasPresentedPicture: false, liveViewEnableSends: 1))
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

        now += 0.5
        var rebuilt = Self.snap(now: now, frameAge: 7, statusAge: 7, bleAge: 0.2)
        rebuilt.secondsSinceLastRebuild = FeedWatchdog.escalateAfter
        #expect(
            dog.tick(rebuilt) == .fullSessionRejoin,
            "one rebuild, then a new handshake exactly at escalateAfter")
        #expect(dog.stage == .fullRejoin)
        #expect(dog.isRecovering)

        now += 1
        #expect(dog.tick(Self.snap(now: now, frameAge: 8, statusAge: 8, bleAge: 0.2)) == .none)
        #expect(dog.stage == .cooldown)
        #expect(!dog.isRecovering)

        now += FeedWatchdog.cooldownDuration - 1
        #expect(
            dog.tick(Self.snap(now: now, frameAge: 22, statusAge: 22, bleAge: 0.2)) == .none,
            "cooldown holds — no 2 s flap")
        #expect(dog.stage == .cooldown)

        now += 1
        #expect(
            dog.tick(Self.snap(now: now, frameAge: 23, statusAge: 23, bleAge: 0.2))
                == .reopenDatalink,
            "still silent after cooldown — one more rebuild → rejoin cycle, never VT / SoftAP")
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
        #expect(dog.stage == .idle)
        #expect(dog.tick(stall) != .fullSessionRejoin, "give the bind escalateAfter first")

        now += 2.5
        stall = Self.snap(now: now, frameAge: 7.7, videoAge: 5.1, statusAge: 5.1, bleAge: 0.2)
        stall.secondsSinceLastRebuild = 5.1
        #expect(
            dog.tick(stall) == .fullSessionRejoin,
            "keepalive / SET-timeout rebuild proved nothing in escalateAfter — re-handshake, not a second bind"
        )
    }

    @Test func recentRebuildDoesNotRepeatRecoverEnable() {
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
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 1, lastVideoPacketAge: 5),
            "encoder-pause / missed IDR is FeedWatchdog.tick — extra 0x09/0xa8 GOP-cuts")
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 2),
            "already retried this hold — do not 1 Hz loop")
        #expect(
            !FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 60, secondsSinceLastRebuild: nil,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true,
                holdEnableCount: 2),
            "mid-session backoff is the watchdog ladder, not a third PLI")
    }

    @Test func liveVideoStaleAfterRebuildNilsClock() {
        #expect(
            FeedWatchdog.shouldTreatLiveVideoAsStale(
                lastVideoPacketAge: nil, hadVideo: true),
            "rebuild wiped lastVideo — analog/head-track must lift")
        #expect(
            !FeedWatchdog.shouldTreatLiveVideoAsStale(
                lastVideoPacketAge: nil, hadVideo: false),
            "first picture has no GOP yet — do not block gimbal")
        #expect(
            FeedWatchdog.shouldTreatLiveVideoAsStale(
                lastVideoPacketAge: 1.6, hadVideo: true))
        #expect(
            !FeedWatchdog.shouldTreatLiveVideoAsStale(
                lastVideoPacketAge: 0.4, hadVideo: true))
        #expect(
            FeedWatchdog.shouldTreatLiveVideoAsStale(
                lastVideoPacketAge: 0.1, hadVideo: true, recovering: true),
            "repair in flight — lift the stick")
        #expect(FeedWatchdog.shouldStartFeedRecovery(rebuildInFlight: false))
        #expect(
            !FeedWatchdog.shouldStartFeedRecovery(rebuildInFlight: true),
            "do not cancel a live UDP rebuild to start another")
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
            !FeedWatchdog.shouldReleaseIDRHold(
                awaitingIDR: true, udpReceiveAlive: true, secondsSinceLastEnable: 2,
                hasPresentedPicture: true),
            "still inside GOP grace")
        #expect(
            FeedWatchdog.shouldReleaseIDRHold(
                awaitingIDR: true, udpReceiveAlive: true, secondsSinceLastEnable: 8,
                hasPresentedPicture: true),
            "mid-session hold with UDP alive must not freeze the last frame forever")
        #expect(
            !FeedWatchdog.shouldReleaseIDRHold(
                awaitingIDR: true, udpReceiveAlive: true, secondsSinceLastEnable: 8,
                hasPresentedPicture: false),
            "first picture stays held until IRAP")
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
            flowHealthy: true,
            pathReady: true,
            hasFormat: true,
            decoderFailed: false,
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
