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
}
