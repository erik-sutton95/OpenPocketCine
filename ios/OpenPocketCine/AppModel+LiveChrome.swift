import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
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

extension LiveSystemRail where Host == AppModel, Record == LiveRecordButton, Display == LiveDispToggle {
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

extension View {
    func chromeEditable(_ section: PocketDispChrome.Section, editing mode: PocketDispMode?)
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
}
