import OpenPocketViewCore
import QuartzCore
import VideoToolbox
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

@MainActor
final class FirstConnectTests: XCTestCase {
    func testCachedFrameRedrawDoesNotAdvanceSourceFreshness() async throws {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus()
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        decoder.sampleBus = bus
        var completions = 0
        var heartbeats = 0
        let identity = expectation(description: "Only the new source reaches the relay")
        identity.assertForOverFulfill = true
        decoder.onIdentityFrame = { _ in identity.fulfill() }
        decoder.onSourceFrame = { _ in completions += 1 }
        decoder.onPresentedFrame = { heartbeats += 1 }
        let buffer = ScopeTestBuffers.makeEdgeBuffer()
        decoder.handleDecodedFrame(buffer)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, decoder.lastPresentedAt == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let source = try XCTUnwrap(decoder.lastSourceFrameAt)
        let presented = try XCTUnwrap(decoder.lastPresentedAt)
        let decoded = bus.decodedFrames
        let firstHeartbeats = heartbeats
        let firstCompletions = completions
        decoder.handleDecodedFrame(buffer, isNewSourceFrame: false)
        let redrawDeadline = Date().addingTimeInterval(2)
        while Date() < redrawDeadline, completions == firstCompletions {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(completions, firstCompletions, "Exercise the cached repaint")
        XCTAssertEqual(decoder.lastPresentedAt, presented)
        XCTAssertEqual(decoder.lastSourceFrameAt, source)
        XCTAssertEqual(bus.decodedFrames, decoded)
        XCTAssertEqual(heartbeats, firstHeartbeats)
        await fulfillment(of: [identity], timeout: 1)

        // Dropping the final assist re-enqueues the held identity buffer directly.
        let container = CALayer()
        container.addSublayer(decoder.displayLayer)
        decoder.displayLayer.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        XCTAssertTrue(decoder.isDisplayReady)
        decoder.effects = LiveImageEffects()
        XCTAssertEqual(decoder.lastPresentedAt, presented)
        XCTAssertEqual(decoder.lastSourceFrameAt, source)
        XCTAssertEqual(heartbeats, firstHeartbeats)
        decoder.displayLayer.removeFromSuperlayer()
        decoder.reset()
        XCTAssertNil(decoder.lastSourceFrameAt)
    }

    func testFirstPictureEscalatesWhenNoVideo() {
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2),
            .wait,
            "sit in IDR grace — Mimo VPS is 25–167 ms")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2,
                secondsSinceLastRebuild: 0.4),
            .wait,
            "neverGotVideo — a leftover rebuild must not skip IDR grace")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 2, secondsSinceLastEnable: 2),
            .wait)
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 2, secondsSinceLastEnable: 8),
            .rebuildUDP)
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 4, secondsSinceLastEnable: 8),
            .rejoin)
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2,
                needsRecordingFormatPoke: true),
            .pokeRecordingFormat,
            "Pocket 3 black first picture: 1080 then boot 4K, not a second enable")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2),
            .wait,
            "Pocket 4 must not inherit the Pocket 3 format poke")
        XCTAssertTrue(CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: false))
        XCTAssertFalse(CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: true))
        XCTAssertFalse(CameraSoftAP.shouldIngestLiveVideo(ingestArmed: false))
        XCTAssertTrue(
            CameraSoftAP.shouldIngestLiveVideo(ingestArmed: true),
            "Mimo 20260828: HEVC at join+17ms, enable at +3s")
        XCTAssertTrue(
            CameraSoftAP.shouldIngestLiveVideo(
                ingestArmed: true, browsingMedia: true, operatorOverlayHeld: true),
            "#177: overlay/browse must not drop pktType 0x02")
        XCTAssertFalse(CameraSoftAP.shouldBeginIDRHoldOnEnable(hasPresentedPicture: true))
        XCTAssertTrue(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 3, alreadySettled: false),
            "frozen first IDR must not skip first-picture recover")
        XCTAssertFalse(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 3, alreadySettled: true))
        XCTAssertFalse(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 0.4, alreadySettled: false))
        XCTAssertFalse(CameraSoftAP.shouldExitPlaybackBeforeLiveEnable(inPlayback: false))
        XCTAssertTrue(CameraSoftAP.shouldExitPlaybackBeforeLiveEnable(inPlayback: true))
        XCTAssertTrue(CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: true))
        XCTAssertFalse(CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: false))
        XCTAssertTrue(CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(hasPicture: false))
        XCTAssertFalse(CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(hasPicture: true))
    }

    func testFirstPictureFrozenBurstRebuildsUDP() {
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 272, enableSends: 1, secondsSinceLastEnable: 5,
                secondsSinceLastVideo: 0.4),
            .resendEnable,
            "packets arriving but no IDR after 5s — one enable resend")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 272, enableSends: 2, secondsSinceLastEnable: 2,
                secondsSinceLastVideo: 0.4),
            .wait,
            "already resent once — wait for IDR, do not tear UDP")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 370, enableSends: 2, secondsSinceLastEnable: 2,
                secondsSinceLastVideo: 2.5),
            .wait,
            "fresh-boot log: 2.5s after enable is the IDR gap, not receive-died")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 420, enableSends: 1, secondsSinceLastEnable: 8,
                secondsSinceLastVideo: 8),
            .rebuildUDP,
            "do not resend 0x09/0xa8 on a frozen socket — that RST'd TCP 7001")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 800, enableSends: 2, secondsSinceLastEnable: 3,
                secondsSinceLastVideo: 0.2),
            .wait,
            "packets still climbing after the one resend — wait for VPS/SPS/PPS/IDR")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 272, enableSends: 2, secondsSinceLastEnable: 8,
                secondsSinceLastVideo: 8),
            .rebuildUDP,
            "272 then long silence is a dead receive, not a healthy counter")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 220, enableSends: 3, secondsSinceLastEnable: 2,
                secondsSinceLastVideo: 6.9, secondsSinceLastRebuild: 0.4),
            .wait,
            "do not rebuild again while the new socket is coming up")
        XCTAssertFalse(
            CameraSoftAP.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild: true, rebuildInFlight: true, secondsSinceLastRebuild: 0))
        XCTAssertFalse(
            CameraSoftAP.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: 10,
                videoFresh: true),
            "fresh HEVC — do not tear UDP because a SET write bounced")
        XCTAssertFalse(
            CameraSoftAP.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: nil,
                sawPicture: false),
            "keepalive must not tear UDP before the first picture")
        XCTAssertFalse(
            CameraSoftAP.shouldKeepaliveRebuildUDP(
                flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: 10,
                videoFresh: false, sawPicture: true, statusFresh: true),
            "status live + HEVC silent is encoder pause — do not keepalive-rebuild")
        XCTAssertTrue(
            FeedWatchdog.shouldHoldForGOPReset(secondsSinceLastEnable: 2.5),
            "LUT-toggle enable pause is the GOP cut")
        XCTAssertTrue(
            FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 2.2),
            "AF-C chip SET pause is not a dead socket")
        XCTAssertFalse(
            FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 4),
            "AF-C grace is 4 s")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 182, enableSends: 1, secondsSinceLastEnable: 10,
                secondsSinceLastVideo: 10, secondsSinceLastStatus: 0.0),
            .rebuildUDP,
            "first-picture P-frame burst then silence must rebuild even if status is alive")
        XCTAssertFalse(
            LiveFeedWarmup.isWarming(
                hasPresentedPicture: true, measuredFPS: 25,
                rollingIntervals: LiveFeedWarmup.minimumRollingIntervals,
                recovering: true, secondsSinceLastPresented: 3.0),
            "mid-session hunt / recover must not put Waiting for live-view back")
    }

    func testSetTimeoutWithFreshVideoDoesNotRebuildUDP() {
        XCTAssertFalse(
            CameraSoftAP.shouldRebuildAfterCommandTimeouts(
                timeoutsInWindow: 2, downlinkFresh: true, videoFresh: true,
                rebuildInFlight: false, secondsSinceLastRebuild: nil),
            "SET ACK late while video flows — leave the socket alone")
        XCTAssertFalse(
            CameraSetMailbox.timeoutImpliesUplinkFailure(.launchPending),
            "superseded shutter SET is not half-dead uplink")
        XCTAssertTrue(CameraSetMailbox.timeoutImpliesUplinkFailure(.waitLate))
        XCTAssertFalse(
            CameraSetMailbox.timeoutImpliesUplinkFailure(
                .waitLate, key: CameraSetMailbox.zoomOpcodeKey),
            "missing 0xB8 ACK is not half-dead uplink")
        XCTAssertFalse(
            FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 5, secondsSinceLastRebuild: 2.6,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: true),
            "one recover 0x09/0xa8 is enough")
        XCTAssertTrue(
            FeedWatchdog.shouldRepeatRecoverEnable(
                secondsSinceLastEnable: 2, secondsSinceLastRebuild: 0.4,
                pathReady: true, lastBleNotifyAge: 0.2, hadVideo: false),
            "neverGotVideo — resend enable even after a leftover rebuild")
    }

    func testHandshakeMissDoesNotKickWhileSoftAPUp() {
        XCTAssertFalse(
            CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: true),
            "SoftAP 192.168.2.x is up — retry handshake, do not pop pairing")
        XCTAssertTrue(CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: false))
        XCTAssertEqual(
            CameraSoftAP.handshakeTimeoutStep(pathReady: true, rebindsUsed: 0),
            .rebindUDP)
        XCTAssertEqual(
            CameraSoftAP.handshakeTimeoutStep(pathReady: false, rebindsUsed: 0),
            .fail)
        XCTAssertEqual(
            CameraSoftAP.handshakeTimeoutStep(
                pathReady: true, rebindsUsed: 0, inboundDatagrams: 12),
            .keepSocket)
        XCTAssertFalse(
            CameraSoftAP.canSendHandshake(receiveArmed: false, connectionReady: true),
            "bound-but-deaf: do not send 0x00 until receiveMessage is armed")
        XCTAssertTrue(CameraSoftAP.canSendHandshake(receiveArmed: true, connectionReady: true))
        XCTAssertTrue(
            CameraSoftAP.shouldRearmAfterError(isLiveConnection: true, canceled: true),
            "spurious 89 on a live fd must not kill the handshake reader")
        XCTAssertTrue(CameraSoftAP.shouldReuseDatalink(isClosed: false))
        XCTAssertFalse(
            CameraSoftAP.shouldReuseDatalink(isClosed: true),
            "close() is terminal — next connect must not inherit that UDP session")
        XCTAssertTrue(
            CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: false, isCancelled: false))
        XCTAssertFalse(
            CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: false, isClosed: false, isCancelled: false),
            "session already replaced this driver")
        XCTAssertFalse(
            CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: true, isCancelled: false),
            "cancelled open() after close() must not publish LIVE")
        XCTAssertFalse(
            CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: false, isCancelled: true),
            "cancelled open() must not publish LIVE after Disconnect")
    }

    func testDoNotEnableUntilWifiReady() {
        XCTAssertFalse(
            CameraSoftAP.shouldSendLiveViewEnable(
                pathReady: false, displayAttached: true, alreadySent: false),
            "first join: DHCP is not done — enable here blacks the feed")
        XCTAssertTrue(
            CameraSoftAP.shouldSendLiveViewEnable(
                pathReady: true, displayAttached: true, alreadySent: false))
        XCTAssertTrue(
            CameraSoftAP.shouldSendLiveViewEnable(
                pathReady: true, displayAttached: false, alreadySent: false),
            "first boot must enable before the layer attaches")
        XCTAssertFalse(
            CameraSoftAP.shouldSendLiveViewEnable(
                pathReady: true, displayAttached: true, alreadySent: true),
            "do not spam 0x09/0xa8")
        XCTAssertTrue(
            CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(alreadySent: false),
            "handshake is path proof — do not wait on getifaddrs")
        XCTAssertFalse(CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(alreadySent: true))
        XCTAssertTrue(
            CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: false),
            "Pocket live-entry sends 0x02/0x68 08 before 0x09/0xa8")
        XCTAssertFalse(
            CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: true),
            "Nano has no captured 0x68 pair")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 0, secondsSinceLastEnable: 8),
            .resendEnable,
            "never sent 0x09/0xa8 — do not sit on LINK")
    }

    func testAvcInterFrameCannotClaimFirstPictureBeforeRandomAccess() {
        let decoder = HevcDecoder()
        let sps: [UInt8] = [
            0x67, 0x64, 0x00, 0x1f, 0xac, 0xb4, 0x02, 0x80,
            0x2d, 0xd3, 0x50, 0x10, 0x40, 0x10, 0x6d, 0x0a, 0x13, 0x50,
        ]
        let pps: [UInt8] = [0x68, 0xee, 0x06, 0xf2, 0xc0]
        _ = decoder.decode(accessUnit: [0, 0, 1] + sps + [0, 0, 1] + pps)
        XCTAssertTrue(decoder.hasFormat)
        // A syntactically framed P-slice is not proof of a decodable first picture.
        XCTAssertFalse(decoder.decode(accessUnit: [0, 0, 1, 0x61, 0xe0, 0x01]))
        XCTAssertNil(decoder.lastPresentedAt)
        XCTAssertTrue(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: nil, alreadySettled: false))
        decoder.reset()
    }

    func testNanoAvcParameterSetsBuildFormat() {
        let decoder = HevcDecoder()
        let sps: [UInt8] = [
            0x67, 0x64, 0x00, 0x1f, 0xac, 0xb4, 0x02, 0x80,
            0x2d, 0xd3, 0x50, 0x10, 0x40, 0x10, 0x6d, 0x0a, 0x13, 0x50,
        ]
        let pps: [UInt8] = [0x68, 0xee, 0x06, 0xf2, 0xc0]
        var au: [UInt8] = [0, 0, 1]
        au += sps
        au += [0, 0, 1]
        au += pps
        XCTAssertFalse(decoder.decode(accessUnit: au), "SPS/PPS alone is not a picture")
        XCTAssertTrue(decoder.hasFormat, "Nano H.264 SPS/PPS must open a format")
        XCTAssertTrue(
            decoder.videoToolboxActive, "AVC must start in its final decoder before the first IDR")
        XCTAssertNil(decoder.lastPresentedAt)
        let rebuilds = decoder.vtRebuildCount
        var requests = 0
        decoder.onHandoffNeedsIDR = { requests += 1 }
        _ = decoder.decode(accessUnit: au)
        decoder.unlockHardwareDecoder()
        var effects = LiveImageEffects()
        effects.zebra = true
        decoder.effects = effects
        decoder.effects = LiveImageEffects()
        decoder.effects = effects
        XCTAssertEqual(decoder.vtRebuildCount, rebuilds)
        XCTAssertEqual(
            requests, 0, "Assist toggles must keep the decoder that receives the first IDR")
        XCTAssertTrue(decoder.videoToolboxActive)
        XCTAssertTrue(decoder.nalTypesSeen.contains(Avc.sps))
        XCTAssertTrue(decoder.nalTypesSeen.contains(Avc.pps))
        decoder.reset()
    }

    func testRebuildVTAfterInvalidSession() {
        XCTAssertTrue(HevcDecoder.shouldRebuildSession(status: kVTInvalidSessionErr))
        XCTAssertTrue(HevcDecoder.shouldRebuildSession(status: -12903))
        XCTAssertFalse(HevcDecoder.shouldRebuildSession(status: noErr))
        XCTAssertFalse(HevcDecoder.shouldRebuildSession(status: kVTParameterErr))
    }

    func testWaitUntilDisplayReadyTimesOutWhenDetached() async {
        let decoder = HevcDecoder()
        XCTAssertFalse(decoder.isDisplayReady, "layer is not in a view yet")
        let ready = await decoder.waitUntilDisplayReady(timeout: .milliseconds(50))
        XCTAssertFalse(ready)
    }

    func testRecoverKeepsLastFrameAndHoldsIDR() {
        XCTAssertFalse(
            FeedWatchdog.shouldFlushDisplayedImage(nextFrameReady: false),
            "do not flush to black before the next decoded frame")
        XCTAssertFalse(
            FeedWatchdog.shouldSendRecoverEnable(pathReady: true, decoderReady: false),
            "same first-connect gate: VT/display before 0x09/0xa8")
        XCTAssertFalse(
            FeedWatchdog.shouldPresentSample(hasPicture: false, awaitingIDR: false, isIDR: false),
            "do not present an empty sample")
        XCTAssertFalse(
            FeedWatchdog.shouldPresentSample(hasPicture: true, awaitingIDR: true, isIDR: false))

        let decoder = HevcDecoder()
        XCTAssertFalse(decoder.isPresentationReady, "detached layer is not ready")
        decoder.flushForRecovery()
        XCTAssertFalse(decoder.displayedImageRemoved, "recover must not wipe the last picture")
        XCTAssertTrue(decoder.awaitingIDR)
        decoder.rebuildPresentation()
        XCTAssertFalse(decoder.displayedImageRemoved)
        XCTAssertTrue(decoder.awaitingIDR)
        let resume = HevcDecoder()
        resume.prepareAfterForeground()
        XCTAssertFalse(
            resume.awaitingIDR,
            "foreground VT rebuild must not hold IDR before 0x09/0xa8 is sent")
    }

    func testRepeatedParameterSetsDoNotRebuildVT() {
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        decoder.effects = fx
        let sets =
            Self.startCodes + Self.vps + Self.startCodes + Self.sps + Self.startCodes + Self.pps
        _ = decoder.decode(accessUnit: sets)
        XCTAssertTrue(decoder.hasFormat)
        let created = decoder.vtRebuildCount
        XCTAssertGreaterThanOrEqual(created, 0)
        _ = decoder.decode(accessUnit: sets)
        _ = decoder.decode(accessUnit: sets)
        XCTAssertEqual(
            decoder.vtRebuildCount, created,
            "repeated VPS/SPS/PPS must not tear the VT session")
    }

    func testLUTOffDoesNotHoldIDROrFlush() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        var fx = LiveImageEffects()
        fx.lutDimension = 2
        fx.lutRGBA = Data(count: 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)
        decoder.effects = fx
        decoder.beginIDRHold()
        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.awaitingIDR, "LUT off is not a GOP reset")
        XCTAssertFalse(decoder.displayedImageRemoved)
        XCTAssertTrue(feed.isHidden)
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertFalse(decoder.videoToolboxActive, "no format yet — VT never opened")
    }

    func testPersistedAssistDoesNotStartVTBeforeFirstPicture() {
        // Format may start VT for persisted assist; must not GOP-reset
        // (onHandoffNeedsIDR) on parameter sets alone.
        let decoder = HevcDecoder()
        var idrRequests = 0
        decoder.onHandoffNeedsIDR = { idrRequests += 1 }
        var zebra = LiveImageEffects()
        zebra.zebra = true
        decoder.effects = zebra
        _ = decoder.decode(
            accessUnit: Self.startCodes + Self.vps + Self.startCodes + Self.sps
                + Self.startCodes + Self.pps)
        XCTAssertTrue(decoder.hasFormat)
        XCTAssertEqual(idrRequests, 0, "parameter sets must not send 0x09/0xa8")
    }

    func testFirstPresentDoesNotCutGOPForPersistedAssist() async {
        let decoder = HevcDecoder()
        var idrRequests = 0
        decoder.onHandoffNeedsIDR = { idrRequests += 1 }
        var zebra = LiveImageEffects()
        zebra.zebra = true
        decoder.effects = zebra
        _ = decoder.decode(
            accessUnit: Self.startCodes + Self.vps + Self.startCodes + Self.sps
                + Self.startCodes + Self.pps)
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, decoder.lastPresentedAt == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(decoder.lastPresentedAt)
        XCTAssertEqual(idrRequests, 0, "first present must not send 0x09/0xa8")
        decoder.unlockHardwareDecoder()
        XCTAssertEqual(
            idrRequests, 0,
            "unlock after a picture must not extra-IDR if VT already started")
    }

    func testAssistToggleKeepsVTAndRequestsIDROnlyOnFirstStart() async {
        let decoder = HevcDecoder()
        var idrRequests = 0
        decoder.onHandoffNeedsIDR = { idrRequests += 1 }

        _ = decoder.decode(
            accessUnit: Self.startCodes + Self.vps + Self.startCodes + Self.sps
                + Self.startCodes + Self.pps)
        XCTAssertTrue(decoder.hasFormat)
        XCTAssertFalse(decoder.videoToolboxActive, "clean feed stays on the HEVC layer")

        // Seed a real layer presentation. The clean path does not run VT;
        // injecting a decoded callback alone must not manufacture a present.
        XCTAssertTrue(decoder.enqueueDecodedFrame(ScopeTestBuffers.makeEdgeBuffer()))
        XCTAssertNotNil(decoder.lastPresentedAt)

        var lut = LiveImageEffects()
        lut.lutDimension = 2
        lut.lutRGBA = Data(count: 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)
        decoder.effects = lut
        XCTAssertEqual(idrRequests, 1, "first VT start needs one 0x09/0xa8")
        XCTAssertTrue(decoder.videoToolboxActive)

        decoder.effects = LiveImageEffects()
        XCTAssertEqual(idrRequests, 1, "LUT off must not GOP-reset")
        XCTAssertTrue(decoder.videoToolboxActive, "keep VT for the rest of the session")
        XCTAssertFalse(decoder.awaitingIDR)
        XCTAssertFalse(decoder.displayedImageRemoved)

        decoder.effects = lut
        XCTAssertEqual(idrRequests, 1, "second LUT on must not request another IDR")
        XCTAssertTrue(decoder.videoToolboxActive)

        var split = lut
        split.splitComparison = true
        decoder.effects = split
        XCTAssertEqual(
            idrRequests, 1, "LUT 50/50 is a compositor flag — must not GOP-reset (#218)")
        XCTAssertTrue(decoder.videoToolboxActive)
        XCTAssertFalse(decoder.awaitingIDR)
        XCTAssertFalse(decoder.displayedImageRemoved)
        decoder.effects = lut
        XCTAssertEqual(idrRequests, 1, "50/50 off must not request another IDR")
        XCTAssertFalse(decoder.awaitingIDR)
    }

    func testHoldDropsPFramesUntilIDR() {
        let decoder = HevcDecoder()
        _ = decoder.decode(
            accessUnit: Self.startCodes + Self.vps + Self.startCodes + Self.sps + Self.startCodes
                + Self.pps)
        XCTAssertTrue(decoder.hasFormat, "Pocket VPS/SPS/PPS must build a format")
        decoder.beginIDRHold()
        let trail: [UInt8] = [0, 0, 1, 0x02, 0xAA, 0xBB]
        XCTAssertFalse(
            decoder.decode(accessUnit: trail), "P-frame while holding IDR must not enqueue")
        XCTAssertTrue(decoder.awaitingIDR)
        XCTAssertFalse(decoder.displayedImageRemoved)
    }

    private static let startCodes: [UInt8] = [0, 0, 1]
    private static let vps = hex(
        "40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
    private static let sps = hex(
        "42010121600000030000030000030000030096a00280802d17aeedc9ae5d4d404040410000030001000003001908"
    )
    private static let pps = hex("4401c17312240890")
}

private func hex(_ s: String) -> [UInt8] {
    var out = [UInt8]()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

/// SIMULATED native OS dependencies exercise CameraSession's donor loop before extraction.
@MainActor
final class ConnectionRunDonorTraceTests: XCTestCase {
    func testColdAccessPointDonorCommandAndRegistrationOrder() async {
        let peer = ConnectionDonorPeer()
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        session.connect(peer.camera)
        await finish(session)
        XCTAssertEqual(peer.trace.filter { !$0.hasPrefix("heartbeat") && $0 != "BLE keepalive" }, [
            "GATT", "BLE wake", "BLE pair", "sleep 0.2", "BLE AP-wake", "sleep 0.6",
            "BLE SSID", "BLE password", "join AP", "persist", "make AP", "attach",
            "open AP", "registered", "enable", "open returned",
        ])
        XCTAssertEqual(peer.join?.ssid, peer.network)
        XCTAssertEqual(peer.join?.password, "SIMULATED-PASSWORD")
        XCTAssertFalse(peer.join?.persist ?? true)
        XCTAssertEqual(peer.writes.filter { $0.cmdId == 0x45 }.count, 1)
        XCTAssertEqual(peer.trace.filter { $0 == "enable" }.count, 1)
        XCTAssertEqual(peer.stages, [.connectingGatt, .pairing, .pairing, .readingWifiCreds,
            .readingWifiCreds, .readingWifiCreds, .joiningWifi, .openingDatalink])
        print("SIMULATED CONNECTION DONOR cold: \(peer.trace)")
    }

    func testWarmAccessPointDonorSkipsOnlySettlesAndCredentialReads() async {
        let peer = ConnectionDonorPeer(cached: true)
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        session.connect(peer.camera)
        await finish(session)
        XCTAssertEqual(peer.trace.filter { !$0.hasPrefix("heartbeat") && $0 != "BLE keepalive" }, [
            "GATT", "BLE wake", "BLE pair", "BLE AP-wake", "join AP", "persist",
            "make AP", "attach", "open AP", "registered", "enable", "open returned",
        ])
        XCTAssertFalse(peer.writes.contains { $0.cmdSet == 7 && [7, 0x0e].contains($0.cmdId) })
        XCTAssertEqual(peer.trace.filter { $0 == "enable" }.count, 1)
        print("SIMULATED CONNECTION DONOR warm: \(peer.trace)")
    }

    func testDeferredPairDonorDropsDrainBeforeThreeSecondRetry() async {
        let peer = ConnectionDonorPeer(cached: true, deferred: true)
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        session.connect(peer.camera)
        await finish(session)
        XCTAssertEqual(peer.trace.filter { !$0.hasPrefix("heartbeat") && $0 != "BLE keepalive" }, [
            "GATT", "BLE wake", "BLE pair", "disconnect BLE", "sleep 3.0", "GATT",
            "BLE wake", "BLE pair", "BLE AP-wake", "join AP", "persist", "make AP",
            "attach", "open AP", "registered", "enable", "open returned",
        ])
        XCTAssertEqual(peer.writes.filter { $0.cmdId == 0x45 }.count, 2)
        XCTAssertEqual(peer.trace.filter { $0 == "enable" }.count, 1)
        print("SIMULATED CONNECTION DONOR deferred: \(peer.trace)")
    }

    func testWiFiStationDonorJoinsPhoneBeforeCapturedStationCommands() async {
        await station(hotspot: false)
    }

    func testHotspotStationDonorNeverJoinsPhoneAndRequiresIdentityBeforeRegistration() async {
        await station(hotspot: true)
    }

    private func station(hotspot: Bool) async {
        let peer = ConnectionDonorPeer(station: true, hotspot: hotspot)
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        session.connect(peer.camera)
        await finish(session)
        var expected = ["GATT", "BLE wake", "BLE pair"]
        if !hotspot { expected.append("join host") }
        expected += ["BLE SSID", "BLE 02/e1", "sleep 2.0", "BLE 07/39", "BLE 07/48",
            "BLE 07/39", "sleep 10.0", "BLE 07/47", "discover", "dispose", "make station",
            "attach", "open identity", "open returned", "UDP identity", "complete registration",
            "registered", "enable"]
        XCTAssertEqual(peer.trace.filter { !$0.hasPrefix("heartbeat") && $0 != "BLE keepalive" }, expected)
        XCTAssertEqual(session.stationHost, "198.51.100.7")
        XCTAssertEqual(peer.trace.filter { $0 == "enable" }.count, 1)
        XCTAssertFalse(peer.trace.contains("persist"), "Station does not persist camera-AP credentials")
        print("SIMULATED CONNECTION DONOR station hotspot=\(hotspot): \(peer.trace)")
    }

    func testSoftAPDonorStopsAfterSixHandshakeMissesWithFiveHalfSecondPauses() async {
        let peer = ConnectionDonorPeer(cached: true)
        peer.handshakeMisses = 6
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        session.connect(peer.camera)
        await finish(session, expectsFailure: true)
        XCTAssertEqual(peer.trace.filter { $0 == "open AP" }.count, 6)
        XCTAssertEqual(peer.trace.filter { $0 == "sleep 0.5" }.count, 5)
        XCTAssertFalse(peer.trace.contains("registered"))
        XCTAssertFalse(peer.trace.contains("enable"))
        XCTAssertEqual(peer.trace.filter { $0 == "make AP" }.count, 1, "Retry retains its actual endpoint")
        print("SIMULATED CONNECTION DONOR retry budget: \(peer.trace)")
    }

    func testApprovalObserverReplacementKeepsOnlySuccessorCommitAndEnable() async {
        let peer = ConnectionDonorPeer(cached: true)
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        var replaced = false
        session.onChromePublished = { [weak session] in
            guard let session, !replaced, session.phase == .awaitingApproval else { return }
            replaced = true
            session.disconnect()
            session.connect(peer.camera)
        }
        session.connect(peer.camera)
        await finish(session)
        XCTAssertTrue(replaced)
        XCTAssertEqual(peer.trace.filter { $0 == "GATT" }.count, 2)
        XCTAssertEqual(peer.trace.filter { $0 == "persist" }.count, 1)
        XCTAssertEqual(peer.trace.filter { $0 == "enable" }.count, 1)
        XCTAssertNil(session.lastConnectError)
        XCTAssertEqual(session.connectedCamera?.id, peer.camera.id)
    }

    func testLiveObserverDisconnectRetiresBeforeInitialEnable() async {
        let peer = ConnectionDonorPeer(cached: true)
        let session = peer.session()
        defer { session.disconnect(); session.decoder.close() }
        var disconnected = false
        session.onChromePublished = { [weak session] in
            guard let session, !disconnected, session.phase == .live else { return }
            disconnected = true; session.disconnect()
        }
        session.connect(peer.camera)
        for _ in 0..<1000 { if disconnected { break }; await Task.yield() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(disconnected)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.lastConnectError)
        XCTAssertFalse(peer.trace.contains("enable"))
    }

    func testBorrowedConnectDoesNotPrepareSharedDecoderOrSendCommands() async {
        let peer = ConnectionDonorPeer(cached: true)
        let decoder = HevcDecoder()
        let session = peer.session(borrowing: decoder)
        defer { session.disconnect(); decoder.close() }
        session.status.isRecording = true
        session.connect(peer.camera)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.status.isRecording)
        XCTAssertTrue(peer.trace.isEmpty)
        XCTAssertTrue(peer.writes.isEmpty)
    }

    func testConnectionCloseWhileRecordingNeverSendsStopRecord() async {
        let peer = ConnectionDonorPeer(cached: true)
        let session = peer.session()
        defer { session.decoder.close() }
        session.status.isRecording = true
        session.connect(peer.camera)
        await finish(session)
        session.disconnect()
        let stop = Commands.recordStop()
        XCTAssertFalse(peer.writes.contains {
            $0.cmdSet == stop.cmdSet && $0.cmdId == stop.cmdId && $0.payload == stop.payload
        })
    }

    private func finish(_ session: CameraSession, expectsFailure: Bool = false) async {
        for _ in 0..<1000 {
            if session.phase == .live { await Task.yield(); return }
            if case .failed(let reason) = session.phase { if !expectsFailure { XCTFail(reason) }; return }
            await Task.yield()
        }
        XCTFail("SIMULATED donor did not reach the registered boundary")
    }
}

@MainActor
private final class ConnectionDonorPeer {
    var time: TimeInterval = 0
    var trace: [String] = []
    var writes: [Duml.Frame] = []
    var stages: [OpenPocketViewCore.ConnectionPhase] = []
    var wakes: [(TimeInterval, @MainActor @Sendable () -> Void)] = []
    var continuation: AsyncStream<Duml.Frame>.Continuation?
    var current: (any DjiAppleConnectionEndpoint)?
    var join: DjiAppleConnectionTransport.AccessPointJoin?
    weak var app: CameraSession?
    let network = "OsmoPocket4-SIMULATED"
    let cached: Bool
    var deferred: Bool
    let station: Bool
    let hotspot: Bool
    var stationSwitched = false
    var handshakeMisses = 0
    enum Failure: LocalizedError {
        case handshake
        var errorDescription: String? { "SIMULATED handshake miss" }
    }
    let camera = FoundCamera(id: UUID(uuidString: "FC064E5E-2B01-4F6B-94D2-663C03C8F001")!,
        name: "OsmoPocket4-SIMULATED", model: CameraModel.resolve(modelId: 0x0021, name: "OsmoPocket4-SIMULATED", brand: .dji), modelId: 0x0021)

    init(cached: Bool = false, deferred: Bool = false, station: Bool = false, hotspot: Bool = false) {
        self.cached = cached; self.deferred = deferred; self.station = station; self.hotspot = hotspot
    }
    var timing: DjiAppleConnectionTiming {
        .init(wallNow: { [unowned self] in time }, uptime: { [unowned self] in time },
            sleep: { [unowned self] duration in
                let c = duration.components
                let seconds = Double(c.seconds) + Double(c.attoseconds) / 1e18
                trace.append(String(format: "sleep %.1f", seconds))
                advance(to: time + seconds)
            })
    }
    var exchangeTiming: DjiAppleExchangeTiming {
        .init(now: { [unowned self] in time }, schedule: { [unowned self] duration, wake in
            let c = duration.components
            wakes.append((time + Double(c.seconds) + Double(c.attoseconds) / 1e18, wake))
        })
    }
    var heartbeatTiming: DjiAppleHeartbeatTiming {
        .init(wallNow: { [unowned self] in time }, uptime: { [unowned self] in time },
            schedule: { [unowned self] duration, wake in
                trace.append("heartbeat scheduled")
                let c = duration.components
                wakes.append((time + Double(c.seconds) + Double(c.attoseconds) / 1e18, wake))
            })
    }
    func advance(to end: TimeInterval) {
        while let next = wakes.enumerated().filter({ $0.element.0 <= end })
            .min(by: { $0.element.0 < $1.element.0 }) {
            time = next.element.0; wakes.remove(at: next.offset); next.element.1()
        }
        time = end
    }
    func send(_ frame: Duml.Frame, viaUDP: Bool = false) {
        writes.append(frame)
        let label: String
        switch (frame.cmdSet, frame.cmdId) {
        case (0, 0x2b): label = frame.payload == [4, 0] ? "wake" : "keepalive"
        case (7, 0x45): label = "pair"
        case (0x53, 0x10): label = "AP-wake"
        case (7, 7): label = "SSID"
        case (7, 0x0e): label = "password"
        default: label = String(format: "%02x/%02x", frame.cmdSet, frame.cmdId)
        }
        trace.append(viaUDP ? "UDP identity" : "BLE \(label)")
        if label != "keepalive", let app { stages.append(app.phase) }
        let payload: [UInt8]
        switch (frame.cmdSet, frame.cmdId) {
        case (7, 0x45):
            payload = deferred ? [0, 6] : [0, 1]; deferred = false
        case (0x53, 0x10): payload = [1, 0, 0, 0]
        case (7, 7): payload = [0] + Duml.packString(network)
        case (7, 0x0e): payload = [0] + Duml.packString("SIMULATED-PASSWORD")
        case (7, 0x39): payload = [0, stationSwitched ? 1 : 0]
        case (7, 0x48): stationSwitched = true; payload = [0, 0]
        case (7, 0x47): payload = [0, 0]
        default: return
        }
        continuation?.yield(.init(sender: frame.receiver, receiver: frame.sender, seq: frame.seq,
            flags: Duml.flagResponse, cmdSet: frame.cmdSet, cmdId: frame.cmdId, payload: payload))
    }
    var transport: DjiAppleConnectionTransport {
        .init(bluetooth: .init(connect: { [unowned self] _ in
            trace.append("GATT"); if let app { stages.append(app.phase) }
        }, frames: { [unowned self] in
            let pair = AsyncStream.makeStream(of: Duml.Frame.self)
            continuation = pair.continuation; return pair.stream
        }, send: { [unowned self] in send($0) }, disconnectAndWait: { [unowned self] in
            trace.append("disconnect BLE"); continuation?.finish()
        }, retryableDrop: { _ in false }), network: .init(cameraPathReady: { true },
            stationPathReady: { _ in true }, joinAccessPoint: { [unowned self] request in
                trace.append("join AP"); join = request; if let app { stages.append(app.phase) }
            }, rejectsCredentials: { _ in false }, joinHost: { [unowned self] _, _ in
                trace.append("join host"); return "192.0.2.2"
            }, leave: { _ in }, currentSSID: { nil }, candidates: { [unowned self] _ in
                trace.append("discover"); return station ? ["198.51.100.7"] : []
            }, subnetSize: { _ in nil }),
            makeEndpoint: { [unowned self] _, host, _ in
                trace.append(host == nil ? "make AP" : "make station")
                return ConnectionDonorEndpoint(peer: self)
            }, localNetworkDenied: { _ in false })
    }
    func session(borrowing decoder: HevcDecoder? = nil) -> CameraSession {
        let session = CameraSession(borrowing: decoder, heartbeatTiming: heartbeatTiming)
        app = session
        if station {
            session.connectionSetup = hotspot ? .phoneHotspot : .wifi
            session.stationNetwork = network
        }
        session.connectionNativePeers = .init(transport: transport, timing: timing,
            exchangeTiming: exchangeTiming, currentEndpoint: { [unowned self] in current },
            attach: { [unowned self] endpoint in
                trace.append(endpoint == nil ? "dispose" : "attach")
                if endpoint == nil { current?.close() }
                current = endpoint
            }, registered: { [unowned self, weak session] _, attempt in
                trace.append("registered"); session?.phase = .live
                guard attempt.isCurrent else { return }; trace.append("enable")
            }, ssid: cached ? network : nil, password: cached ? "SIMULATED-PASSWORD" : nil,
            stationNetwork: station ? .init(ssid: network, password: "SIMULATED-PASSWORD", hotspot: hotspot) : nil, persist: { [unowned self] _, _ in trace.append("persist") },
            forget: { [unowned self] in trace.append("forget") })
        session.sessionHeartbeat.endpoint = .init(writeBLE: { [unowned self] in send($0) },
            registerDatalink: {}, transport: { .init() })
        return session
    }
}

@MainActor
private final class ConnectionDonorEndpoint: DjiAppleConnectionEndpoint {
    unowned let peer: ConnectionDonorPeer
    var isClosed = false
    init(peer: ConnectionDonorPeer) { self.peer = peer }
    func open(identityOnly: Bool, afterHandshake: (@MainActor () async -> Void)?) async throws {
        peer.trace.append(identityOnly ? "open identity" : "open AP")
        if peer.handshakeMisses > 0 {
            peer.handshakeMisses -= 1; throw ConnectionDonorPeer.Failure.handshake
        }
        if let app = peer.app { peer.stages.append(app.phase) }
        await afterHandshake?()
        peer.trace.append("open returned")
    }
    func send(_ frame: Duml.Frame) -> UInt16 { peer.send(frame, viaUDP: true); return frame.seq }
    func completeRegistration() { peer.trace.append("complete registration") }
    func close() { isClosed = true; peer.trace.append("close") }
}
