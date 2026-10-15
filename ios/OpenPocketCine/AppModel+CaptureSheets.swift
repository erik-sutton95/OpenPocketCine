import MonitorPresentation
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

typealias LiveCapturePickerHost = CaptureSheetPickerHost<AppModel>
typealias CaptureControlSheet = CaptureSheetModal<AppModel>
typealias CapturePickerPanel = CaptureSheetPanel<AppModel>
typealias LiveCaptureDrumHost = CaptureSheetDrumHost<AppModel>
typealias CaptureReadoutGesture = CaptureSheetReadoutGesture<AppModel>

extension CaptureLists {
    static let nativeIsoHopHelp =
        "On: switching D-Log ↔ D-Log2 hops ISO to that curve's starred native if you were still on native. Off: keep the ISO you set."
}

extension CaptureQuickSnapshot {
    @MainActor static func primary(_ sheet: CaptureSheet, model: AppModel) -> Self? {
        let layout = OsmoMonitorPresentation.capabilities(model.session)
        switch sheet {
        case .aperture where !layout.iris, .audio where !layout.audio: return nil
        default: break
        }
        // WB shows the pending request over the reported value; other kinds read the same
        // reported status (only WB fields differ).
        var result = primary(
            sheet, status: model.session.whiteBalanceDisplayStatus,
            cameraModel: model.session.connectedCamera?.model,
            supportsFocusMode: layout.focus, supportsAperture: layout.iris,
            facePriorityExposureEnabled: model.facePriorityExposureEnabled,
            shutterUsesAngle: OperatorPrefs.shutterUsesAngle,
            shutterAngleDegrees: OperatorPrefs.shutterAngleDegrees,
            aeLocked: model.session.autoExposureLock != nil,
            awbLocked: model.session.autoWhiteBalanceLock != nil,
            offersAwbLock: model.session.canLockAutoWhiteBalance,
            profile: model.labelProfile, audioField: model.audioService?.fields.first,
            audioSourceID: model.audioService?.sourceID)
        if sheet == .shutter, model.session.status.expoMode == .auto,
            let field = model.control.captureField(.exposureCompensation) {
            result = .common(field)
            result?.enabled = field.isEditable && !model.facePriorityExposureEnabled
        }
        if sheet == .focus { result?.nativeEditor = model.control.edit(.focusMode) }
        return result
    }
}

/// The shared capture sheets on this app's session: ISO and white balance go out as typed camera
/// calls, EV and AF-S / AF-C through the common fields the sheets open.
extension AppModel: CaptureSheetHost {
    typealias Palette = LiveDesign

    var cameraStatus: CameraStatus { session.status }
    var displayStatus: CameraStatus { session.whiteBalanceDisplayStatus }
    /// main held ISO and shutter at the camera's report until it answered.
    var captureStripShowsPendingEdits: Bool { false }
    var connectedBody: CameraModel? { session.connectedCamera?.model }
    var sessionPhaseLabel: String { session.phase.label }
    var bodyFamily: CameraBodyFamily { session.bodyFamily }
    var labelProfile: CameraLabelProfile { connectedBody?.captureProfile?.labels ?? .standard }
    var audioService: CaptureAudioService? {
        guard OsmoMonitorPresentation.capabilities(session).audio,
            let cameraID = session.connectedCamera?.id else { return nil }
        let snapshot = session.control.current
        let sourceID = CaptureAudioSourceID(session: snapshot.session, epoch: snapshot.epoch)
        let status = session.status
        return CaptureAudioService(sourceID: sourceID, fields: [
            CaptureAudioField(id: .channel, title: "Channel",
                choices: AudioChannel.allCases.map(CaptureAudioValue.channel),
                observed: status.audioChannel.map(CaptureAudioValue.channel)),
            CaptureAudioField(id: .wind, title: "Wind",
                choices: WindNoiseReduction.allCases.map(CaptureAudioValue.wind),
                observed: status.windNR.map(CaptureAudioValue.wind)),
            CaptureAudioField(id: .direction, title: "Direction",
                choices: DirectionalAudio.allCases.map(CaptureAudioValue.direction),
                observed: status.directionalAudio.map(CaptureAudioValue.direction)),
            CaptureAudioField(id: .vocal, title: "Vocal",
                choices: VocalBoost.allCases.map(CaptureAudioValue.vocal),
                observed: status.vocalBoost.map(CaptureAudioValue.vocal))
        ], commit: { [weak self] value in
            guard let self, self.session.connectedCamera?.id == cameraID else { return .unavailable }
            let current = self.session.control.current
            guard CaptureAudioSourceID(session: current.session, epoch: current.epoch) == sourceID,
                OsmoMonitorPresentation.capabilities(self.session).audio else { return .unavailable }
            guard self.session.phase == .live, !self.session.isLocked else {
                self.session.controlNote = "Audio control refused"
                return .refused
            }
            switch value {
            case .channel(let channel): self.session.setAudioChannel(channel)
            case .wind(let wind): self.session.setWindNR(wind)
            case .direction(let direction): self.session.setDirectionalAudio(direction)
            case .vocal(let vocal): self.session.setVocalBoost(vocal)
            }
            return .submitted
        }, refresh: { [weak self] in
            guard let self, self.session.connectedCamera?.id == cameraID else { return }
            let current = self.session.control.current
            guard CaptureAudioSourceID(session: current.session, epoch: current.epoch) == sourceID else { return }
            await self.session.refreshAudioState()
        })
    }
    var colorModes: [ColorMode] { session.colorModes }
    var currentShootingMode: ShootingMode? { session.currentShootingMode }
    var sessionLocked: Bool { session.isLocked }
    var formatPinActive: Bool { session.isFormatPinActive }
    var autoExposureLocked: Bool { session.autoExposureLock != nil }
    var autoWhiteBalanceLocked: Bool { session.autoWhiteBalanceLock != nil }
    var canLockAutoWhiteBalance: Bool { session.canLockAutoWhiteBalance }
    var captureRouting: CaptureSheetRouting {
        .init(commonExposureCompensation: true, commonFocusMode: true)
    }
    var captureCapabilities: CaptureSheetCapabilities {
        let layout = OsmoMonitorPresentation.capabilities(session)
        return CaptureSheetCapabilities(
            focusMode: layout.focus, aperture: layout.iris,
            nativeISO: session.nativeISOCapabilities,
            audio: audioService != nil,
            faceMetering: false)
    }
    var focusOptions: [FocusOption] { FocusOption.allCases }
    var shutterUsesAngle: Bool {
        get { OperatorPrefs.shutterUsesAngle }
        set { OperatorPrefs.shutterUsesAngle = newValue }
    }
    var shutterAngleDegrees: Double { OperatorPrefs.shutterAngleDegrees }
    var coverOpen: Bool { shell.cover != nil }
    var operatorPanelOpen: Bool { shell.cover != nil }

    func quickSnapshot(_ sheet: CaptureSheet) -> CaptureQuickSnapshot? {
        CaptureQuickSnapshot.primary(sheet, model: self)
    }

    func commit(_ setting: CaptureSetting, from origin: CaptureCommitOrigin) {
        switch setting {
        case .iso(let iso): session.control.setISO(iso)
        case .isoAuto: session.control.setISO(.auto)
        case .isoManual(let label):
            if let iso = IsoIndex.allCases.first(where: { $0.label == label }),
                CaptureLists.isoIndices(from: session.status).contains(iso)
            {
                session.control.setISO(iso)
            }
        case .isoLimit(let limit): session.setIsoLimit(limit)
        case .ev(let ev): session.setEv(ev)
        case .shutterDenom(let denom): session.setShutterDenom(denom)
        case .shutterAngle(let degrees): session.setShutterAngle(degrees)
        case .whiteBalanceAuto: session.control.setWhiteBalanceAuto()
        case .whiteBalanceCustom(let kelvin, let tint):
            session.control.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
        case .whiteBalanceTint(let tint, let kelvin):
            // Auto SET keeps tint (Mimo). Tint pad must not kick Auto into Custom.
            if let kelvin {
                session.control.setWhiteBalanceCustom(kelvin: kelvin, tint: tint)
            } else {
                session.control.setWhiteBalanceAuto(tint: tint)
            }
        case .autoWhiteBalanceLock: session.lockAutoWhiteBalance()
        case .videoFormat(let format):
            session.setVideoFormat(resolution: format.resolution, frameRate: format.frameRate)
        case .colorMode(let mode): session.setColorMode(mode)
        case .shootingMode(let mode): session.setShootingMode(mode)
        case .aperture(let strategy): session.setApertureStrategy(strategy)
        case .expoMode(let mode): session.setExpoMode(mode)
        case .focus(let option, let label): commitFocus(option, label: label, from: origin)
        }
    }

    /// AF-S and plain AF-C commit through the focus field's editor; the tracking rows stay
    /// typed calls. A stale or missing editor commits nothing.
    private func commitFocus(_ option: FocusOption, label: String, from origin: CaptureCommitOrigin) {
        let editor: MonitorControlModel.Editor?
        switch origin {
        case .sheet(let field): editor = field?.editor
        case .readout(let native): editor = native
        }
        guard let editor, control.isCurrent(editor) else { return }
        if let commonValue = CaptureFocusAdmission.commonValue(label, track: session.status.focusTrack) {
            control.commit(commonValue, from: editor, label: "FOCUS \(label)")
        } else {
            session.setFocusOption(option)
        }
    }

    func captureDrumDidCommit(_ value: SettingValue) {}
    func refreshIsoLimit() async { await session.refreshIsoLimit() }
}
