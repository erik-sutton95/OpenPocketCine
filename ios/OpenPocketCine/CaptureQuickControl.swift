import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// A snapshot of the same primary choices used by CapturePickerPanel. It holds
/// presentation values only; camera status stays authoritative throughout a drag.
struct CaptureQuickSnapshot: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case iso, isoLimit, ev, shutter, angle, whiteBalanceMode, kelvin, focus, exposure, audio
        case format, color, shootingMode
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

    /// Options and capability for an in-flight gesture. Live HUD selection is
    /// excluded so an optimistic Auto/Manual write cannot cancel a drag or settle.
    var sourceIdentity: SourceIdentity {
        SourceIdentity(
            kind: kind, title: title, options: options, marked: marked, context: context,
            enabled: enabled)
    }

    struct SourceIdentity: Hashable, Sendable {
        var kind: Kind
        var title: String
        var options: [String]
        var marked: Set<String>
        var context: String
        var enabled: Bool
    }

    var display: MonitorReadoutSnapshot {
        MonitorReadoutSnapshot(
            title: title, options: options, selection: selection, marked: marked,
            fallbackIndex: index)
    }

    var chipValue: String { selection.isEmpty ? "—" : selection }

    /// Angle HUD: preferred only when it maps to live 1/N, else the nearest live label.
    static func shutterReadout(
        status: CameraStatus, shutterUsesAngle: Bool, shutterAngleDegrees: Double,
        facePriorityExposureEnabled: Bool = false
    ) -> String {
        primary(
            .shutter, status: status, facePriorityExposureEnabled: facePriorityExposureEnabled,
            shutterUsesAngle: shutterUsesAngle, shutterAngleDegrees: shutterAngleDegrees
        )?.chipValue ?? "—"
    }

    static func persistPreferredAngle(
        afterDenom denom: Int, fps: Int, usesAngle: Bool, isPhoto: Bool, expoIsAuto: Bool
    ) -> Double? {
        guard
            GamepadShutterSync.shouldPersistPreferredAngle(
                usesAngle: usesAngle, isPhoto: isPhoto, expoIsAuto: expoIsAuto)
        else { return nil }
        return GamepadShutterSync.preferredAngle(afterDenom: denom, fps: fps)
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
            if shutterUsesAngle, !status.isPhoto {
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
            guard !status.isPhoto else { return nil }
            return Self(
                kind: .audio, title: "AUDIO", options: AudioChannel.allCases.map(\.label),
                selection: status.audioChannel?.label ?? "")
        case .resolution:
            if status.isPhoto {
                return Self(
                    kind: .format, title: "FORMAT", options: [], selection: "Photo",
                    enabled: false)
            }
            return formatSnapshot(status: status, cameraModel: cameraModel)
        case .color:
            guard !status.isPhoto else { return nil }
            return colorSnapshot(status: status, cameraModel: cameraModel)
        case .mode: return shootingModeSnapshot(status: status, cameraModel: cameraModel)
        }
    }

    private static func formatSnapshot(status: CameraStatus, cameraModel: CameraModel?) -> Self? {
        let formats = CamCapVideoFormat.pickerFormats(
            available: status.availableVideoFormats, model: cameraModel,
            shootingMode: status.shootingMode)
        let current =
            status.videoFormat
            ?? VideoFormat(
                resolution: status.videoResolution ?? .p1080,
                frameRate: VideoFrameRate.fromFps(status.fps) ?? .fps24)
        let rates = CamCapVideoFormat.frameRates(
            available: formats, resolution: current.resolution, current: current.frameRate)
        let options = rates.map(\.drumLabel)
        guard !options.isEmpty else { return nil }
        let live = current.frameRate.drumLabel
        return Self(
            kind: .format, title: "FORMAT", options: options,
            selection: options.contains(live) ? live : "",
            context:
                "\(current.resolution.rawValue):\(status.shootingMode):\(options.joined(separator: ","))",
            enabled: !formats.isEmpty
        )
    }

    private static func colorSnapshot(status: CameraStatus, cameraModel: CameraModel?) -> Self? {
        let family = cameraModel?.family ?? .other
        let modes =
            cameraModel.map {
                CamCapColorMode.wheel(available: status.availableColorModes, model: $0)
            }
            ?? CamCapColorMode.wheel(available: status.availableColorModes, family: family)
        let options = modes.map { $0.label(for: family) }
        guard !options.isEmpty else { return nil }
        let live = status.colorMode?.label(for: family) ?? ""
        return Self(
            kind: .color, title: "COLOR", options: options,
            selection: options.contains(live) ? live : "",
            context: "\(family):\(options.joined(separator: ",")):\(status.isRecording)")
    }

    private static func shootingModeSnapshot(status: CameraStatus, cameraModel: CameraModel?)
        -> Self
    {
        let options = CaptureLists.operatorShootingModes(from: status, model: cameraModel).map {
            $0.label(for: cameraModel)
        }
        let live = ShootingMode.fromStatus(status.shootingMode)?.label(for: cameraModel) ?? ""
        return Self(
            kind: .shootingMode, title: "MODE", options: options,
            selection: options.contains(live) ? live : "",
            context: "\(status.shootingMode):\(status.isRecording)",
            enabled: !status.isRecording)
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
        case .format:
            let formats = CamCapVideoFormat.pickerFormats(
                available: status.availableVideoFormats,
                model: model.session.connectedCamera?.model,
                shootingMode: status.shootingMode)
            let current =
                status.videoFormat
                ?? VideoFormat(
                    resolution: status.videoResolution ?? .p1080,
                    frameRate: VideoFrameRate.fromFps(status.fps) ?? .fps24)
            let rates = CamCapVideoFormat.frameRates(
                available: formats, resolution: current.resolution, current: current.frameRate)
            if let rate = VideoFrameRate(drumLabel: value), rates.contains(rate) {
                model.session.setVideoFormat(resolution: current.resolution, frameRate: rate)
            }
        case .color:
            if let mode = ColorMode(label: value) {
                model.session.setColorMode(mode)
            }
        case .shootingMode:
            guard !status.isRecording else { return }
            if let mode = CaptureLists.operatorShootingModes(
                from: status, model: model.session.connectedCamera?.model
            ).first(where: {
                $0.label(for: model.session.connectedCamera?.model) == value
            }), mode != .livePhoto {
                model.session.setShootingMode(mode)
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

    private var canBegin: Bool {
        CaptureReadoutAdmission.canBegin(
            locked: locked, sessionLocked: model.session.isLocked,
            sceneActive: scenePhase == .active, operatorPanel: model.liveOperatorPanel != nil)
    }

    private var canCommit: Bool {
        CaptureReadoutAdmission.canCommit(canBegin: canBegin, captureSheet: model.captureSheet)
    }

    func body(content: Content) -> some View {
        let current = source
        return content.modifier(
            MonitorReadoutGesture(
                snapshot: current.snapshot.flatMap { $0.enabled ? $0.display : nil },
                sourceIdentity: current, isEnabled: canBegin, ownership: $ownership,
                presentationOwner: { model.captureDrum?.id }, onEvent: handleEvent))
    }

    private func handleEvent(_ event: MonitorReadoutEvent<Source>) {
        switch event {
        case .open(let admittedSource):
            if canBegin, admittedSource == source,
                ownership.owner == nil, model.captureDrum == nil
            {
                onTap()
            }
        case .preview(let preview):
            guard canBegin, ownership.owns(preview.id), preview.sourceIdentity == source,
                let snapshot = preview.sourceIdentity.snapshot, snapshot.enabled,
                model.captureDrum == nil || model.captureDrum?.id == preview.id
            else { return }
            model.captureSheet = nil
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
        guard canCommit, admittedSource == source,
            let snapshot = admittedSource.snapshot, snapshot.enabled,
            let value = release.changedValue
        else { return }
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            if snapshot.delayed { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled, canCommit, admittedSource == source,
                admittedWindow == windowGeometry, ownership.permitsDeferredCommit(revision),
                model.captureDrum == nil
            else { return }
            commitTask = nil
            snapshot.apply(value, model: model)
        }
    }
}

enum CaptureReadoutAdmission {
    static func canBegin(
        locked: Bool, sessionLocked: Bool, sceneActive: Bool, operatorPanel: Bool
    ) -> Bool {
        !locked && !sessionLocked && sceneActive && !operatorPanel
    }

    static func canCommit(canBegin: Bool, captureSheet: CaptureSheet?) -> Bool {
        canBegin && captureSheet == nil
    }

    static func replacing(_ current: CaptureSheet?, with next: CaptureSheet) -> CaptureSheet? {
        current == next ? nil : next
    }

    /// Photo has no video FORMAT / COLOR sheet. Open shooting mode instead so the slot stays useful.
    static func opening(_ sheet: CaptureSheet, isPhoto: Bool) -> CaptureSheet {
        guard isPhoto else { return sheet }
        switch sheet {
        case .resolution, .color: return .mode
        default: return sheet
        }
    }

    /// Persistent pickers follow the live mode. Video-only AUDIO closes; FORMAT / COLOR become MODE.
    static func retained(_ sheet: CaptureSheet?, isPhoto: Bool) -> CaptureSheet? {
        guard let sheet else { return nil }
        if !isPhoto { return sheet }
        switch sheet {
        case .resolution, .color: return .mode
        case .audio: return nil
        default: return sheet
        }
    }

    /// A held video drum cannot remap to MODE mid-gesture; drop it on stills.
    static func retainedDrum(_ sheet: CaptureSheet?, isPhoto: Bool) -> CaptureSheet? {
        guard let sheet else { return nil }
        if !isPhoto { return sheet }
        switch sheet {
        case .resolution, .color, .audio: return nil
        default: return sheet
        }
    }

    static func hidesLowerCaptureValues(sheet: CaptureSheet?, drum: CaptureSheet?) -> Bool {
        if let drum { return !drum.isTopAnchored }
        if let sheet { return !sheet.isTopAnchored }
        return false
    }
}
