import SwiftUI

/// OpenZCine portrait system bar (`.axisHorizontal`): lock + DISP on the leading
/// half, media + settings on the trailing half, record overlaid dead-centre so
/// unmounting a neighbour cannot walk the shutter off-centre.
struct LivePortraitSystemBar: View {
    @Environment(AppModel.self) private var model
    @Binding var interfaceLocked: Bool
    var chromeInteractive: Bool

    var body: some View {
        let editing = model.chromeEditorMode
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 14)
                    if model.chromeSectionMounts(.lockButton) || interfaceLocked {
                        LiveLockButton(locked: $interfaceLocked)
                            .chromeEditable(.lockButton, editing: editing)
                        Spacer(minLength: 14)
                    }
                    if chromeInteractive {
                        LiveDispToggle()
                            .chromeEditable(.statusBar, editing: editing)
                        Spacer(minLength: 14)
                    }
                }
                .frame(maxWidth: .infinity)

                if model.chromeSectionMounts(.railRecord) || model.session.status.isRecording {
                    Color.clear.frame(width: LiveChromeMetrics.recordButtonSize)
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 14)
                    if model.chromeSectionMounts(.railMedia) {
                        LiveMediaButton { model.liveOperatorPanel = .media }
                            .chromeEditable(.railMedia, editing: editing)
                        Spacer(minLength: 14)
                    }
                    if model.chromeSectionMounts(.railSettings) || model.session.status.isRecording
                    {
                        LiveSettingsButton { model.liveOperatorPanel = .settings }
                            .chromeEditable(.railSettings, editing: editing)
                        Spacer(minLength: 14)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if model.chromeSectionMounts(.railRecord) || model.session.status.isRecording {
                LiveRecordButton()
                    .chromeEditable(.railRecord, editing: editing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
