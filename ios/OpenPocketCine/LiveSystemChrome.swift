import MonitorPresentation
import MonitorUI
import SwiftUI

/// App display customization and integration photo/mode adapters over shared system composition.
struct LiveSystemChrome: View {
    @Environment(AppModel.self) private var model
    @Binding var locked: Bool
    let layout: FieldMonitorLayout
    let capturePresented: Bool
    let visible: Bool
    let interactive: Bool

    var body: some View {
        let editing = model.chromeEditorMode
        let visibility = MonitorSystemControlsVisibility(
            lock: model.multiviewExit != nil || model.chromeSectionMounts(.lockButton),
            settings: model.chromeSectionMounts(.railSettings),
            media: model.chromeSectionMounts(.railMedia),
            record: model.chromeSectionMounts(.railRecord)
        ).resolved(locked: locked, recording: model.control.isRecording,
            borrowed: model.session.isMultiviewBorrowed)
        MonitorSystemControls(
            layout: layout, visibility: visibility, capturePresented: capturePresented,
            visible: visible, interactive: interactive,
            navigationHidden: model.captureDrum != nil || (model.captureSheet != nil && !layout.portrait)
        ) {
            if let exit = model.multiviewExit {
                MonitorChromeButton("Return to Multiview",
                    size: CGSize(width: layout.lock.width, height: layout.lock.height), action: exit) {
                    MonitorIcon.layoutGrid.frame(width: layout.lock.width * 29 / 54,
                        height: layout.lock.height * 29 / 54)
                }
            } else {
                MonitorLockButton(locked: $locked, side: layout.lock.width)
                    .chromeEditable(.lockButton, editing: editing)
            }
        } settings: {
            LiveSettingsButton(size: layout.settings.width) { model.shell.open(.settings) }
                .chromeEditable(.railSettings, editing: editing)
        } media: {
            LiveMediaButton(size: layout.media.width) { model.shell.open(.media) }
                .chromeEditable(.railMedia, editing: editing)
        } record: {
            LiveRecordButton(diameter: layout.record.width)
                .chromeEditable(.railRecord, editing: editing)
        } display: {
            LiveDispToggle(size: CGSize(width: layout.display.width, height: layout.display.height))
        }
        .environment(\.interfaceLocked, locked)
    }
}
