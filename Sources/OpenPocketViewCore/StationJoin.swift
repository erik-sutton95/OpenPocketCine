import Foundation

/// Captured BLE sequence that moves an Osmo from its own access point onto another network:
/// Video mode, station role, then `07/47` join with bounded retry. Shared by Multiview and
/// the per-camera phone-hotspot setup (#406). Transport-free: the shell supplies the BLE
/// exchange and the LAN probe, so this stays portable.
public struct StationJoin {
    public enum Outcome: Equatable, Sendable {
        /// The camera accepted the join; the shell still finds and verifies it on the LAN.
        case joined
        /// `verifyOnNetwork` already found and verified the camera.
        case verified
    }

    public enum Failure: LocalizedError, Equatable {
        case rejected, unsupportedRole, roleRefused, roleStarting, joinSilent, joinRejected
        case hotspotUnavailable

        public var errorDescription: String? {
            switch self {
            case .rejected:
                "Camera could not complete this step. Check the Wi-Fi details and try again."
            case .unsupportedRole:
                "This camera did not report a supported Wi-Fi mode. Shared Wi-Fi setup is experimental for this model."
            case .roleRefused: "The camera did not accept shared Wi-Fi mode."
            case .roleStarting: "Camera Wi-Fi is still starting. Retry with the camera nearby."
            case .joinSilent: "Camera Wi-Fi did not respond. Retry setup with the camera nearby."
            case .joinRejected:
                "The camera could not join the Wi-Fi. Check the password and that the network is in range. WPA3-only networks refuse some cameras: use WPA2/WPA3 with PMF optional."
            case .hotspotUnavailable:
                "Enable Personal Hotspot and Allow Others to Join, then retry. The hotspot network is not available yet."
            }
        }
    }

    public typealias Exchange = (Duml.Frame, TimeInterval) async throws -> Duml.Frame

    public var model: CameraModel
    public var ssid: String
    public var password: String
    public var hotspot: Bool
    /// Multiview's bounded path for models without a captured preview profile.
    public var experimental = false
    /// Camera already in station role: try the LAN before re-sending the join. Multiview
    /// always re-joins; a saved hotspot reconnect probes first.
    public var probeExistingStation = false

    public init(model: CameraModel, ssid: String, password: String, hotspot: Bool) {
        self.model = model
        self.ssid = ssid
        self.password = password
        self.hotspot = hotspot
    }

    /// `identity` is the camera's `07/07` reply read before the role change. It is the
    /// only proof that a LAN address is this body, so callers verify with it. Runs on the
    /// caller's actor, so shell closures keep their MainActor state.
    public func run(
        isolation: isolated (any Actor)? = #isolation,
        identity: [UInt8],
        exchange: Exchange,
        send: (Duml.Frame) -> Void,
        next: () -> UInt16,
        status: (String) -> Void,
        hotspotReady: () -> Bool,
        verifyOnNetwork: () async throws -> Bool,
        log: (String) -> Void = { _ in },
        sleep: (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) async throws -> Outcome {
        guard identity.count > 2, identity[0] == 0 else { throw Failure.rejected }
        _ = try MulticamCommands.join(ssid: ssid, password: password, seq: 0)
        if MulticamSupport.hasPreview(model) && !experimental {
            status("Selecting Video mode")
            send(MulticamCommands.videoMode(seq: next()))
            try await sleep(2)
        }
        let role = try await exchange(MulticamCommands.wifiWorkMode(seq: next()), 12).payload
        let decision = MulticamStationPolicy.decision(
            reply: role,
            allowMissingQuery: experimental
                || MulticamSupport.acceptsMissingRoleQuery(model, reply: role))
        let missingRoleQuery = decision == .setWithoutReadback
        log("station experimental=\(experimental) decision=\(decision)")
        if decision == .alreadyStation, probeExistingStation, !hotspot || hotspotReady() {
            status("Finding camera on Wi-Fi")
            if try await verifyOnNetwork() { return .verified }
        }
        if decision != .alreadyStation {
            guard decision != .reject else { throw Failure.unsupportedRole }
            let switched = try await exchange(
                MulticamCommands.stationMode(true, seq: next()), 12
            ).payload
            guard MulticamStationPolicy.acceptsSetter(switched, missingQuery: missingRoleQuery)
            else { throw Failure.roleRefused }
            // The missing-getter shape has no readback; its join result and LAN identity
            // check remain required.
            if !missingRoleQuery {
                var stationReady = false
                for _ in 0..<6 {
                    let reported = try await exchange(
                        MulticamCommands.wifiWorkMode(seq: next()), 12
                    ).payload
                    if reported == [0, 1] {
                        stationReady = true
                        break
                    }
                    guard reported == [0, 0] else { throw Failure.rejected }
                    try await sleep(2)
                }
                guard stationReady else { throw Failure.roleStarting }
            }
        }
        status("Waiting for camera Wi-Fi")
        try await sleep(TimeInterval(MulticamJoinPolicy.prepareSettleSeconds))
        for attempt in 1...MulticamJoinPolicy.maximumAttempts {
            status("Joining Wi-Fi · attempt \(attempt) of \(MulticamJoinPolicy.maximumAttempts)")
            let joined: Duml.Frame
            do {
                joined = try await exchange(
                    MulticamCommands.join(ssid: ssid, password: password, seq: next()),
                    MulticamJoinPolicy.replyTimeoutSeconds)
            } catch {
                if error is CancellationError { throw error }
                log("join reply timeout; checking verified LAN identity")
                // A lost BLE reply is not proof that association failed.
                if !hotspot || hotspotReady() {
                    do {
                        if try await verifyOnNetwork() { return .verified }
                    } catch { if error is CancellationError { throw error } }
                }
                if attempt < MulticamJoinPolicy.maximumAttempts {
                    try await sleep(TimeInterval(MulticamJoinPolicy.retryDelaySeconds))
                    continue
                }
                throw Failure.joinSilent
            }
            // Only the fixed-size result is logged, never the credential request.
            let result = joined.payload.prefix(4).map { String(format: "%02x", $0) }
            log("Wi-Fi join attempt=\(attempt) result=\(result.joined(separator: " "))")
            switch MulticamJoinPolicy.decision(reply: joined.payload, attempt: attempt) {
            case .connected: break
            case .retry:
                status("Retrying Wi-Fi connection")
                try await sleep(TimeInterval(MulticamJoinPolicy.retryDelaySeconds))
                continue
            case .rejected: throw Failure.joinRejected
            }
            break
        }
        if hotspot {
            // The phone's hotspot bridge may appear only after the camera associates.
            status("Waiting for Personal Hotspot")
            var waited: TimeInterval = 0
            while !hotspotReady() && waited < 15 {
                try await sleep(0.25)
                waited += 0.25
            }
            guard hotspotReady() else { throw Failure.hotspotUnavailable }
        }
        return .joined
    }
}
