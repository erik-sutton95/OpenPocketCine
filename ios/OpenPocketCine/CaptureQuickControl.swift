import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// A snapshot of the same primary choices used by CapturePickerPanel. It holds
/// presentation values only; camera status stays authoritative throughout a drag.
struct CaptureQuickSnapshot: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
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

    var display: MonitorReadoutSnapshot {
        MonitorReadoutSnapshot(
            title: title, options: options, selection: selection, marked: marked,
            fallbackIndex: index)
    }

    func changedValue(translation: Double, current: Self?) -> String? {
        guard self == current, enabled else { return nil }
        return display.changedValue(at: display.position(translation: translation))
    }

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
                kind: .focus, title: "FOCUS", options: FocusOption.allCases.map(\.chip),
                selection: CaptureLists.focusOption(from: status)?.chip ?? "",
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
        case .focus:
            if let option = FocusOption.allCases.first(where: { $0.chip == value }) {
                model.session.setFocusOption(option)
            }
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

    /// The origin is only a visual anchor when native state is unknown. A
    /// stationary hold (or a drag back to that origin) must keep it unselected.
    var selection: String { snapshot.display.selection(at: position) }
}

/// Osmo adapter for the shared readout gesture. It derives native options and
/// owns delayed SET admission; pointer timing, ownership and lifecycle live in MonitorUI.
struct CaptureReadoutGesture: ViewModifier {
    let sheet: CaptureSheet
    let locked: Bool
    @Binding var ownership: MonitorReadoutOwnership
    let onTap: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var commitTask: Task<Void, Never>?

    private struct Source: Hashable, Sendable {
        let cameraID: UUID?
        let phase: String
        let controlID: String
        let snapshot: CaptureQuickSnapshot?
    }

    private var source: Source {
        Source(
            cameraID: model.session.connectedCamera?.id, phase: model.session.phase.label,
            controlID: sheet.rawValue, snapshot: CaptureQuickSnapshot.primary(sheet, model: model))
    }

    private var canInteract: Bool {
        !locked && !model.session.isLocked && scenePhase == .active
            && model.liveOperatorPanel == nil && model.captureSheet == nil
    }

    func body(content: Content) -> some View {
        let current = source
        return content.modifier(
            MonitorReadoutGesture(
                snapshot: current.snapshot.flatMap { $0.enabled ? $0.display : nil },
                sourceIdentity: current, isEnabled: canInteract, ownership: $ownership,
                presentationOwner: { model.captureDrum?.id }, onEvent: handleEvent))
    }

    private func handleEvent(_ event: MonitorReadoutEvent<Source>) {
        switch event {
        case .open(let admittedSource):
            if canInteract, admittedSource == source,
                ownership.owner == nil, model.captureDrum == nil
            {
                onTap()
            }
        case .preview(let preview):
            guard canInteract, ownership.owns(preview.id), preview.sourceIdentity == source,
                let snapshot = preview.sourceIdentity.snapshot, snapshot.enabled,
                model.captureDrum == nil || model.captureDrum?.id == preview.id
            else { return }
            model.captureDrum = CaptureDrumPresentation(
                id: preview.id, sheet: sheet, snapshot: snapshot, position: preview.position)
        case .commit(let release, let revision):
            guard model.captureDrum?.id == release.id else { return }
            model.captureDrum = nil
            scheduleCommit(release, revision: revision)
        case .cancel(let identity):
            commitTask?.cancel()
            commitTask = nil
            if model.captureDrum?.id == identity { model.captureDrum = nil }
        }
    }

    private func scheduleCommit(_ release: MonitorReadoutValue<Source>, revision: UInt64) {
        let admittedSource = release.sourceIdentity
        let admittedWindow = windowGeometry
        guard canInteract, admittedSource == source,
            let snapshot = admittedSource.snapshot, snapshot.enabled,
            let value = release.changedValue
        else { return }
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            if snapshot.delayed { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled, canInteract, admittedSource == source,
                admittedWindow == windowGeometry, ownership.permitsDeferredCommit(revision),
                model.captureDrum == nil
            else { return }
            commitTask = nil
            snapshot.apply(value, model: model)
        }
    }
}
