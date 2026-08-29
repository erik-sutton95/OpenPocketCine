import Foundation

/// SoftAP addressing and first-connect gates. The camera is `192.168.2.1`; the phone
/// only has a usable datalink path after DHCP gives it `192.168.2.2…254`.
///
/// `NEHotspotConfiguration.apply` returning success is not that signal — first join
/// is slow (prompt + associate + DHCP). Second connect is already on the AP, which
/// is why the feed appears after disconnect/reconnect.
public enum CameraSoftAP: Sendable {
    public static let host = "192.168.2.1"
    public static let invalidVTSessionStatus: Int32 = -12903  // kVTInvalidSessionErr

    /// Phone address on the camera AP. `.1` is the camera; `.0` / `.255` are not hosts.
    public static func isAssociatedIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
            parts[0] == "192", parts[1] == "168", parts[2] == "2",
            let host = Int(parts[3]), (2...254).contains(host)
        else { return false }
        return true
    }

    public static func isPathReady(localIPv4s: [String]) -> Bool {
        localIPv4s.contains(where: isAssociatedIPv4)
    }

    /// Pocket / Nano / Action SoftAP names. Used to drop the other body's
    /// hotspot config so two cameras at `192.168.2.1` cannot share the path.
    public static func isOsmoSoftAPSSID(_ ssid: String) -> Bool {
        let n = ssid.lowercased().replacingOccurrences(of: " ", with: "")
        return n.contains("osmo") || n.contains("dji")
            || n.contains("pocket") || n.contains("nano") || n.contains("atto")
    }
}

/// Pocket → Nano SoftAP switch. Both APs are `192.168.2.1`, so a live
/// `192.168.2.x` after leaving Pocket is not a failure — join the target.
public enum CameraSoftAPSwitch {
    public static let maxJoinAttempts = 3

    /// Do not abort because the phone still has a camera DHCP address.
    public static func shouldAbortBecausePathStillReady(_ pathReady: Bool) -> Bool {
        _ = pathReady
        return false
    }

    /// Unknown SSID after `apply` is treated as success (iOS often hides it).
    public static func isOnTarget(currentSSID: String?, target: String) -> Bool {
        guard let current = currentSSID, !current.isEmpty else { return true }
        return current == target
    }

    public static func ssidToKick(currentSSID: String?, target: String) -> String? {
        guard let current = currentSSID, !current.isEmpty, current != target else { return nil }
        return current
    }
}

extension CameraSoftAP {
    /// One IPv4 on a named interface (`getifaddrs`). Used to pin UDP to the
    /// SoftAP instead of whatever `en0` Network.framework calls Wi-Fi.
    public struct InterfaceAddress: Equatable, Sendable {
        public var name: String
        public var ipv4: String
        public init(name: String, ipv4: String) {
            self.name = name
            self.ipv4 = ipv4
        }
    }

    public static func cameraAddresses(in addrs: [InterfaceAddress]) -> [InterfaceAddress] {
        addrs.filter { isAssociatedIPv4($0.ipv4) }
    }

    public static func cameraLocalIPv4(in addrs: [InterfaceAddress]) -> String? {
        cameraAddresses(in: addrs).first?.ipv4
    }

    public static func cameraInterfaceNames(in addrs: [InterfaceAddress]) -> [String] {
        cameraAddresses(in: addrs).map(\.name)
    }

    /// First path interface that owns `192.168.2.2…254`. `en0` is not enough.
    public static func preferredInterfaceName(cameraNames: [String], available: [String]) -> String?
    {
        available.first { cameraNames.contains($0) }
    }

    /// UDP channel-flow health. `writeRejected` is iOS
    /// `nw_flow_add_write_request … cannot accept write requests`.
    public enum DatalinkFlowHealth: Equatable, Sendable {
        case ready
        case writeRejected
        case notReady
        case cancelled
        case pathLost
    }

    public static func shouldRebuildFlow(_ health: DatalinkFlowHealth) -> Bool {
        health != .ready
    }

    /// Keepalive must not tear down a socket that first-picture / watchdog just
    /// opened. Cancel of the *old* UDP is NWError 89 — that is not the new flow dying.
    public static let rebuildCooldown: TimeInterval = 5
    /// After a foreground rebuild, wait this long for an IDR before a full rejoin.
    public static let foregroundPictureGrace: TimeInterval = 2.0

    /// Control Center / a 300 ms app-switcher peek still has a live GOP — do not
    /// tear UDP. A parked app does not.
    public static func shouldRecoverAfterForeground(
        secondsSinceLastPresented: TimeInterval?,
        stall: TimeInterval = FeedWatchdog.stallThreshold
    ) -> Bool {
        guard let age = secondsSinceLastPresented else { return true }
        return age >= stall
    }

    public static func shouldEscalateForegroundRecover(
        secondsSinceLastPresented: TimeInterval?,
        grace: TimeInterval = foregroundPictureGrace
    ) -> Bool {
        guard let age = secondsSinceLastPresented else { return true }
        return age >= grace
    }

    public static func shouldKeepaliveRebuildUDP(
        flowNeedsRebuild: Bool,
        rebuildInFlight: Bool,
        secondsSinceLastRebuild: TimeInterval?,
        videoFresh: Bool = false,
        sawPicture: Bool = true
    ) -> Bool {
        // First picture owns the socket. Keepalive rebuild here canceled the
        // new UDP and RST'd TCP 7001 — black canvas, 2 s flap.
        guard sawPicture else { return false }
        // A late SET write reject while HEVC is still arriving is not a dead
        // socket. Tearing UDP here is the “toggle LUT / pinch zoom” dropout.
        guard flowNeedsRebuild, !rebuildInFlight, !videoFresh else { return false }
        if let since = secondsSinceLastRebuild, since < rebuildCooldown { return false }
        return true
    }

    /// SET ACK timeout is not a dead socket when video is still arriving.
    /// Tearing UDP for a late shutter / ISO ACK is what killed SoftAP: the
    /// rebuild dropped a working receive, then the watchdog flapped the bind.
    /// Downlink dead too → the receive watchdog owns recovery. Superseded
    /// mailbox timeouts are not counted by the caller.
    public static let commandTimeoutWindow: TimeInterval = 5
    public static let commandTimeoutRebuildCount = 2

    public static func shouldRebuildAfterCommandTimeouts(
        timeoutsInWindow: Int,
        downlinkFresh: Bool,
        videoFresh: Bool,
        rebuildInFlight: Bool,
        secondsSinceLastRebuild: TimeInterval?
    ) -> Bool {
        guard !videoFresh else { return false }
        guard timeoutsInWindow >= commandTimeoutRebuildCount, downlinkFresh, !rebuildInFlight
        else { return false }
        if let since = secondsSinceLastRebuild, since < rebuildCooldown { return false }
        return true
    }

    /// Darwin `ECANCELED` / `Network.NWError error 89 - Operation canceled`.
    public static func isCanceledReceive(_ message: String) -> Bool {
        message.contains("error 89") || message.localizedCaseInsensitiveContains("canceled")
            || message.localizedCaseInsensitiveContains("cancelled")
    }

    public static func shouldCountReceiveError(isLiveConnection: Bool, canceled: Bool) -> Bool {
        isLiveConnection && !canceled
    }

    /// A live fd that reports 89 is a path blip, not a dead reader. `canceled`
    /// only decides whether we *count* the error; the socket state decides re-arm.
    public static func shouldRearmAfterError(isLiveConnection: Bool, canceled: Bool) -> Bool {
        _ = canceled
        return isLiveConnection
    }

    /// First 0x00 must not go out on a bound socket that is not reading.
    public static func canSendHandshake(receiveArmed: Bool, connectionReady: Bool) -> Bool {
        receiveArmed && connectionReady
    }

    /// Write / state callbacks from a discarded UDP socket must not mark the
    /// live flow dead (that is what triggered the colliding keepalive rebuild).
    public static func shouldApplyStaleSocketHealth(isLiveConnection: Bool) -> Bool {
        isLiveConnection
    }

    /// First connect: no decoded picture yet. Resending `0x09/0xa8` forever
    /// stays black if UDP receive died after the first subscribe push.
    public enum FirstPictureStep: String, Equatable, Sendable {
        case wait
        case resendEnable
        /// Pocket 3 only: SET 1080 then the boot 4K (`0x02/0x18`) so the live
        /// encoder actually starts. HUD/gimbal already work; enable does not.
        case pokeRecordingFormat
        case rebuildUDP
        case rejoin
    }

    /// After `0x09/0xa8` the camera cuts a new GOP (VPS+IDR in 25–167 ms on
    /// a warm encoder; first boot can pause a few seconds). Tearing UDP in
    /// that gap is the fresh-boot black feed.
    public static let firstPictureIDRGrace: TimeInterval = 8
    /// One extra IDR request if P-frames keep arriving with no picture.
    public static let firstPictureResendWhileLive: TimeInterval = 5
    /// Floor after each first-picture `0x02/0x18` so the encoder can cut a GOP.
    public static let firstPictureFormatPokeMinSettle: TimeInterval = 0.8
    /// Pin wait for that SET. Matches `CameraSetMailbox` settle.
    public static let firstPictureFormatPokePinWait: TimeInterval = 2

    /// `enableSends` counts every `0x09/0xa8` including the initial one.
    /// A non-zero `videoPackets` is not alive — the first burst can freeze
    /// (272 then silence) while the counter stays huge.
    ///
    /// `neverGotVideo` (`videoPackets == 0`) is first picture: a prior UDP
    /// rebuild must not skip the enable. `hadVideoThenStalled` keeps the
    /// shutter-spin backoff (no 2s flap, no enable-on-frozen-socket).
    public static func firstPictureStep(
        videoPackets: Int,
        enableSends: Int,
        secondsSinceLastEnable: TimeInterval,
        secondsSinceLastVideo: TimeInterval? = nil,
        secondsSinceLastRebuild: TimeInterval? = nil,
        secondsSinceLastStatus _: TimeInterval? = nil,
        needsRecordingFormatPoke: Bool = false,
        alreadyPokedRecordingFormat: Bool = false,
        recordingFormatPokeInFlight: Bool = false,
        isRecording: Bool = false,
        hasPresentedPicture: Bool = false
    ) -> FirstPictureStep {
        // Handshake succeeded but 0x09/0xa8 never left (pathReady flickered).
        // Waiting here is the black LINK canvas until the operator reconnects.
        if enableSends < 1 { return .resendEnable }
        if hasPresentedPicture { return .wait }
        if recordingFormatPokeInFlight { return .wait }
        guard secondsSinceLastEnable >= 2 else { return .wait }
        let hadVideo = FeedWatchdog.hadVideo(
            videoPackets: videoPackets, lastVideoPacketAge: secondsSinceLastVideo)
        if shouldPokeRecordingFormat(
            needsPoke: needsRecordingFormatPoke,
            alreadyPoked: alreadyPokedRecordingFormat,
            isRecording: isRecording,
            hadVideo: hadVideo,
            enableSends: enableSends,
            secondsSinceLastEnable: secondsSinceLastEnable)
        {
            return .pokeRecordingFormat
        }
        let videoFresh =
            hadVideo
            && (secondsSinceLastVideo ?? .infinity) < FeedWatchdog.stallThreshold
        if !hadVideo {
            // Mimo first picture is 1–2 s. A 2 s second-enable / UDP rebuild
            // kills the IDR in flight and is the 30–45 s Waiting for live view.
            if secondsSinceLastEnable < firstPictureIDRGrace { return .wait }
            if enableSends >= 4 { return .rejoin }
            if enableSends >= 2 {
                if let since = secondsSinceLastRebuild, since < rebuildCooldown {
                    return .wait
                }
                return .rebuildUDP
            }
            return .resendEnable
        }
        // Saw video. A 2–3 s pause after enable is the GOP cut (fresh-boot
        // log: 370 pkts, lastVideo=2.5s, then rebuild killed the IDR).
        if secondsSinceLastEnable < firstPictureIDRGrace {
            if videoFresh, enableSends == 1,
                secondsSinceLastEnable >= firstPictureResendWhileLive
            {
                return .resendEnable
            }
            return .wait
        }
        if videoFresh {
            if enableSends == 1 { return .resendEnable }
            return .wait
        }
        // Live status with frozen HEVC is the watchdog's encoder-pause path
        // after a rolling picture. First-picture has no GOP yet — 182 P-frames
        // then silence (nals 1/35/40, format=0) sat on Waiting for live-view.
        if let since = secondsSinceLastRebuild, since < rebuildCooldown { return .wait }
        if enableSends >= 4 { return .rejoin }
        // One UDP rebuild already tried and the burst is still frozen → full rejoin
        // (the sequence that works after the operator hits Disconnect).
        if secondsSinceLastRebuild != nil { return .rejoin }
        // Packets arrived then stopped. A second 0x09/0xa8 on that socket
        // RST'd TCP 7001. Rebuild UDP only; enable on the new socket.
        return .rebuildUDP
    }

    /// Pocket 3 boots 4K 25/30 with chrome live and no HEVC until the operator
    /// SETs 1080 then 4K. Same-tab FORMAT is a no-op, so the boot 4K never
    /// leaves the wire. One poke, before UDP rebuild. Not Pocket 4.
    public static func shouldPokeRecordingFormat(
        needsPoke: Bool,
        alreadyPoked: Bool,
        isRecording: Bool,
        hadVideo: Bool,
        enableSends: Int,
        secondsSinceLastEnable: TimeInterval
    ) -> Bool {
        guard needsPoke, !alreadyPoked, !isRecording, enableSends >= 1 else { return false }
        guard secondsSinceLastEnable >= 2 else { return false }
        if !hadVideo { return true }
        return secondsSinceLastEnable >= firstPictureResendWhileLive
    }

    /// After a UDP rebuild, first picture must put `0x09/0xa8` on the new
    /// socket. After live video, the enable already rode with the rebuild.
    public static func shouldForceEnableAfterUDPRebuild(hadVideo: Bool) -> Bool {
        !hadVideo
    }

    /// Mimo 2026-08-28 live-start: HEVC at join+17 ms, `0x09/0xa8` at +3 s.
    /// Ingest pktType `0x02` once the UDP handshake is acked. Decoder still
    /// latches VPS/SPS only, so leftover TRAIL P-frames do not present.
    /// Enable is PLI for a dead encoder, not a gate to look.
    public static func shouldIngestLiveVideo(ingestArmed: Bool) -> Bool {
        ingestArmed
    }

    /// Skip GOP-reset IDR hold when a picture is already on the layer.
    /// Mimo's enable at +3 s must not black a feed that started at +17 ms.
    public static func shouldBeginIDRHoldOnEnable(hasPresentedPicture: Bool) -> Bool {
        !hasPresentedPicture
    }

    /// `0x09/0xa8` once path is up. Do not wait for the display layer —
    /// first-boot attach is ~2 s and mid-GOP P-frames pile up; enable
    /// before subscribe is ignored. Display can attach after format exists.
    public static func shouldSendLiveViewEnable(
        pathReady: Bool,
        displayAttached: Bool,
        alreadySent: Bool
    ) -> Bool {
        _ = displayAttached
        return pathReady && !alreadySent
    }

    /// After UDP handshake the path is proven. Do not ask `getifaddrs` again —
    /// a flicker there skipped enable and first-picture recovery sat on LINK.
    public static func shouldSendLiveViewEnableAfterHandshake(alreadySent: Bool) -> Bool {
        !alreadySent
    }

    /// Pocket live-entry: `0x02/0x68` `08` immediately before `0x09/0xa8`
    /// (`mimo-disconnect-20260822-105228`). That pair starts a clean GOP
    /// (137 B VPS) instead of leftover TRAIL P-frames. Nano has no captured
    /// 0x68 pair — skip it when the Nano gate is in use.
    public static func shouldSendLiveViewPrepare(usesNanoLiveViewGate: Bool) -> Bool {
        !usesNanoLiveViewGate
    }

    /// `0x02/0x0c` is gallery enter/exit, not live-start. Unconditional exit
    /// before every `0x09/0xa8` left Pocket on WAITING FOR LIVE VIEW (`videoPkts=0`).
    public static func shouldExitPlaybackBeforeLiveEnable(inPlayback: Bool) -> Bool {
        inPlayback
    }

    /// `onPause` during bounded session recovery must not latch first-picture
    /// skip forever after `holdsMonitor` clears.
    public static func shouldClearForegroundRecoverWithoutRebuild(holdsMonitor: Bool) -> Bool {
        holdsMonitor
    }

    /// Stray gallery on a black feed: send exit, then still `0x09/0xa8` this tick.
    public static func shouldContinueFirstPictureAfterStrayPlayback(hasPicture: Bool) -> Bool {
        !hasPicture
    }

    /// A presented sample inside the stall window. One IDR then silence is not this.
    public static func isPresentedPictureFresh(
        secondsSinceLastPresented: TimeInterval?,
        stall: TimeInterval = FeedWatchdog.stallThreshold
    ) -> Bool {
        guard let age = secondsSinceLastPresented else { return false }
        return age >= 0 && age < stall
    }

    /// First-picture recovery must keep running after a frozen first GOP.
    /// `lastPresentedAt != nil` used to skip it and leave LINK until Disconnect.
    public static func shouldRunFirstPictureRecover(
        secondsSinceLastPresented: TimeInterval?,
        alreadySettled: Bool
    ) -> Bool {
        if alreadySettled { return false }
        return !isPresentedPictureFresh(secondsSinceLastPresented: secondsSinceLastPresented)
    }

    /// Rolling picture is first picture. Do not wait the 8 s IDR grace after
    /// enable — Mimo is on-screen in tens of ms once UDP is up.
    public static func shouldMarkFirstPictureSettled(
        secondsSinceLastPresented: TimeInterval?,
        secondsSinceLastEnable: TimeInterval
    ) -> Bool {
        _ = secondsSinceLastEnable
        return isPresentedPictureFresh(secondsSinceLastPresented: secondsSinceLastPresented)
    }

    /// Rebuild the VT session. Do not treat this as an enable/IDR trigger.
    public static func shouldRebuildVTSession(status: Int32) -> Bool {
        status == invalidVTSessionStatus
    }

    /// One UDP bind of handshake sends. Camera SoftAP can be up (DHCP) before
    /// 9004 is listening — settle, then send, then rebind without tearing Wi-Fi.
    public static let handshakeSendsPerBind = 20
    public static let handshakeSendIntervalMilliseconds = 350
    /// Driver must poll this often and break when the handshake ACK flag is set.
    /// handshakeSendIntervalMilliseconds remains the max wait per send.
    public static let handshakePollMilliseconds = 20
    public static let handshakeSettleMilliseconds = 400
    public static let handshakeRebindLimit = 3
    public static let handshakeRetryPauseMilliseconds = 500
    /// openDatalinkKeepingLive must stop after this many failed open attempts.
    public static let handshakeOpenRetryLimit = 6
    public static func shouldGiveUpOpenRetry(attempts: Int) -> Bool {
        attempts >= handshakeOpenRetryLimit
    }
    /// Saved cameras keep NEHotspotConfiguration across background.
    public static func shouldPersistHotspot(isSavedCamera: Bool) -> Bool {
        isSavedCamera
    }

    public enum HandshakeTimeoutStep: String, Equatable, Sendable {
        case rebindUDP
        case fail
    }

    public static func isHandshakeAck(_ datagram: [UInt8]) -> Bool {
        DumlTransport.isHandshake(datagram)
    }

    /// After a bind's send loop misses. SoftAP still `192.168.2.x` → new UDP
    /// socket, same TCP poke. SoftAP gone → this open() attempt fails.
    public static func handshakeTimeoutStep(
        pathReady: Bool,
        rebindsUsed: Int,
        rebindLimit: Int = handshakeRebindLimit
    ) -> HandshakeTimeoutStep {
        if !pathReady { return .fail }
        if rebindsUsed < rebindLimit { return .rebindUDP }
        return .fail
    }

    /// A handshake miss is not a pairing-screen kick while the camera AP is up.
    public static func shouldKickAfterHandshakeTimeout(pathReady: Bool) -> Bool {
        !pathReady
    }

    /// `close()` is terminal. Handshake again on that driver inherited a
    /// half-dead UDP session; reconnect then sat on Waiting for live view
    /// until process death.
    public static func shouldReuseDatalink(isClosed: Bool) -> Bool {
        !isClosed
    }

    /// In-app disconnect is not process death. A cancelled `open()` can still
    /// finish handshake and publish LIVE unless the session still owns this
    /// driver, it is not closed, and the task is not cancelled.
    public static func shouldCommitLiveHandshake(
        driverOwned: Bool, isClosed: Bool, isCancelled: Bool
    ) -> Bool {
        driverOwned && !isClosed && !isCancelled
    }
}
