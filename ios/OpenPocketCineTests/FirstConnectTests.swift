import VideoToolbox
import XCTest
import OpenPocketViewCore
@testable import OpenPocketCine

@MainActor
final class FirstConnectTests: XCTestCase {
    func testFirstPictureEscalatesWhenNoVideo() {
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2),
            .resendEnable)
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2,
                secondsSinceLastRebuild: 0.4),
            .resendEnable,
            "neverGotVideo — a leftover rebuild must not skip 0x09/0xa8")
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 2, secondsSinceLastEnable: 2),
            .rebuildUDP)
        XCTAssertEqual(
            CameraSoftAP.firstPictureStep(
                videoPackets: 0, enableSends: 4, secondsSinceLastEnable: 2),
            .rejoin)
        XCTAssertTrue(CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: false))
        XCTAssertFalse(CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: true))
        XCTAssertFalse(
            CameraSoftAP.shouldIngestLiveVideo(liveViewEnabled: false),
            "0x02 before 0x09/0xa8 is the previous GOP — do not decode it")
        XCTAssertTrue(CameraSoftAP.shouldIngestLiveVideo(liveViewEnabled: true))
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
        XCTAssertTrue(
            FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 2.6, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: true),
            "after one UDP rebuild, do not flap on a 2s stall")
        XCTAssertFalse(
            FeedWatchdog.shouldHoldRebuildAfterRecentUDP(
                secondsSinceLastRebuild: 2.6, pathReady: true, lastBleNotifyAge: 0.2,
                hadVideo: false),
            "first picture is not a live flap")
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
        XCTAssertTrue(CameraSoftAP.isHandshakeAck(
            [0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertFalse(CameraSoftAP.isHandshakeAck(
            [0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x02, 0x00]))
        XCTAssertFalse(
            CameraSoftAP.canSendHandshake(receiveArmed: false, connectionReady: true),
            "bound-but-deaf: do not send 0x00 until receiveMessage is armed")
        XCTAssertTrue(CameraSoftAP.canSendHandshake(receiveArmed: true, connectionReady: true))
        let ack = DumlTransport.handshakeDatagram(sessionId: 0x1234, seq: 0, baseSeq: 0xB887)
        XCTAssertTrue(CameraSoftAP.isHandshakeAck(ack), "inbound 0x00 is the handshake ACK")
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

    func testPinDatalinkToCameraInterfaceNotEn0() {
        let addrs = [
            CameraSoftAP.InterfaceAddress(name: "en0", ipv4: "192.168.1.20"),
            CameraSoftAP.InterfaceAddress(name: "en2", ipv4: "192.168.2.15"),
        ]
        XCTAssertEqual(CameraSoftAP.cameraLocalIPv4(in: addrs), "192.168.2.15")
        XCTAssertEqual(CameraSoftAP.preferredInterfaceName(
            cameraNames: ["en2"], available: ["en0", "en2"]), "en2")
        XCTAssertTrue(CameraSoftAP.shouldRebuildFlow(.writeRejected))
        XCTAssertTrue(Duml.shouldHoldReply(set: 0x02, cmd: 0xB8))
    }

    func testNanoAvcParameterSetsBuildFormat() {
        let decoder = HevcDecoder()
        let sps: [UInt8] = [0x67, 0x64, 0x00, 0x1f, 0xac, 0xb4, 0x02, 0x80,
                            0x2d, 0xd3, 0x50, 0x10, 0x40, 0x10, 0x6d, 0x0a, 0x13, 0x50]
        let pps: [UInt8] = [0x68, 0xee, 0x06, 0xf2, 0xc0]
        var au: [UInt8] = [0, 0, 1]
        au += sps
        au += [0, 0, 1]
        au += pps
        XCTAssertFalse(decoder.decode(accessUnit: au), "SPS/PPS alone is not a picture")
        XCTAssertTrue(decoder.hasFormat, "Nano H.264 SPS/PPS must open a format")
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
        let sets = Self.startCodes + Self.vps + Self.startCodes + Self.sps + Self.startCodes + Self.pps
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

        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, decoder.lastPresentedAt == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
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
    }

    func testHoldDropsPFramesUntilIDR() {
        let decoder = HevcDecoder()
        _ = decoder.decode(accessUnit: Self.startCodes + Self.vps + Self.startCodes + Self.sps + Self.startCodes + Self.pps)
        XCTAssertTrue(decoder.hasFormat, "Pocket VPS/SPS/PPS must build a format")
        decoder.beginIDRHold()
        let trail: [UInt8] = [0, 0, 1, 0x02, 0xAA, 0xBB]
        XCTAssertFalse(decoder.decode(accessUnit: trail), "P-frame while holding IDR must not enqueue")
        XCTAssertTrue(decoder.awaitingIDR)
        XCTAssertFalse(decoder.displayedImageRemoved)
    }

    private static let startCodes: [UInt8] = [0, 0, 1]
    private static let vps = hex("40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
    private static let sps = hex("42010121600000030000030000030000030096a00280802d17aeedc9ae5d4d404040410000030001000003001908")
    private static let pps = hex("4401c17312240890")
}

private func hex(_ s: String) -> [UInt8] {
    var out = [UInt8](); var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!); i = j
    }
    return out
}
