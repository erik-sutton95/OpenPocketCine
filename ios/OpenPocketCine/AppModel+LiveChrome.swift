import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI

typealias LiveCameraControlBar = CaptureControlBar<AppModel, EmptyView>
typealias FieldMonitorStatusChrome = LiveStatusChrome<AppModel>
typealias FieldMonitorAssistPalette = LiveAssistPalette<AppModel, AssistToolIcon>
typealias FieldMonitorGauges = LiveTelemetryGauges<AppModel>
typealias LiveTopPickerHost = LiveTopSheetHost<AppModel>
typealias ChromeEditBadgeLayer = ChromeEditBadges<AppModel>
typealias ChromeEditBanner = ChromeEditDoneBanner<AppModel>
typealias LiveSystemChrome = LiveSystemRail<AppModel, LiveRecordButton, LiveDispToggle>
typealias LiveFocusResetButton = FocusResetButton<AppModel>
typealias LiveAutoExposureUnlockButton = AutoExposureUnlockButton<AppModel>
typealias LiveHeadTrackCalibrateButton = HeadTrackCalibrateButton<LiveDesign>
typealias LivePortraitAspectToggle = PortraitAspectToggle<LiveDesign>
typealias LiveZoomPinchWell = FeedGestureWell<AppModel>
typealias LiveZoomChip = ZoomChip<AppModel>
typealias MonitorRecoveryOverlay = SessionRecoveryOverlay<AppModel>

extension LiveSystemRail
where Host == AppModel, Record == LiveRecordButton, Display == LiveDispToggle {
    init(
        locked: Binding<Bool>, layout: FieldMonitorLayout, capturePresented: Bool, visible: Bool,
        interactive: Bool
    ) {
        self.init(
            locked: locked, layout: layout, capturePresented: capturePresented, visible: visible,
            interactive: interactive
        ) {
            LiveRecordButton(diameter: $0)
        } display: {
            LiveDispToggle(size: $0)
        }
    }
}

extension LiveAssistPalette where Host == AppModel, Icon == AssistToolIcon {
    init(
        layout: LiveMonitorLayout, isLocked: Bool, otherOverlayPresented: Bool = false,
        expanded: Binding<Bool>, onExpansionActivityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            layout: layout, isLocked: isLocked, otherOverlayPresented: otherOverlayPresented,
            expanded: expanded, onExpansionActivityChange: onExpansionActivityChange
        ) { AssistToolIcon(tool: $0, size: nil) }
    }
}

extension SessionRecoveryOverlay where Host == AppModel {
    static func progressDetail(_ phase: ConnectionPhase) -> String {
        switch phase {
        case .idle, .scanning: "Looking for your camera…"
        case .connectingGatt, .pairing: "Connecting to your camera…"
        case .awaitingApproval: "Approve on the camera screen if asked."
        case .readingWifiCreds, .joiningWifi: "Rejoining camera Wi-Fi…"
        case .openingDatalink: "Restoring the camera connection…"
        case .live: "Waiting for a new live picture…"
        case .failed: "Connection attempt failed. Trying again…"
        }
    }
}

extension View {
    func chromeEditable(_ section: MonitorDisplayChrome.Section, editing mode: MonitorDisplayMode?)
        -> some View
    {
        modifier(ChromeEditableModifier<AppModel>(section: section, mode: mode))
    }
}

/// The shared live chrome on this app's session: the clock shows only while recording, and the
/// timecode only on bodies that report one.
extension AppModel: LiveChromeHost {
    var liveStatus: MonitorStatusPresentation {
        control.statusPresentation(
            elapsedSeconds: control.isRecording == nil ? nil : session.status.recordElapsedSec)
    }
    var timecodeAvailable: Bool { OsmoMonitorPresentation.capabilities(session).timecode }
    var liveSignalBars: Int { session.liveSignalBars }
    var liveFPS: String { session.liveFPS }
    var gimbalPanelOpen: Bool { liveGimbalPanel != .none }
    var multiviewBorrowed: Bool { session.isMultiviewBorrowed }
    func openSettings() { shell.open(.settings) }
    func openMedia() { shell.open(.media) }
    func resetFocusPoint() { session.resetFocusPoint() }
    func unlockAutoExposure() { session.unlockAutoExposure() }

    /// A pending zoom edit shows (and cycles) ahead of the camera's report.
    var zoomFactor: Double {
        if case .zoom(let pending)? = control.pending[.zoom] { return pending }
        return session.zoomReadout
    }
    var zoomCycleOrigin: Double {
        if case .zoom(let pending)? = control.pending[.zoom] { return pending }
        return session.zoomPinchPreview ?? session.zoomOptimistic ?? session.status.zoomFactor
            ?? session.zoomStop
    }
    var zoomPinchPreview: Double? { session.zoomPinchPreview }
    var zoomCeiling: Double { CamFov.maxFactor }
    var zoomTapStops: MonitorZoomTapStops { OsmoMonitorPresentation.zoomTapStops(session) }
    var zoomStops: [Double] { session.zoomStops }
    func cycleZoom(to ratio: Double) { commitZoomCycle(ratio) }
    func zoomPinchWillBegin() { control.cancelEdit(.zoom) }
    var canLockAutoExposure: Bool { session.canLockAutoExposure }
    func lockAutoExposure() -> Bool { session.lockAutoExposure() }
    func showControlNote(_ note: String) { session.controlNote = note }
    var tapFocusPoint: CGPoint? {
        guard session.supportsTapFocus, case .focus = session.focusOverlay else { return nil }
        return session.focusPoint
    }
    func handleFeedTap(at point: CGPoint) { session.handleFeedTap(at: point) }
    func startTracking(_ box: TrackingBox) { session.startTracking(box) }
    var sessionRecovery: SessionRecoveryState { session.sessionRecovery }
    var sessionRecoveryCardGraceElapsed: Bool { session.sessionRecoveryCardGraceElapsed }
    var recoveryDeviceName: String { session.recoveryDeviceName }
    var recoveryProgressDetail: String { MonitorRecoveryOverlay.progressDetail(session.phase) }
    func retrySessionRecovery() { session.retrySessionRecovery() }
}
