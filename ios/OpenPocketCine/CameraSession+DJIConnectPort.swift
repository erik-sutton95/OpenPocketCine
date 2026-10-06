import Foundation
import OpenCineCore
import OpenCineMedia
import OpenPocketViewCore
import OpenCineDJIApple

/// The shared document's saved camera (SHELL-02), for app files that do not import OpenCineCore
/// (its `ConnectionPhase` and `CameraSession` share names with this app's).

/// A saved camera's DJI setups, as this app's session and wizard read them (SHELL-02 document:
/// camera Wi-Fi is the `ap` route, Wi-Fi and Hotspot the setups that move the camera).
extension SavedCamera {
    var modelName: String { model }
    var modelId: Int? { extras["modelId"].flatMap { Int($0) } }
    var lastSSID: String? { network(of: .cameraAccessPoint) }
    var wifiSSID: String? { network(of: .infrastructureNetwork) }
    var hotspotSSID: String? { network(of: .phoneHotspot) }

    func ssid(for setup: CameraConnectionSetup) -> String? {
        switch setup {
        case .cameraWiFi: lastSSID
        case .wifi: wifiSSID
        case .phoneHotspot: hotspotSSID
        }
    }

    /// A setup that moves the camera was the last one started: its access point may still be down.
    var mayBeInStationRole: Bool {
        let preferred = routes.first { $0.id == preferredRoute }?.kind
        return preferred == .infrastructureNetwork || preferred == .phoneHotspot
            || ["wifi", "phoneHotspot"].contains(extras["lastSetup"] ?? "")
    }

    private func network(of kind: RouteKind) -> String? {
        routes.first { $0.kind == kind }?.network
    }
}

/// The shared connection flow's way into this session (SHELL-02): `DJIIntegration` runs pairing
/// and saved-camera connects through it, so the session keeps its phases, recovery, keepalive
/// and feed exactly as for its own reconnects.
extension CameraSession: DJIConnectPort {
    static func sighting(_ camera: DjiAppleSighting) -> DJISighting {
        DJISighting(
            id: camera.id.uuidString,
            name: FoundCameraIdentity.listTitle(advertisedName: camera.name, modelName: camera.model.name),
            model: camera.model, modelId: camera.modelId)
    }

    func connect(cameraID: String, setup: DJISetup, restoreAccessPoint: Bool) async throws -> DJIConnection {
        guard let id = UUID(uuidString: cameraID) else {
            throw Self.failure(.notFound, "camera.unknown", "This camera is not a Bluetooth camera this phone knows.")
        }
        let next: CameraConnectionSetup
        let nextNetwork: String?
        switch setup {
        case .cameraWiFi:
            next = .cameraWiFi
            nextNetwork = nil
        case .wifi(let network, let password):
            next = .wifi
            nextNetwork = network
            if let password { MultiviewNetworkStore.save(ssid: network, password: password, hotspot: false) }
        case .phoneHotspot(let network, let password):
            next = .phoneHotspot
            nextNetwork = network
            if let password {
                MultiviewNetworkStore.save(ssid: network, password: password, hotspot: true)
            } else if DjiAppleSharedWiFiPath.address(hotspot: true) == nil, let confirmHotspot {
                // iOS reports Personal Hotspot only once a device has joined it, so a saved
                // hotspot connect without that sign asks first. Without it the camera spends
                // its join retries on a network that is not there.
                guard await confirmHotspot(network) else { throw CancellationError() }
            }
        }
        try Task.checkCancellation()
        // Switching setups is a new connection, never a live-session no-op.
        if connectedCamera?.id == id, connectionSetup != next { disconnect() }
        connectionSetup = next
        stationNetwork = nextNetwork
        lastConnectError = nil
        reconnect(to: id)
        while true {
            switch phase {
            case .live:
                guard let camera = connectedCamera else { throw CancellationError() }
                var services = CameraServices()
                if let producer = await connectedMediaService() {
                    services.register(producer as any CameraMediaService,
                        as: (any CameraMediaService).self)
                }
                try Task.checkCancellation()
                guard connectedCamera?.id == camera.id, case .live = phase else {
                    throw CancellationError()
                }
                return DJIConnection(
                    session: control, joinedNetwork: next == .cameraWiFi ? joinedSSID : nil,
                    camera: DJISighting(id: cameraID, name: camera.name, model: camera.model, modelId: camera.modelId),
                    services: services)
            case .failed(let why):
                throw typedFailure(why)
            case .idle:
                throw CancellationError()
            default:
                await nextPhase()
                try Task.checkCancellation()
            }
        }
    }

    func forget(cameraID: String) {
        if let camera = savedCameras().first(where: { $0.id == cameraID }) { forgetWifiCreds(for: camera) }
    }

    /// Reports the attempt's stage and wakes the port's waiter on every phase or progress change.
    func connectPhaseChanged() {
        let waiters = phaseWaiters
        phaseWaiters = []
        waiters.forEach { $0.resume() }
        let stage: DJIConnectionStage? =
            switch phase {
            case .scanning: .scanning
            case .connectingGatt: .connectingBluetooth
            case .pairing: .pairing
            case .awaitingApproval: .awaitingApproval
            case .readingWifiCreds: .readingWiFi
            case .joiningWifi: setupProgress?.hasPrefix("Finding") == true ? .findingCamera : .joiningWiFi
            case .openingDatalink: .openingDatalink
            case .idle, .live, .failed: nil
            }
        if let stage { onStage?(stage, setupProgress ?? (stage == .joiningWiFi ? phase.label : nil)) }
    }

    private func nextPhase() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { phaseWaiters.append($0) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.connectPhaseChanged() }
        }
    }

    /// The failed connect as the cards show it: this app's copy (`StartupConnectionCopy`), with
    /// Open Settings where only Settings fixes it, typed by the error the pipeline threw.
    func typedFailure(_ why: String) -> ConnectionFailure {
        var message = StartupConnectionCopy.friendly(why)
        if connectionSetup == .phoneHotspot, DjiAppleSharedWiFiPath.address(hotspot: true) == nil {
            // The usual cause: the hotspot was off, so the camera had nothing to join.
            message =
                "The camera could not find this iPhone’s hotspot. Turn on Personal Hotspot and Allow Others to Join, then try again."
        }
        let (reason, code) = Self.reason(lastConnectError, why)
        var failure = Self.failure(reason, code, message)
        if StartupConnectionCopy.opensSettings(why) { failure.actions = [.openSettings, .retry] }
        return failure
    }

    static func failure(_ reason: ConnectionFailure.Reason, _ code: String, _ message: String) -> ConnectionFailure {
        ConnectionFailure(
            reason: reason, title: "Couldn’t connect over Camera Wi-Fi", message: message, actions: [.retry],
            code: "\(DJICameraSessionAdapter.integration.rawValue).\(code)")
    }

    /// Typed at the errors the pipeline throws (`Fail`, `BleError`, `JoinError`,
    /// `DatalinkError`, `StationJoin.Failure`); a scan that never started reports in `why`.
    static func reason(_ error: Error?, _ why: String) -> (ConnectionFailure.Reason, String) {
        if let fail = error as? Fail {
            switch fail {
            case .pairingTimeout: return (.notApproved, "approval.timeout")
            case .pairingDeferred, .mimoSession, .credsRefused: return (.heldElsewhere, "camera.held")
            case .wrongCamera: return (.wrongCamera, "camera.wrong")
            case .setupNotSaved: return (.credentialsRejected, "station.password-missing")
            case .hostWiFi, .staleSoftAP: return (.joinFailed, "wifi.join-failed")
            case .stationCameraMissing: return (.notFound, "station.camera-missing")
            case .timeout, .commandTimeout, .nanoWake: return (.timedOut, "timeout")
            case .disconnected, .disconnectedDuring: return (.linkLost, "link.lost")
            case .creds, .credsEmpty: return (.other, "creds.unread")
            }
        }
        if let ble = error as? DjiAppleBluetoothLink.BleError {
            return ble == .timeout ? (.timedOut, "bluetooth.timeout") : (.linkLost, "bluetooth.lost")
        }
        if let join = error as? DjiAppleWiFiJoiner.JoinError {
            return DjiAppleWiFiJoiner.JoinError.rejectsCredentials(join)
                ? (.credentialsRejected, "wifi.rejected") : (.joinFailed, "wifi.join-failed")
        }
        if let datalink = error as? DjiAppleDatalink.DatalinkError {
            if case .localNetworkDenied = datalink { return (.permission(.localNetwork), "local-network.denied") }
            return (.timedOut, "datalink.silent")
        }
        if let station = error as? StationJoin.Failure {
            return station == .hotspotUnavailable
                ? (.joinFailed, "station.hotspot-unavailable") : (.credentialsRejected, "station.join-rejected")
        }
        switch why {
        case StartupConnectionCopy.bluetoothDenied: return (.permission(.bluetooth), "bluetooth.denied")
        case StartupConnectionCopy.bluetoothOff: return (.radioOff(.bluetooth), "bluetooth.off")
        default: return (.other, "connect.failed")
        }
    }
}
