import Foundation

/// Live-feed stall detector and reconnect policy.
///
/// UDP receive age is the stall signal — not “VT/layer did not present.”
/// Packets or AUs still arriving means the socket is alive; a black or
/// frozen canvas is a present-path bug and must not resend `0x09/0xa8`,
/// rebuild VT, or rejoin SoftAP.
///
/// Half-dead socket: UDP rx silent, BLE/tx still up. Rebuild UDP at once.
/// Do not climb enable → VT → reopen → fullRejoin. Do not tear VT because
/// the socket paused. SoftAP bind stays.
///
/// Encoder pause: DUML status still landing, HEVC silent, past GOP/AF-C
/// grace. Two `0x09/0xa8`, then one UDP rebuild. Keepalive must not flap
/// while status is young. `escalateAfter` between actions — do not 1 Hz loop.
///
/// Mid-session recover must not paint black: keep the last frame until a
/// new decoded picture is in hand, and do not enqueue empty samples.
public struct FeedWatchdog: Equatable, Sendable {
    public static let stallThreshold: TimeInterval = 2
    public static let escalateAfter: TimeInterval = 5
    public static let cooldownDuration: TimeInterval = 15
    /// After one UDP rebuild, do not flap the bind on the 2s stall cadence.
    /// Thirty rebuilds in a minute is what dropped SoftAP.
    public static let rebuildBackoff: TimeInterval = 60
    /// Analog / head-track lift. Shorter than stall so a held stick cannot
    /// keep throwing into an encoder-pause recover.
    public static let analogLiftStale: TimeInterval = 1.6

    public enum Stage: String, Equatable, Sendable {
        case idle
        case resendEnable
        case rebuildVT
        case reopenDatalink
        case fullRejoin
        case cooldown
    }

    public enum Action: Equatable, Sendable {
        case none
        case resendLiveViewEnable
        case rebuildVTSession
        case reopenDatalink
        case fullSessionRejoin
    }

    public struct Snapshot: Equatable, Sendable {
        public var now: TimeInterval
        public var lastDecodedFrameAge: TimeInterval?
        public var lastVideoPacketAge: TimeInterval?
        public var lastAccessUnitAge: TimeInterval?
        public var lastStatusAge: TimeInterval?
        public var flowHealthy: Bool
        public var pathReady: Bool
        public var hasFormat: Bool
        public var decoderFailed: Bool
        public var live: Bool
        public var sawPicture: Bool
        public var tcpPokeReady: Bool
        /// Last displayed picture was removed (or the layer failed) before a
        /// replacement sample was enqueued — the operator sees black.
        public var displayedImageRemoved: Bool
        /// BLE notify age. Fresh while UDP is silent ⇒ half-dead socket.
        public var lastBleNotifyAge: TimeInterval?
        /// Driver clock since the last UDP rebind. Used to stop a 2s flap.
        public var secondsSinceLastRebuild: TimeInterval?
        /// A real video packet was seen this session (`videoPkts > 0`).
        /// `noteRebuild()` clears receive clocks — do not infer this from a
        /// nil `lastVideoPacketAge`. First picture is `false`.
        public var hadVideo: Bool
        /// Age of the last `0x09/0xa8`. The camera cuts a new GOP after enable;
        /// 2 s of UDP silence in that window is the IDR gap, not a dead socket.
        public var secondsSinceLastEnable: TimeInterval?
        /// Age of the last AF-C `0x8E` pid `0x003B` SET. Switching intelligence
        /// can pause HEVC; that is not a dead socket.
        public var secondsSinceFocusTrackSet: TimeInterval?
        /// Age of the last zoom `0xB8` SET. Lens slew can pause HEVC the same
        /// way AF-C does; GOP-cutting mid-zoom blacks the well.
        public var secondsSinceZoomSet: TimeInterval?
        /// Age of the last non-rest gimbal stick throw. Motion can pause HEVC.
        public var secondsSinceGimbalThrow: TimeInterval?

        public init(
            now: TimeInterval,
            lastDecodedFrameAge: TimeInterval?,
            lastVideoPacketAge: TimeInterval?,
            lastAccessUnitAge: TimeInterval? = nil,
            lastStatusAge: TimeInterval?,
            flowHealthy: Bool,
            pathReady: Bool,
            hasFormat: Bool,
            decoderFailed: Bool,
            live: Bool,
            sawPicture: Bool,
            tcpPokeReady: Bool = false,
            displayedImageRemoved: Bool = false,
            lastBleNotifyAge: TimeInterval? = nil,
            secondsSinceLastRebuild: TimeInterval? = nil,
            hadVideo: Bool = true,
            secondsSinceLastEnable: TimeInterval? = nil,
            secondsSinceFocusTrackSet: TimeInterval? = nil,
            secondsSinceZoomSet: TimeInterval? = nil,
            secondsSinceGimbalThrow: TimeInterval? = nil
        ) {
            self.now = now
            self.lastDecodedFrameAge = lastDecodedFrameAge
            self.lastVideoPacketAge = lastVideoPacketAge
            self.lastAccessUnitAge = lastAccessUnitAge
            self.lastStatusAge = lastStatusAge
            self.flowHealthy = flowHealthy
            self.pathReady = pathReady
            self.hasFormat = hasFormat
            self.decoderFailed = decoderFailed
            self.live = live
            self.sawPicture = sawPicture
            self.tcpPokeReady = tcpPokeReady
            self.displayedImageRemoved = displayedImageRemoved
            self.lastBleNotifyAge = lastBleNotifyAge
            self.secondsSinceLastRebuild = secondsSinceLastRebuild
            self.hadVideo = hadVideo
            self.secondsSinceLastEnable = secondsSinceLastEnable
            self.secondsSinceFocusTrackSet = secondsSinceFocusTrackSet
            self.secondsSinceZoomSet = secondsSinceZoomSet
            self.secondsSinceGimbalThrow = secondsSinceGimbalThrow
        }
    }

    public var stage: Stage = .idle
    public private(set) var lastActionAt: TimeInterval = 0
    /// Encoder-pause `0x09/0xa8`s this stall. Two then one UDP rebuild.
    private var encoderPauseEnables = 0

    public init() {}

    /// Active recovery (not idle, not the post-cycle cooldown).
    public var isRecovering: Bool {
        switch stage {
        case .idle, .cooldown: false
        default: true
        }
    }

    /// Video packets or assembled AUs still arriving — the UDP socket is alive.
    /// A stale `lastDecodedFrameAge` is a present hitch, not a dead link.
    public static func udpReceiveAlive(_ snap: Snapshot) -> Bool {
        if let video = snap.lastVideoPacketAge, video < stallThreshold { return true }
        if let au = snap.lastAccessUnitAge, au < stallThreshold { return true }
        return false
    }

    /// Status frames ride the same UDP 9004 socket as HEVC. Fresh status with
    /// silent video is an encoder pause, not a dead bind — resend enable after
    /// GOP / AF-C grace instead of tearing UDP.
    public static func controlReceiveAlive(_ snap: Snapshot) -> Bool {
        guard let status = snap.lastStatusAge else { return false }
        return status < stallThreshold
    }

    /// Either HEVC or DUML status still landing — do not tear the socket.
    public static func socketAlive(_ snap: Snapshot) -> Bool {
        udpReceiveAlive(snap) || controlReceiveAlive(snap)
    }

    /// BLE still up and SoftAP still on the path — do not flap UDP / fullRejoin.
    public static func shouldHoldBind(pathReady: Bool, lastBleNotifyAge: TimeInterval?) -> Bool {
        pathReady && (lastBleNotifyAge ?? .infinity) < stallThreshold
    }

    /// Sticky session signal: a real `0x02` video packet arrived.
    /// `noteRebuild()` nils the receive clocks; `videoPackets` stays.
    public static func hadVideo(videoPackets: Int, lastVideoPacketAge: TimeInterval?) -> Bool {
        videoPackets > 0 || lastVideoPacketAge != nil
    }

    /// HEVC landed after this `0x09/0xa8` — the IDR gap, not a still-paused encoder.
    public static func enableRestartedVideo(
        secondsSinceLastEnable: TimeInterval?,
        lastVideoPacketAge: TimeInterval?
    ) -> Bool {
        guard let since = secondsSinceLastEnable, let video = lastVideoPacketAge else {
            return false
        }
        return video + 0.05 < since
    }

    /// `0x09/0xa8` cuts the encoder GOP. Warm cameras answer in 25–167 ms;
    /// a fresh-boot / mid-session enable can stay silent for a few seconds.
    /// Tearing UDP in that gap is the LUT-toggle / first-picture black feed.
    ///
    /// If HEVC has been silent *longer* than this enable, the enable did not
    /// restart the encoder — do not sit in the 8s IDR window.
    public static func shouldHoldForGOPReset(
        secondsSinceLastEnable: TimeInterval?,
        lastVideoPacketAge: TimeInterval? = nil
    ) -> Bool {
        guard let since = secondsSinceLastEnable, since < CameraSoftAP.firstPictureIDRGrace else {
            return false
        }
        if let video = lastVideoPacketAge, video > since + stallThreshold {
            return false
        }
        return true
    }

    /// Only the first time a hardware decoder that cannot join mid-GOP starts.
    /// LUT / PEAK / WAVE off is a local present change — not an IDR request.
    public static func shouldRequestKeyFrameForDecoderStart(
        startingHardwareDecoder: Bool,
        hasFormat: Bool,
        hasPicture: Bool
    ) -> Bool {
        startingHardwareDecoder && hasFormat && hasPicture
    }

    /// Persist LUT/WAVE starts VT after the identity layer already consumed the
    /// live-start IDR. Skipping a PLI because that enable was `< 1 s` ago leaves
    /// a fresh VT with no IDR — WAITING FOR LIVE VIEW while UDP stays live.
    /// Rapid A/B assist toggles still collapse (`liveViewEnableSends > 1`).
    public static func shouldSendEnableForAssistVTStart(
        secondsSinceLastEnable: TimeInterval,
        hasPresentedPicture: Bool,
        liveViewEnableSends: Int
    ) -> Bool {
        if secondsSinceLastEnable >= 1 { return true }
        return hasPresentedPicture && liveViewEnableSends <= 1
    }

    /// After one UDP rebuild, do not rebuild again on the 2s stall cadence.
    /// First picture (`hadVideo == false`) is not a live flap — do not hold.
    public static func shouldHoldRebuildAfterRecentUDP(
        secondsSinceLastRebuild: TimeInterval?,
        pathReady: Bool,
        lastBleNotifyAge: TimeInterval?,
        hadVideo: Bool = true
    ) -> Bool {
        guard hadVideo else { return false }
        guard shouldHoldBind(pathReady: pathReady, lastBleNotifyAge: lastBleNotifyAge) else {
            return false
        }
        guard let since = secondsSinceLastRebuild else { return false }
        return since < rebuildBackoff
    }

    /// HEVC silent, a repair in flight, or clocks wiped after a live GOP.
    /// `lastVideoPacketAge == nil` after `hadVideo` is a rebuild (`lastVideo=none`
    /// on physical #148) — treating that as fresh re-grabs the stick into a GOP cut.
    public static func shouldTreatLiveVideoAsStale(
        lastVideoPacketAge: TimeInterval?,
        hadVideo: Bool,
        recovering: Bool = false
    ) -> Bool {
        if recovering { return true }
        guard let age = lastVideoPacketAge else { return hadVideo }
        return age >= analogLiftStale
    }

    /// One feed-repair Task at a time. Cancelling a live rebuild left the
    /// cancelled body force-enabling after `await` while a new rebuild started.
    public static func shouldStartFeedRecovery(rebuildInFlight: Bool) -> Bool {
        !rebuildInFlight
    }

    /// First picture (`hadVideo == false`) may resend `0x09/0xa8` after stall.
    /// Mid-session extra enable while `awaitingIDR` GOP-cuts a live or
    /// encoder-paused picture — `tick` already owns that ladder.
    public static func shouldRepeatRecoverEnable(
        secondsSinceLastEnable: TimeInterval,
        secondsSinceLastRebuild: TimeInterval?,
        pathReady: Bool,
        lastBleNotifyAge: TimeInterval?,
        hadVideo: Bool = true,
        holdEnableCount: Int = 1,
        lastVideoPacketAge: TimeInterval? = nil
    ) -> Bool {
        _ = secondsSinceLastRebuild
        _ = pathReady
        _ = lastBleNotifyAge
        _ = holdEnableCount
        _ = lastVideoPacketAge
        if hadVideo { return false }
        return secondsSinceLastEnable >= stallThreshold
    }

    public mutating func tick(_ snap: Snapshot) -> Action {
        if !snap.live {
            resetIdle()
            return .none
        }
        guard snap.pathReady else { return .none }

        if Self.udpReceiveAlive(snap) {
            resetIdle()
            return .none
        }

        if Self.shouldHoldForGOPReset(
            secondsSinceLastEnable: snap.secondsSinceLastEnable,
            lastVideoPacketAge: snap.lastVideoPacketAge
        ) {
            return .none
        }

        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: snap.secondsSinceFocusTrackSet) {
            return .none
        }

        if CamFov.shouldHoldWatchdog(secondsSinceSet: snap.secondsSinceZoomSet) {
            return .none
        }

        if GimbalStick.shouldHoldWatchdog(
            secondsSinceThrow: snap.secondsSinceGimbalThrow,
            lastVideoPacketAge: snap.lastVideoPacketAge)
        {
            return .none
        }

        // First connect: no video packet yet. Resend enable — do not treat
        // “already rebuilt / no clocks” as a post-video flap.
        if !snap.hadVideo {
            if stage != .idle, snap.now - lastActionAt < Self.escalateAfter {
                return .none
            }
            switch stage {
            case .idle:
                return fire(.resendLiveViewEnable, at: snap.now)
            case .resendEnable:
                return fire(.reopenDatalink, at: snap.now)
            case .rebuildVT, .reopenDatalink, .fullRejoin:
                stage = .cooldown
                lastActionAt = snap.now
                return .none
            case .cooldown:
                return .none
            }
        }

        // Encoder pause: status still on 9004, HEVC silent. Two enables,
        // then one UDP rebuild (22:16 brought the picture back). Do not
        // reset the enable cap or ignore rebuildBackoff when BLE is stale
        // — that flapped UDP while status was young (#148). The shell
        // already rides one enable with the rebuild.
        if snap.hadVideo, Self.controlReceiveAlive(snap), !Self.udpReceiveAlive(snap) {
            if stage != .idle, snap.now - lastActionAt < Self.escalateAfter {
                return .none
            }
            if encoderPauseEnables < 2 {
                encoderPauseEnables += 1
                return fire(.resendLiveViewEnable, at: snap.now)
            }
            if let since = snap.secondsSinceLastRebuild, since < Self.rebuildBackoff {
                return .none
            }
            return fire(.reopenDatalink, at: snap.now)
        }

        if Self.shouldHoldRebuildAfterRecentUDP(
            secondsSinceLastRebuild: snap.secondsSinceLastRebuild,
            pathReady: snap.pathReady,
            lastBleNotifyAge: snap.lastBleNotifyAge,
            hadVideo: snap.hadVideo
        ) {
            if stage == .idle {
                stage = .cooldown
                lastActionAt = snap.now
            }
            return .none
        }

        if stage == .cooldown {
            if Self.shouldHoldBind(
                pathReady: snap.pathReady, lastBleNotifyAge: snap.lastBleNotifyAge)
            {
                return .none
            }
            if snap.now - lastActionAt >= Self.cooldownDuration {
                return fire(.reopenDatalink, at: snap.now)
            }
            return .none
        }

        if stage != .idle, snap.now - lastActionAt < Self.escalateAfter {
            return .none
        }

        switch stage {
        case .idle, .resendEnable, .rebuildVT:
            // UDP silent. BLE/tx may still be up — rebuild the socket now.
            // Do not resend enable, do not tear VT, do not fullRejoin SoftAP.
            return fire(.reopenDatalink, at: snap.now)
        case .reopenDatalink, .fullRejoin:
            stage = .cooldown
            lastActionAt = snap.now
            return .none
        case .cooldown:
            return .none
        }
    }

    /// `feed: stall` while the last picture is still up; `feed: black` if recover
    /// (or a failed layer) already wiped it.
    public func stallLogLine(_ snap: Snapshot) -> String {
        func age(_ value: TimeInterval?) -> String {
            guard let value else { return "none" }
            return String(format: "%.1f", value)
        }
        let flow = snap.flowHealthy ? "ready" : "dead"
        let prefix = snap.displayedImageRemoved ? "feed: black" : "feed: stall"
        return
            "\(prefix) lastFrame=\(age(snap.lastDecodedFrameAge))s lastVideo=\(age(snap.lastVideoPacketAge))s lastAU=\(age(snap.lastAccessUnitAge))s lastStatus=\(age(snap.lastStatusAge))s lastBle=\(age(snap.lastBleNotifyAge))s flow=\(flow) tcp=\(snap.tcpPokeReady ? 1 : 0) path=\(snap.pathReady ? 1 : 0) format=\(snap.hasFormat ? 1 : 0) stage=\(stage.rawValue) recoverBlack=\(snap.displayedImageRemoved ? 1 : 0)"
    }

    /// Wipe the display layer only when the next decoded picture is in hand.
    /// Passing `false` is the mid-session recover rule: keep the last frame.
    public static func shouldFlushDisplayedImage(nextFrameReady: Bool) -> Bool {
        nextFrameReady
    }

    /// Re-enable only after SoftAP `192.168.2.x` and VT/display are ready.
    /// Same first-connect gate; mid-session recover used to skip it.
    public static func shouldSendRecoverEnable(pathReady: Bool, decoderReady: Bool) -> Bool {
        pathReady && decoderReady
    }

    /// Do not present an empty sample, and do not enqueue P-frames after a
    /// GOP-reset enable until the IDR lands.
    public static func shouldPresentSample(
        hasPicture: Bool,
        awaitingIDR: Bool,
        isIDR: Bool
    ) -> Bool {
        guard hasPicture else { return false }
        if awaitingIDR { return isIDR }
        return true
    }

    private mutating func fire(_ action: Action, at now: TimeInterval) -> Action {
        switch action {
        case .resendLiveViewEnable: stage = .resendEnable
        case .rebuildVTSession: stage = .rebuildVT
        case .reopenDatalink: stage = .reopenDatalink
        case .fullSessionRejoin: stage = .fullRejoin
        case .none: break
        }
        lastActionAt = now
        return action
    }

    private mutating func resetIdle() {
        stage = .idle
        lastActionAt = 0
        encoderPauseEnables = 0
    }
}
