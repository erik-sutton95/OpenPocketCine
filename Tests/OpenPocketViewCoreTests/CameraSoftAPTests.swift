import Testing
@testable import OpenPocketViewCore

@Suite struct CameraSoftAPTests {
    @Test func phoneAddressOnCameraAP() {
        #expect(CameraSoftAP.isAssociatedIPv4("192.168.2.15"))
        #expect(CameraSoftAP.isAssociatedIPv4("192.168.2.2"))
        #expect(CameraSoftAP.isAssociatedIPv4("192.168.2.254"))
        #expect(!CameraSoftAP.isAssociatedIPv4("192.168.2.1"))    // camera
        #expect(!CameraSoftAP.isAssociatedIPv4("192.168.2.0"))
        #expect(!CameraSoftAP.isAssociatedIPv4("192.168.2.255"))
        #expect(!CameraSoftAP.isAssociatedIPv4("192.168.1.15"))
        #expect(!CameraSoftAP.isAssociatedIPv4("10.0.0.2"))
        #expect(!CameraSoftAP.isAssociatedIPv4(""))
        #expect(!CameraSoftAP.isAssociatedIPv4("192.168.2"))
    }

    @Test func pathReadyRequiresPhoneAddress() {
        #expect(!CameraSoftAP.isPathReady(localIPv4s: []))
        #expect(!CameraSoftAP.isPathReady(localIPv4s: ["127.0.0.1", "192.168.1.10"]))
        #expect(!CameraSoftAP.isPathReady(localIPv4s: ["192.168.2.1"]))
        #expect(CameraSoftAP.isPathReady(localIPv4s: ["192.168.1.10", "192.168.2.42"]))
    }

    @Test func leftoverCameraPathDoesNotBlockTheOtherBody() {
        #expect(!CameraSoftAPSwitch.shouldAbortBecausePathStillReady(true))
        #expect(!CameraSoftAPSwitch.shouldAbortBecausePathStillReady(false))
        #expect(CameraSoftAPSwitch.isOnTarget(currentSSID: nil, target: "OsmoNano-BBBB"))
        #expect(CameraSoftAPSwitch.isOnTarget(currentSSID: "OsmoNano-BBBB", target: "OsmoNano-BBBB"))
        #expect(!CameraSoftAPSwitch.isOnTarget(currentSSID: "OsmoPocket4P-AAAA", target: "OsmoNano-BBBB"))
        #expect(
            CameraSoftAPSwitch.ssidToKick(
                currentSSID: "OsmoPocket4P-AAAA", target: "OsmoNano-BBBB")
                == "OsmoPocket4P-AAAA")
        #expect(
            CameraSoftAPSwitch.ssidToKick(currentSSID: "OsmoNano-BBBB", target: "OsmoNano-BBBB")
                == nil)
    }

    @Test func leftoverGOPBeforeEnableIsNotLiveVideo() {
        #expect(!CameraSoftAP.shouldIngestLiveVideo(liveViewEnabled: false),
            "0x02 during handshake is the previous session's GOP")
        #expect(CameraSoftAP.shouldIngestLiveVideo(liveViewEnabled: true))
        #expect(CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: false),
            "Pocket live-entry sends 0x02/0x68 08 before 0x09/0xa8")
        #expect(!CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: true),
            "Nano has no captured 0x68 pair")
    }

    /// First connect: join callback fires before DHCP. Enable here is the black feed.
    /// Display attach is not a gate — waiting ~2 s piles mid-GOP P-frames.
    @Test func doNotEnableUntilWifiReady() {
        #expect(!CameraSoftAP.shouldSendLiveViewEnable(
            pathReady: false, displayAttached: true, alreadySent: false))
        #expect(CameraSoftAP.shouldSendLiveViewEnable(
            pathReady: true, displayAttached: false, alreadySent: false),
            "enable as soon as SoftAP is up, even if the layer is not attached")
        #expect(!CameraSoftAP.shouldSendLiveViewEnable(
            pathReady: true, displayAttached: true, alreadySent: true))
        #expect(CameraSoftAP.shouldSendLiveViewEnable(
            pathReady: true, displayAttached: true, alreadySent: false))
    }

    @Test func rebuildVTAfterInvalidSession() {
        #expect(CameraSoftAP.shouldRebuildVTSession(status: -12903))
        #expect(!CameraSoftAP.shouldRebuildVTSession(status: 0))
        #expect(!CameraSoftAP.shouldRebuildVTSession(status: -12900))
    }

    /// Home Wi-Fi stays on `en0`; SoftAP DHCP is a different name. Pinning
    /// `requiredInterfaceType = .wifi` alone picks `en0` and later writes die
    /// with `nw_flow_add_write_request … cannot accept write requests`.
    @Test func pinToInterfaceThatOwnsCameraAddress() {
        let addrs = [
            CameraSoftAP.InterfaceAddress(name: "en0", ipv4: "192.168.1.20"),
            CameraSoftAP.InterfaceAddress(name: "en2", ipv4: "192.168.2.15"),
            CameraSoftAP.InterfaceAddress(name: "lo0", ipv4: "127.0.0.1"),
        ]
        #expect(CameraSoftAP.cameraLocalIPv4(in: addrs) == "192.168.2.15")
        #expect(CameraSoftAP.cameraInterfaceNames(in: addrs) == ["en2"])
        #expect(CameraSoftAP.preferredInterfaceName(
            cameraNames: ["en2"], available: ["en0", "en2", "pdp_ip0"]) == "en2")
        #expect(CameraSoftAP.preferredInterfaceName(
            cameraNames: ["en2"], available: ["en0", "pdp_ip0"]) == nil)
        #expect(CameraSoftAP.cameraLocalIPv4(in: [
            .init(name: "en0", ipv4: "192.168.1.20")
        ]) == nil)
    }

    @Test func firstPictureEscalatesPastEnableSpam() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 0.5) == .wait)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2) == .resendEnable)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 2, secondsSinceLastEnable: 2) == .rebuildUDP)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 4, secondsSinceLastEnable: 2) == .rejoin)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 10, enableSends: 4, secondsSinceLastEnable: 5,
            secondsSinceLastVideo: 0.2) == .wait)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 800, enableSends: 1, secondsSinceLastEnable: 3,
            secondsSinceLastVideo: 0.2) == .wait,
            "live mid-GOP — do not second-enable at 2s; camera pauses and we tear UDP")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 800, enableSends: 1, secondsSinceLastEnable: 5,
            secondsSinceLastVideo: 0.2) == .resendEnable,
            "still no picture after 5s of P-frames — one IDR request")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 800, enableSends: 2, secondsSinceLastEnable: 3,
            secondsSinceLastVideo: 0.2) == .wait,
            "already resent once while packets climb — do not tear UDP")
    }

    /// Fresh-boot log: 370 pkts, NAL 1/35/40, format=0. Enable #2 then
    /// lastVideo=2.5s was treated as “receive died” and the rebuild killed
    /// the only socket that would have received the IDR.
    @Test func firstPictureWaitsIDRGapAfterEnable() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 370, enableSends: 2, secondsSinceLastEnable: 2,
            secondsSinceLastVideo: 2.5) == .wait,
            "2.5s silence after 0x09/0xa8 is the GOP cut, not a dead receive")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 370, enableSends: 1, secondsSinceLastEnable: 2,
            secondsSinceLastVideo: 0.4) == .wait,
            "do not resend enable on a live mid-GOP stream at 2s")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 370, enableSends: 2, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 8) == .rebuildUDP,
            "past IDR grace and still silent — then rebuild")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 182, enableSends: 1, secondsSinceLastEnable: 10,
            secondsSinceLastVideo: 10, secondsSinceLastStatus: 0.0) == .rebuildUDP,
            "182 P-frames then silence with live status is a dead GOP, not AF-C hunt")
    }

    @Test func foregroundRecoverSkipsFreshPictureAndEscalatesWhenFrozen() {
        #expect(!CameraSoftAP.shouldRecoverAfterForeground(secondsSinceLastPresented: 0.4))
        #expect(CameraSoftAP.shouldRecoverAfterForeground(secondsSinceLastPresented: 2.0))
        #expect(CameraSoftAP.shouldRecoverAfterForeground(secondsSinceLastPresented: nil))
        #expect(!CameraSoftAP.shouldEscalateForegroundRecover(secondsSinceLastPresented: 0.5))
        #expect(CameraSoftAP.shouldEscalateForegroundRecover(secondsSinceLastPresented: 2.0))
        #expect(CameraSoftAP.shouldEscalateForegroundRecover(secondsSinceLastPresented: nil))
    }

    @Test func frozenPresentedFrameIsStillFirstPicture() {
        #expect(!CameraSoftAP.isPresentedPictureFresh(secondsSinceLastPresented: nil))
        #expect(CameraSoftAP.isPresentedPictureFresh(secondsSinceLastPresented: 0.4))
        #expect(!CameraSoftAP.isPresentedPictureFresh(secondsSinceLastPresented: 2.0))
        #expect(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: nil, alreadySettled: false),
            "never presented")
        #expect(
            CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 3.0, alreadySettled: false),
            "one IDR then silence must not skip first-picture")
        #expect(
            !CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 0.3, alreadySettled: false),
            "picture is rolling — do not second-enable")
        #expect(
            !CameraSoftAP.shouldRunFirstPictureRecover(
                secondsSinceLastPresented: 4.0, alreadySettled: true),
            "mid-session stall is the watchdog, not a SoftAP rejoin")
        #expect(
            !CameraSoftAP.shouldMarkFirstPictureSettled(
                secondsSinceLastPresented: 0.2, secondsSinceLastEnable: 5))
        #expect(
            CameraSoftAP.shouldMarkFirstPictureSettled(
                secondsSinceLastPresented: 0.2, secondsSinceLastEnable: 8))
        #expect(
            !CameraSoftAP.shouldMarkFirstPictureSettled(
                secondsSinceLastPresented: 3.0, secondsSinceLastEnable: 10))
    }

    /// A keepalive / handshake leftover rebuild must not eat the first enable.
    @Test func firstPictureSendsEnableWhenNeverSent() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 0, secondsSinceLastEnable: 0) == .resendEnable)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 80, enableSends: 0, secondsSinceLastEnable: 10) == .resendEnable)
        #expect(CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(alreadySent: false))
        #expect(!CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(alreadySent: true))
    }

    @Test func firstPictureResendsEnableAfterRebuildWhenNeverGotVideo() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2,
            secondsSinceLastRebuild: 0.4) == .resendEnable,
            "neverGotVideo — lastRebuild is not a live flap")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 2,
            secondsSinceLastRebuild: 5) == .resendEnable)
        #expect(CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: false))
        #expect(!CameraSoftAP.shouldForceEnableAfterUDPRebuild(hadVideo: true))
        #expect(!FeedWatchdog.hadVideo(videoPackets: 0, lastVideoPacketAge: nil))
        #expect(FeedWatchdog.hadVideo(videoPackets: 12, lastVideoPacketAge: nil),
                "noteRebuild() nils the clock; videoPkts stays")
    }

    /// 272 pkts then silence: receive died. Do not sit on enable-only because
    /// the cumulative counter is non-zero.
    @Test func firstPictureFrozenBurstRebuildsUDP() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 272, enableSends: 1, secondsSinceLastEnable: 5,
            secondsSinceLastVideo: 0.4) == .resendEnable,
            "fresh packets, no picture after 5s — one 0x09/0xa8 resend")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 272, enableSends: 1, secondsSinceLastEnable: 2,
            secondsSinceLastVideo: 2) == .wait,
            "inside IDR grace — do not rebuild")
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 272, enableSends: 2, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 8) == .rebuildUDP)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 272, enableSends: 4, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 8) == .rejoin)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 272, enableSends: 4, secondsSinceLastEnable: 8) == .rejoin)
    }

    /// Second enable on a frozen receive RST'd TCP 7001. Skip it.
    @Test func frozenBurstDoesNotResendEnableOnSameSocket() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 420, enableSends: 1, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 8) == .rebuildUDP)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 420, enableSends: 2, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 8, secondsSinceLastRebuild: 5) == .rejoin)
    }

    @Test func rebuildDeadWriteFlow() {
        #expect(!CameraSoftAP.shouldRebuildFlow(.ready))
        #expect(CameraSoftAP.shouldRebuildFlow(.writeRejected))
        #expect(CameraSoftAP.shouldRebuildFlow(.notReady))
        #expect(CameraSoftAP.shouldRebuildFlow(.cancelled))
        #expect(CameraSoftAP.shouldRebuildFlow(.pathLost))
    }

    /// first-picture rebuild + keepalive rebuild canceled the live socket (89)
    /// and RST’d TCP 7001. One rebuild at a time; ignore the discarded socket.
    @Test func keepaliveDoesNotCollideWithFirstPictureRebuild() {
        #expect(!CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: true, rebuildInFlight: true, secondsSinceLastRebuild: nil))
        #expect(!CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: 0.4))
        #expect(CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: 5))
        #expect(!CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: false, rebuildInFlight: false, secondsSinceLastRebuild: 10))
        #expect(!CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: 10,
            videoFresh: true),
            "HEVC still arriving — a write reject must not tear UDP")
        #expect(!CameraSoftAP.shouldKeepaliveRebuildUDP(
            flowNeedsRebuild: true, rebuildInFlight: false, secondsSinceLastRebuild: nil,
            sawPicture: false),
            "first picture owns the socket")
        #expect(CameraSoftAP.rebuildCooldown == 5)
    }

    @Test func canceledReceiveIsNotTheLiveSocket() {
        #expect(CameraSoftAP.isCanceledReceive(
            "The operation couldn't be completed. (Network.NWError error 89 - Operation canceled)"))
        #expect(!CameraSoftAP.shouldCountReceiveError(isLiveConnection: false, canceled: true))
        #expect(!CameraSoftAP.shouldRearmAfterError(isLiveConnection: false, canceled: true))
        // Spurious 89 on a socket that is still .ready must re-arm. Treating
        // that as fatal left first-connect bound-but-deaf (20× handshake, 0 inbound).
        #expect(CameraSoftAP.shouldRearmAfterError(isLiveConnection: true, canceled: true))
        #expect(CameraSoftAP.shouldRearmAfterError(isLiveConnection: true, canceled: false))
        #expect(!CameraSoftAP.shouldApplyStaleSocketHealth(isLiveConnection: false))
    }

    @Test func handshakeSendRequiresArmedReader() {
        #expect(!CameraSoftAP.canSendHandshake(receiveArmed: false, connectionReady: true))
        #expect(!CameraSoftAP.canSendHandshake(receiveArmed: true, connectionReady: false))
        #expect(CameraSoftAP.canSendHandshake(receiveArmed: true, connectionReady: true))
    }

    @Test func firstPictureDoesNotExitPlaybackUnlessCameraIsInGallery() {
        #expect(!CameraSoftAP.shouldExitPlaybackBeforeLiveEnable(inPlayback: false))
        #expect(CameraSoftAP.shouldExitPlaybackBeforeLiveEnable(inPlayback: true))
        #expect(CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: true))
        #expect(!CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: false))
        #expect(CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(hasPicture: false))
        #expect(!CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(hasPicture: true))
    }

    @Test func firstPictureWaitsAfterUDPRebuild() {
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 220, enableSends: 3, secondsSinceLastEnable: 2,
            secondsSinceLastVideo: 6.9, secondsSinceLastRebuild: 0.5) == .wait)
        #expect(CameraSoftAP.firstPictureStep(
            videoPackets: 220, enableSends: 3, secondsSinceLastEnable: 8,
            secondsSinceLastVideo: 6.9, secondsSinceLastRebuild: 5) == .rejoin)
    }

    /// pktType 0x00, 8-byte transport header. Session/seq are not part of the
    /// ACK test — a mismatch here is how a real reply was treated as a miss.
    @Test func handshakeAckIsPktType00() {
        #expect(CameraSoftAP.isHandshakeAck([0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00]))
        #expect(DumlTransport.isHandshake([0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x00, 0x00]))
        #expect(!CameraSoftAP.isHandshakeAck([0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x02, 0x00]))
        #expect(!CameraSoftAP.isHandshakeAck([0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x04, 0x00]))
        #expect(!CameraSoftAP.isHandshakeAck([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(!CameraSoftAP.isHandshakeAck([]))
    }

    /// One bind of 20×350 ms is not a kick if 192.168.2.x is still on the path.
    @Test func handshakeTimeoutRebindsWhileSoftAPUp() {
        #expect(CameraSoftAP.handshakeTimeoutStep(pathReady: true, rebindsUsed: 0) == .rebindUDP)
        #expect(CameraSoftAP.handshakeTimeoutStep(pathReady: true, rebindsUsed: 2) == .rebindUDP)
        #expect(CameraSoftAP.handshakeTimeoutStep(pathReady: false, rebindsUsed: 0) == .fail)
        #expect(CameraSoftAP.handshakeTimeoutStep(
            pathReady: true, rebindsUsed: CameraSoftAP.handshakeRebindLimit) == .fail)
    }

    /// Late SET ACK while video is still arriving is not a dead uplink.
    /// Rebuilding UDP here tore a working receive and started the SoftAP death spiral.
    @Test func commandTimeoutsWithFreshVideoDoNotRebuild() {
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: true,
            rebuildInFlight: false, secondsSinceLastRebuild: nil),
            "SET ACK timeout while video is fresh ⇒ leave the socket alone")
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 3, downlinkFresh: true, videoFresh: true,
            rebuildInFlight: false, secondsSinceLastRebuild: CameraSoftAP.rebuildCooldown))
    }

    /// Video already silent: enough genuine SET timeouts may rebuild once.
    /// The receive watchdog still owns a quiet downlink.
    @Test func commandTimeoutsWithStaleVideoMayRebuild() {
        #expect(CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: false,
            rebuildInFlight: false, secondsSinceLastRebuild: nil))
        #expect(CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 3, downlinkFresh: true, videoFresh: false,
            rebuildInFlight: false, secondsSinceLastRebuild: CameraSoftAP.rebuildCooldown))
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 1, downlinkFresh: true, videoFresh: false,
            rebuildInFlight: false, secondsSinceLastRebuild: nil),
            "one timeout is a lost datagram, not a dead flow")
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: false, videoFresh: false,
            rebuildInFlight: false, secondsSinceLastRebuild: nil),
            "downlink dead too — the receive watchdog owns it")
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: false,
            rebuildInFlight: true, secondsSinceLastRebuild: nil),
            "one rebuild at a time")
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: false,
            rebuildInFlight: false, secondsSinceLastRebuild: CameraSoftAP.rebuildCooldown - 0.1),
            "respect the rebuild cooldown")
    }

    @Test func handshakeTimeoutDoesNotKickWhileSoftAPUp() {
        #expect(!CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: true))
        #expect(CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: false))
        #expect(!CameraSoftAP.shouldKickAfterHandshakeTimeout(pathReady: true),
                "rebind-limit fail is this open() attempt — operator stays on live")
    }

    @Test func handshakeOpenRetryGivesUpAtLimit() {
        #expect(!CameraSoftAP.shouldGiveUpOpenRetry(attempts: 0))
        #expect(!CameraSoftAP.shouldGiveUpOpenRetry(attempts: 5))
        #expect(CameraSoftAP.shouldGiveUpOpenRetry(attempts: 6))
    }

    /// Disconnect must not leave a closed driver for the next connect, and a
    /// cancelled `open()` must not publish LIVE after the operator already left.
    @Test func closedDatalinkMustNotCommitLive() {
        #expect(CameraSoftAP.shouldReuseDatalink(isClosed: false))
        #expect(!CameraSoftAP.shouldReuseDatalink(isClosed: true))
        #expect(
            CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: false, isCancelled: false))
        #expect(
            !CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: false, isClosed: false, isCancelled: false),
            "session already replaced this driver")
        #expect(
            !CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: true, isCancelled: false),
            "close() already ran — leftover handshake is not LIVE")
        #expect(
            !CameraSoftAP.shouldCommitLiveHandshake(
                driverOwned: true, isClosed: false, isCancelled: true),
            "cancelled open() must not publish LIVE after Disconnect")
    }

    @Test func savedCamerasPersistHotspot() {
        #expect(CameraSoftAP.shouldPersistHotspot(isSavedCamera: true))
        #expect(!CameraSoftAP.shouldPersistHotspot(isSavedCamera: false))
    }

    /// Poll so an early ACK does not wait out the full send interval.
    @Test func handshakePollIsFinerThanSendInterval() {
        #expect(CameraSoftAP.handshakePollMilliseconds > 0)
        #expect(
            CameraSoftAP.handshakePollMilliseconds
                < CameraSoftAP.handshakeSendIntervalMilliseconds)
    }

}
