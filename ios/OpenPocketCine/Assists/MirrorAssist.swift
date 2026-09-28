import SwiftUI

/// OpenZCine `MonitorAssistTool.mirror`, plus a vertical axis.
///
/// Tap toggles the tool. Long-press options pick the axes: Horizontal (a body pointed
/// back at the operator) and Vertical (an underslung camera). Both on is a 180° turn.
enum MirrorAssist {
    static let explanation =
        "Flips the monitor for a camera pointed back at you or mounted upside down. "
        + "The recording and the scopes are never mirrored."
    static let horizontalHelp = "Left-to-right, for a camera pointed back at you."
    static let verticalHelp = "Top-to-bottom, for an underslung mount. Both on turns it 180°."

    /// OpenZCine `LiveFrameRaster.feedScale`: negative X for Horizontal, negative Y for Vertical.
    static func feedScale(
        mirrored: Bool,
        flippedVertically: Bool = false,
        squeeze: CGSize = CGSize(width: 1, height: 1)
    ) -> CGSize {
        CGSize(
            width: mirrored ? -squeeze.width : squeeze.width,
            height: flippedVertically ? -squeeze.height : squeeze.height)
    }

    static func longPressMenu(assist: LiveAssistState) -> MirrorLongPressMenu {
        MirrorLongPressMenu(assist: assist)
    }
}

/// Grid-style axis switches under the MIRROR help copy.
struct MirrorLongPressMenu: View {
    @Bindable var assist: LiveAssistState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MirrorAssist.explanation)
                .font(LiveType.ui(size: 13))
                .foregroundStyle(LiveDesign.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            SettingsSwitchInlineRow(
                title: "Horizontal", help: MirrorAssist.horizontalHelp, showTopDivider: false,
                isOn: assist.mirrorHorizontal, identifier: "mirror.horizontal"
            ) {
                assist.mirrorHorizontal.toggle()
                assist.persist()
            }
            SettingsSwitchInlineRow(
                title: "Vertical", help: MirrorAssist.verticalHelp,
                isOn: assist.mirrorVertical, identifier: "mirror.vertical"
            ) {
                assist.mirrorVertical.toggle()
                assist.persist()
            }
        }
    }
}
