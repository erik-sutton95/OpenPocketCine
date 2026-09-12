import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

/// A snapshot of the same primary choices used by CapturePickerPanel. It holds
/// presentation values only; camera status stays authoritative throughout a drag.
struct CaptureQuickSnapshot: Hashable {
    enum Kind: Hashable {
        case iso, isoLimit, ev, shutter, angle, whiteBalanceMode, kelvin, focus, exposure, audio
    }
    let kind: Kind
    let title: String
    let options: [String]
    let selection: String
    var marked: Set<String> = []
    var context = ""
    var enabled = true

    var index: Int {
        if let exact = options.firstIndex(of: selection) { return exact }
        switch kind {
        case .kelvin: return options.firstIndex(of: "5600K") ?? 0
        case .ev: return options.firstIndex(of: "0.0") ?? 0
        case .shutter:
            guard let current = CamCapShutter.denom(from: selection),
                let nearest = CamCapShutter.nearestDenom(
                    current, in: options.compactMap { CamCapShutter.denom(from: $0) })
            else { return 0 }
            return options.firstIndex(of: CamCapShutter.label(nearest)) ?? 0
        default: return 0
        }
    }
    var delayed: Bool { [.iso, .isoLimit, .ev, .shutter, .angle].contains(kind) }

    @MainActor static func primary(_ sheet: CaptureSheet, model: AppModel) -> Self? {
        primary(
            sheet, status: model.session.status, cameraModel: model.session.connectedCamera?.model,
            supportsFocusMode: model.session.supportsFocusMode,
            facePriorityExposureEnabled: model.facePriorityExposureEnabled,
            shutterUsesAngle: OperatorPrefs.shutterUsesAngle,
            shutterAngleDegrees: OperatorPrefs.shutterAngleDegrees)
    }

    static func primary(
        _ sheet: CaptureSheet, status: CameraStatus, cameraModel: CameraModel? = nil,
        supportsFocusMode: Bool = false, facePriorityExposureEnabled: Bool = false,
        shutterUsesAngle: Bool = false, shutterAngleDegrees: Double = 180
    ) -> Self? {
        switch sheet {
        case .iso:
            if CaptureLists.offersIsoAuto(from: status), status.isoIndex == .auto {
                let choices = CaptureLists.isoAutoLabels(
                    from: status, model: cameraModel)
                return Self(
                    kind: .isoLimit, title: "ISO", options: choices,
                    selection: CaptureLists.isoAutoLabel(
                        from: status, model: cameraModel))
            }
            return Self(
                kind: .iso, title: "ISO", options: CaptureLists.isoDrumLabels(from: status),
                selection: status.isoIndex?.label ?? (status.iso > 0 ? String(status.iso) : ""),
                marked: CaptureLists.isoMarkedLabels(from: status))
        case .shutter:
            if status.expoMode == .auto {
                return Self(
                    kind: .ev, title: "EV", options: CaptureLists.evLabels,
                    selection: status.evComp?.label ?? "",
                    enabled: !facePriorityExposureEnabled)
            }
            if shutterUsesAngle {
                let preferred = shutterAngleDegrees
                let mapped = ShutterAngle.denom(
                    degrees: preferred, fps: status.fps,
                    available: CaptureLists.shutterDenoms(from: status))
                return Self(
                    kind: .angle, title: "SHUTTER", options: ShutterAngle.labels,
                    selection: status.shutterDenom <= 0
                        ? ""
                        : mapped == status.shutterDenom
                            ? ShutterAngle.label(preferred)
                            : ShutterAngle.nearestLabel(
                                denom: status.shutterDenom, fps: status.fps),
                    context: "\(status.fps):\(CaptureLists.shutterDenoms(from: status))")
            }
            return Self(
                kind: .shutter, title: "SHUTTER", options: CaptureLists.shutterLabels(from: status),
                selection: status.shutterDenom > 0 ? CamCapShutter.label(status.shutterDenom) : "",
                context: String(status.fps))
        case .wb:
            if status.whiteBalance?.mode == .custom {
                return Self(
                    kind: .kelvin, title: "WB", options: CaptureLists.kelvinLabels,
                    selection: "\(status.whiteBalanceKelvin)K",
                    context: String(status.whiteBalanceTint ?? 0))
            }
            return Self(
                kind: .whiteBalanceMode, title: "WB",
                options: WhiteBalanceMode.allCases.map(\.label),
                selection: status.whiteBalance?.mode.label ?? "")
        case .focus:
            guard supportsFocusMode else { return nil }
            return Self(
                kind: .focus, title: "FOCUS", options: ["AF-S", "AF-C"],
                selection: status.focusMode.map { $0 == .continuous ? "AF-C" : "AF-S" } ?? "",
                context: String(describing: status.focusTrack))
        case .exposure:
            return Self(
                kind: .exposure, title: "EXPOSURE", options: ExpoMode.allCases.map(\.label),
                selection: status.expoMode?.label ?? "")
        case .audio:
            return Self(
                kind: .audio, title: "AUDIO", options: AudioChannel.allCases.map(\.label),
                selection: status.audioChannel?.label ?? "")
        case .mode, .resolution, .color: return nil
        }
    }

    /// Typed camera calls retain the production capability lists, Kelvin/tint
    /// preservation, and shutter-angle conversion; there is no protocol mapping here.
    @MainActor func apply(_ value: String, model: AppModel) {
        guard enabled, options.contains(value), value != selection, !model.session.isLocked else {
            return
        }
        let status = model.session.status
        switch kind {
        case .iso:
            if let iso = IsoIndex.allCases.first(where: { $0.label == value }),
                CaptureLists.isoIndices(from: status).contains(iso)
            {
                model.session.setISO(iso)
            }
        case .isoLimit:
            if let limit = CaptureLists.isoLimit(
                from: value, status: status, model: model.session.connectedCamera?.model)
            {
                model.session.setIsoLimit(limit)
            }
        case .ev:
            if !model.facePriorityExposureEnabled, let ev = EvComp(label: value) {
                model.session.setEv(ev)
            }
        case .shutter:
            if let denom = CamCapShutter.denom(from: value),
                CaptureLists.shutterDenoms(from: status).contains(denom)
            {
                model.session.setShutterDenom(denom)
            }
        case .angle:
            if let degrees = ShutterAngle.parse(value) {
                OperatorPrefs.shutterAngleDegrees = degrees
                model.session.setShutterDenom(
                    ShutterAngle.denom(
                        degrees: degrees, fps: status.fps,
                        available: CaptureLists.shutterDenoms(from: status)))
            }
        case .whiteBalanceMode:
            if value == WhiteBalanceMode.auto.label {
                model.session.setWhiteBalanceAuto()
            } else {
                let kelvin =
                    (2_000...10_000).contains(status.whiteBalanceKelvin)
                    ? status.whiteBalanceKelvin : 5_600
                model.session.setWhiteBalanceCustom(
                    kelvin: kelvin, tint: min(100, max(-100, status.whiteBalanceTint ?? 0)))
            }
        case .kelvin:
            if let kelvin = CaptureLists.kelvin(from: value) {
                model.session.setWhiteBalanceCustom(
                    kelvin: kelvin, tint: min(100, max(-100, status.whiteBalanceTint ?? 0)))
            }
        case .focus: model.session.setFocusMode(value == "AF-C" ? .continuous : .single)
        case .exposure:
            if let mode = ExpoMode.allCases.first(where: { $0.label == value }) {
                model.session.setExpoMode(mode)
            }
        case .audio:
            if let channel = AudioChannel.allCases.first(where: { $0.label == value }) {
                model.session.setAudioChannel(channel)
            }
        }
    }
}

struct CaptureDrumPresentation: Equatable {
    let id: UUID
    let sheet: CaptureSheet
    let snapshot: CaptureQuickSnapshot
    var position: Double
}

/// The gesture stays attached to the readout while its noninteractive overlay
/// appears. One recognizer owns tap/hold/drag, so opening a drum cannot also tap.
struct CaptureReadoutGesture: ViewModifier {
    let sheet: CaptureSheet
    let locked: Bool
    let onTap: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var interaction = MonitorReadoutInteraction()
    @State private var snapshot: CaptureQuickSnapshot?
    @State private var identity = UUID()
    @State private var holdTask: Task<Void, Never>?
    @State private var commitTask: Task<Void, Never>?
    @GestureState private var touching = false

    private var current: CaptureQuickSnapshot? { CaptureQuickSnapshot.primary(sheet, model: model) }

    func body(content: Content) -> some View {
        content.accessibilityElement(children: .ignore)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard !locked else {
                            cancel()
                            return
                        }
                        if interaction.phase == .idle { begin() }
                        let armed = interaction.move(
                            x: value.translation.width, y: value.translation.height)
                        if armed {
                            holdTask?.cancel()
                            publish()
                        } else if interaction.phase == .drumming {
                            publish()
                        }
                    }
                    .onEnded { value in
                        holdTask?.cancel()
                        _ = interaction.move(
                            x: value.translation.width, y: value.translation.height)
                        let owned = model.captureDrum?.id == identity
                        let outcome = interaction.end()
                        if owned { model.captureDrum = nil }
                        guard !locked else { return }
                        switch outcome {
                        case .tap: onTap()
                        case .commit(let translation):
                            guard owned, let snapshot, snapshot == current, snapshot.enabled,
                                let index = MonitorDrumSelection.changedIndex(
                                    origin: snapshot.index,
                                    translation: translation, count: snapshot.options.count)
                            else { return }
                            let value = snapshot.options[index]
                            guard value != snapshot.selection else {
                                return
                            }
                            commitTask?.cancel()
                            commitTask = Task { @MainActor in
                                if snapshot.delayed {
                                    try? await Task.sleep(for: .milliseconds(80))
                                }
                                guard !Task.isCancelled, !model.session.isLocked,
                                    snapshot == CaptureQuickSnapshot.primary(sheet, model: model)
                                else { return }
                                commitTask = nil
                                snapshot.apply(value, model: model)
                            }
                        case .cancelled: break
                        }
                    }
            )
            .onChange(of: touching) { _, active in
                if !active, interaction.phase != .idle {
                    cancel(cancelCommit: false)
                    interaction = .init()
                }
            }
            .onChange(of: current) { _, _ in cancel() }
            .onChange(of: locked) { _, value in if value { cancel() } }
            .onChange(of: scenePhase) { _, value in if value != .active { cancel() } }
            .onReceive(
                NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            ) { _ in
                cancel()
            }
            .onChange(of: model.session.connectedCamera?.id) { _, _ in cancel() }
            .onChange(of: model.session.phase.label) { _, _ in cancel() }
            .onChange(of: model.captureDrum?.id) { _, id in
                if interaction.phase == .drumming, id != identity { cancel() }
            }
            .onChange(of: model.captureSheet) { _, value in
                if value != nil, interaction.phase == .drumming { cancel() }
            }
            .onDisappear { cancel() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if !locked { onTap() } }
    }

    private func begin() {
        commitTask?.cancel()
        commitTask = nil
        identity = UUID()
        snapshot = current
        interaction.begin()
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(MonitorReadoutInteraction.holdMilliseconds))
            guard !Task.isCancelled, !locked, snapshot == current, interaction.hold() else {
                return
            }
            publish()
        }
    }

    private func publish() {
        guard let snapshot, snapshot == current, snapshot.enabled, !snapshot.options.isEmpty else {
            cancel()
            return
        }
        model.captureSheet = nil
        model.captureDrum = CaptureDrumPresentation(
            id: identity, sheet: sheet, snapshot: snapshot,
            position: MonitorDrumSelection.position(
                origin: snapshot.index,
                translation: interaction.translation, count: snapshot.options.count))
    }

    private func cancel(cancelCommit: Bool = true) {
        holdTask?.cancel()
        if cancelCommit {
            commitTask?.cancel()
            commitTask = nil
        }
        interaction.cancel()
        if !touching { interaction = .init() }
        if model.captureDrum?.id == identity { model.captureDrum = nil }
    }
}
