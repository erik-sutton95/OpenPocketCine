import MonitorPresentation
import OpenPocketViewCore
import SwiftUI

/// Maps the existing Osmo session into shared page values. No discovery timers,
/// connection policy, or invented camera telemetry belong in this adapter.
@MainActor
enum OsmoCameraPageAdapter {
    static func paired(_ model: AppModel) -> [CameraListItem] {
        let latest = model.savedCameras.max { $0.lastConnectedAt < $1.lastConnectedAt }?.id
        let busy = model.isBusy || model.session.isReconnecting
        return model.savedCameras.map { saved in
            let nearby = model.session.found.contains { $0.id == saved.id }
            let connecting = busy && model.session.connectionTargetID == saved.id
            let progress =
                model.session.isReconnecting && model.isScanning
                ? "Looking for camera…"
                : model.session.setupProgress ?? model.session.phase.label
            let preferred = saved.preferredSetup
            let network = saved.ssid(for: preferred)
            let body = CameraModel.resolve(modelId: saved.modelId, name: saved.advertisedName)
            let failure = connectFailure(model, saved: saved, busy: connecting)
            return CameraListItem(
                id: saved.id.uuidString, name: saved.displayName,
                subtitle: saved.modelName + (network.map { " · \($0)" } ?? ""),
                badge: connecting
                    ? "CONNECTING"
                    : failure != nil
                        ? "NOT CONNECTED"
                        : saved.id == latest ? "LAST USED" : nearby ? "PAIRED" : "OFFLINE",
                status: connecting
                    ? progress
                    : nearby ? "Nearby · ready to connect" : "Not found — power it on to reconnect",
                actionTitle: nearby ? "Connect" : "Reconnect", isPrimary: saved.id == latest,
                isBusy: connecting, isAvailable: nearby,
                setups: saved.setups.map {
                    CameraSetupChip(
                        id: $0.rawValue, title: chipTitle($0, saved: saved),
                        isActive: $0
                            == (connecting || failure != nil
                                ? model.session.connectionSetup : preferred),
                        canForget: $0.movesCamera)
                },
                // Every Osmo body answers the captured station sequence (#406).
                canAddSetup: saved.setups.count < CameraConnectionSetup.allCases.count
                    && MulticamSupport.appears(body),
                steps: connecting ? connectSteps(model, saved: saved) : [],
                failure: failure)
        }
    }

    static func chipTitle(_ setup: CameraConnectionSetup, saved: SavedCamera) -> String {
        guard setup == .wifi, let ssid = saved.wifiSSID else { return setup.title }
        return "Wi-Fi · \(ssid)"
    }

    /// Four steps on the connecting card: Bluetooth, network, find/handshake, picture.
    static func connectSteps(_ model: AppModel, saved: SavedCamera) -> [CameraConnectStep] {
        let session = model.session
        let setup = session.connectionSetup
        let network =
            setup == .cameraWiFi ? "camera Wi-Fi" : saved.ssid(for: setup) ?? setup.title
        let progress = session.setupProgress
        let finding = progress?.hasPrefix("Finding") == true
        let stage: Int
        switch session.phase {
        case .idle, .scanning, .failed, .connectingGatt, .pairing, .awaitingApproval: stage = 0
        case .readingWifiCreds, .joiningWifi: stage = finding ? 2 : 1
        case .openingDatalink: stage = 2
        case .live: stage = 4
        }
        func state(_ index: Int) -> CameraConnectStep.State {
            index < stage ? .done : index == stage ? .active : .waiting
        }
        let bluetooth: String
        if session.phase == .awaitingApproval {
            bluetooth = "Approve on the camera"
        } else if session.phase == .scanning {
            bluetooth = "Looking for the camera"
        } else {
            bluetooth = ""
        }
        // One caption at a time under the progress bar: what is happening, then its detail.
        return [
            .init("Connecting over Bluetooth", detail: bluetooth, state: state(0)),
            .init(
                setup == .cameraWiFi ? "Joining camera Wi-Fi" : "Moving the camera to \(network)",
                detail: stage == 1 ? progress ?? session.phase.label : "",
                state: state(1)),
            .init(
                setup == .cameraWiFi ? "Opening the video link" : "Finding the camera",
                detail: "", state: state(2)),
            .init("Starting the picture", detail: "", state: state(3)),
        ]
    }

    /// A failed connect stays on its card with the ways out, until the next connect.
    static func connectFailure(_ model: AppModel, saved: SavedCamera, busy: Bool)
        -> CameraConnectFailure?
    {
        guard !busy, case .failed(let reason) = model.session.phase,
            model.session.connectionTargetID == saved.id
        else { return nil }
        let setup = model.session.connectionSetup
        var message = StartupConnectionCopy.friendly(reason)
        if setup == .phoneHotspot, SharedWiFiPath.address(hotspot: true) == nil {
            // The usual cause: the hotspot was off, so the camera had nothing to join.
            message =
                "The camera could not find this iPhone’s hotspot. Turn on Personal Hotspot and Allow Others to Join, then try again."
        }
        guard setup.movesCamera else {
            return .init(
                title: "Couldn’t connect over Camera Wi-Fi", message: message,
                actions: [.init(id: "retry", title: "Try again", primary: true)])
        }
        return .init(
            title: "Couldn’t connect over \(saved.ssid(for: setup) ?? setup.title)",
            message: message,
            actions: [
                .init(id: "edit", title: "Edit setup"),
                .init(id: "retry", title: "Try again", primary: true),
            ],
            link: .init(id: "cameraWiFi", title: "Connect over Camera Wi-Fi instead"))
    }

    static func nearby(_ model: AppModel) -> [CameraListItem] {
        let savedIDs = Set(model.savedCameras.map(\.id))
        return model.session.found.filter { !savedIDs.contains($0.id) }.map {
            device($0, model: model)
        }
    }

    static func device(_ camera: FoundCamera, model: AppModel, selected: UUID? = nil)
        -> CameraListItem
    {
        CameraListItem(
            id: camera.id.uuidString,
            name: FoundCameraIdentity.listTitle(
                advertisedName: camera.name, modelName: camera.model.name),
            subtitle: FoundCameraIdentity.listSubtitle(
                advertisedName: camera.name, modelName: camera.model.name)
                + (camera.model.verified ? "" : " · unverified"),
            badge: "NEW", status: "Needs approval on the camera", actionTitle: "Pair",
            isPrimary: selected == camera.id, isBusy: model.isBusy)
    }

    static func pairing(_ model: AppModel, selected: UUID?) -> CameraPairingPresentation {
        let phase = model.session.phase
        let step = phase.pocketWizardStep - 1
        let target = model.session.connectedCamera
        let picked = model.session.found.first { $0.id == selected }
        let failure: String?
        if case .failed(let reason) = phase {
            failure = StartupConnectionCopy.friendly(reason)
        } else {
            failure = nil
        }
        let scanning = step == 0
        let titles = [
            "Find your camera", "Approve on the camera", "Join camera Wi-Fi", "Open video link",
        ]
        let bodies = [
            "Turn the camera on and keep the phone nearby. Pocket and Nano both appear — choose the one you want.",
            "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
            "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
            "Exposure, LUTs and scopes go live as soon as the video link is up.",
        ]
        var instructions: [CameraPairingInstruction] = []
        if step == 1 {
            instructions = [
                .init(
                    title: "On the camera", icon: .camera,
                    lines: ["Look for an Approve / pairing prompt", "Tap it on the camera screen"]),
                .init(
                    title: "On iPhone", icon: .phone,
                    lines: [
                        "Wait here — we keep the Bluetooth link alive", "Don't force-quit the app",
                    ]),
            ]
        } else if step == 2 {
            instructions = [
                .init(
                    title: "On the camera", icon: .camera,
                    lines: [
                        "Leave the camera on — it brings up its own Wi-Fi",
                        "On 5.8 GHz that can take about a minute; we keep trying",
                    ]),
                .init(
                    title: "On iPhone", icon: .phone,
                    lines: [
                        "Tap Join when iOS asks to join the camera network",
                        LocalVPNFilter.joinWifiPhoneStep,
                    ]),
            ]
        } else if step == 3 && LocalVPNProbe.isActive() {
            instructions = [
                .init(
                    title: "Check the connection", icon: .phone,
                    lines: [LocalVPNFilter.wizardBanner])
            ]
        }
        let checks: [CameraPairingCheck] =
            step >= 2
            ? [
                .init(
                    title: "Bluetooth link", subtitle: target?.name ?? "Camera connected",
                    state: .complete, stateLabel: "OK"),
                .init(
                    title: "Camera Wi-Fi",
                    subtitle: model.session.joinedSSID ?? "Waiting for the camera network",
                    state: step > 2 ? .complete : .active, stateLabel: step > 2 ? "OK" : "JOINING"),
                .init(
                    title: "Live picture",
                    subtitle: step > 2 ? "Opening the video link…" : "Starts after Wi-Fi joins",
                    state: step > 2 ? .active : .waiting, stateLabel: "WAITING"),
            ] : []
        let hint: String
        if scanning {
            hint =
                picked.map { "Selected \($0.name)" } ?? "Choose the camera that matches your screen"
        } else if step == 1 {
            hint = "Nothing to type — approve it on the camera"
        } else if step == 2 {
            hint = "iOS asks to join the camera network"
        } else {
            hint = "Monitoring opens when the picture is ready"
        }
        return CameraPairingPresentation(
            steps: zip(titles, ["Bluetooth scan", "Camera prompt", "Camera network", "Video link"])
                .map { .init($0.0, $0.1) },
            currentStep: step, title: titles[step], body: bodies[step],
            target: (scanning ? picked?.name : target?.name) ?? "Nothing selected yet", hint: hint,
            progress: failure == nil && (model.isBusy || model.isScanning) ? phase.label : nil,
            error: failure,
            devices: scanning
                ? model.session.found.map { device($0, model: model, selected: selected) } : [],
            instructions: instructions, checks: checks,
            emptyTitle: scanning && model.session.found.isEmpty
                ? model.isScanning ? "Looking for cameras" : "No cameras yet" : nil,
            primaryAction: failure != nil ? "Try again" : scanning ? "Continue" : nil,
            primaryActionEnabled: failure != nil || (picked != nil && !model.isBusy),
            backAction: model.isBusy ? "Cancel" : !model.savedCameras.isEmpty ? "Back" : nil)
    }

    static func safeArea(
        _ proposed: EdgeInsets, window: EdgeInsets, portrait: Bool,
        orientation: MonitorDeviceOrientation
    ) -> EdgeInsets {
        let raw = LiveMonitorLayout.resolvedSafeArea(
            proposed, scene: window)
        guard !portrait else { return raw }
        return OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: raw, isPortrait: false,
            mirrored: LiveMonitorLayout.shouldMirror(
                leading: raw.leading, trailing: raw.trailing, orientation: orientation))
    }
}
