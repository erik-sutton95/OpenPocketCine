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
                ? "Looking for camera…" : model.session.phase.label
            return CameraListItem(
                id: saved.id.uuidString, name: saved.displayName,
                subtitle: saved.modelName + (saved.lastSSID.map { " · \($0)" } ?? ""),
                badge: connecting
                    ? "CONNECTING"
                    : saved.id == latest ? "LAST USED" : nearby ? "PAIRED" : "OFFLINE",
                status: connecting
                    ? progress
                    : nearby ? "Nearby · ready to connect" : "Not found — power it on to reconnect",
                actionTitle: nearby ? "Connect" : "Reconnect", isPrimary: saved.id == latest,
                isBusy: connecting, isAvailable: nearby)
        }
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
