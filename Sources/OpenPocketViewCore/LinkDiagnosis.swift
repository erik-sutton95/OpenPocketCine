import Foundation

/// Classified live-link failure. Cheapest matching case wins; present-path
/// faults must not tear UDP.
public enum LinkFailure: Equatable, Sendable {
    case none
    case bleLost
    case softAPLost
    case udpFlowDead
    case encoderPaused
    case decoderWedged
    case presentStalled
}

/// Repair for a classified failure. Present-path faults map to `.none`.
public enum LinkRepair: Equatable, Sendable {
    case none
    case resendEnable
    case rebindUDP
    case rehandshake
    case rejoinSoftAP
    case fullReconnect
}

/// Diagnose a live link, then map the failure to one repair.
public enum LinkDiagnoser {
    /// Path ready, no BLE notify, and both UDP and status stale.
    private static let bleLostAge: TimeInterval = 8

    public static func diagnose(
        pathReady: Bool,
        bleNotifyAge: TimeInterval?,
        videoAge: TimeInterval?,
        statusAge: TimeInterval?,
        flowHealthy: Bool,
        decoderFailed: Bool,
        udpReceiveAlive: Bool,
        hadVideo: Bool,
        secondsSinceLastEnable: TimeInterval?,
        secondsSinceFocusTrackSet: TimeInterval?,
        presentAge: TimeInterval? = nil
    ) -> LinkFailure {
        if !pathReady { return .softAPLost }
        if decoderFailed { return .decoderWedged }
        if udpReceiveAlive,
            let presentAge,
            presentAge > FeedWatchdog.stallThreshold,
            !decoderFailed
        {
            return .presentStalled
        }
        if FeedWatchdog.shouldHoldForGOPReset(
            secondsSinceLastEnable: secondsSinceLastEnable,
            lastVideoPacketAge: videoAge
        ) {
            return .none
        }
        if FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: secondsSinceFocusTrackSet) {
            return .none
        }
        if hadVideo,
            (statusAge ?? .infinity) < FeedWatchdog.stallThreshold,
            !udpReceiveAlive
        {
            return .encoderPaused
        }
        if pathReady,
            bleNotifyAge == nil || bleNotifyAge! > bleLostAge,
            !udpReceiveAlive,
            (statusAge ?? .infinity) >= FeedWatchdog.stallThreshold
        {
            return .bleLost
        }
        if !flowHealthy || !udpReceiveAlive {
            return .udpFlowDead
        }
        return .none
    }

    public static func repair(for failure: LinkFailure) -> LinkRepair {
        switch failure {
        case .none: .none
        case .encoderPaused: .resendEnable
        case .udpFlowDead: .rebindUDP
        case .softAPLost: .rejoinSoftAP
        case .bleLost: .fullReconnect
        case .decoderWedged: .none
        case .presentStalled: .none
        }
    }

    /// Same classifier, from the watchdog snapshot the shells already build.
    public static func diagnose(_ snap: FeedWatchdog.Snapshot) -> LinkFailure {
        diagnose(
            pathReady: snap.pathReady,
            bleNotifyAge: snap.lastBleNotifyAge,
            videoAge: snap.lastVideoPacketAge,
            statusAge: snap.lastStatusAge,
            flowHealthy: snap.flowHealthy,
            decoderFailed: snap.decoderFailed,
            udpReceiveAlive: FeedWatchdog.udpReceiveAlive(snap),
            hadVideo: snap.hadVideo,
            secondsSinceLastEnable: snap.secondsSinceLastEnable,
            secondsSinceFocusTrackSet: snap.secondsSinceFocusTrackSet,
            presentAge: snap.lastDecodedFrameAge
        )
    }

    /// One Console line: what `LinkDiagnoser` would repair vs what `FeedWatchdog.tick`
    /// actually returned. Does not change the repair. `disagree=1` means they split.
    public static func observeLine(snap: FeedWatchdog.Snapshot, watchdog: FeedWatchdog.Action)
        -> String
    {
        let failure = diagnose(snap)
        let repair = repair(for: failure)
        let disagree = agrees(watchdog: watchdog, repair: repair) ? 0 : 1
        func age(_ value: TimeInterval?) -> String {
            guard let value else { return "none" }
            return String(format: "%.1f", value)
        }
        return
            "feed: observe diagnose=\(failure) repair=\(repair) watchdog=\(watchdog) disagree=\(disagree) lastFrame=\(age(snap.lastDecodedFrameAge))s lastVideo=\(age(snap.lastVideoPacketAge))s lastStatus=\(age(snap.lastStatusAge))s lastBle=\(age(snap.lastBleNotifyAge))s"
    }

    /// Same intent, not the same enum. Shells map `rebuildVTSession` to UDP rebuild.
    public static func agrees(watchdog: FeedWatchdog.Action, repair: LinkRepair) -> Bool {
        switch (watchdog, repair) {
        case (.none, .none): true
        case (.resendLiveViewEnable, .resendEnable): true
        case (.reopenDatalink, .rebindUDP), (.rebuildVTSession, .rebindUDP): true
        case (.fullSessionRejoin, .fullReconnect), (.fullSessionRejoin, .rejoinSoftAP): true
        default: false
        }
    }
}
