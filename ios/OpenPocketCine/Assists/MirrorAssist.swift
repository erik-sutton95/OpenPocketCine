import SwiftUI

/// OpenZCine `MonitorAssistTool.mirror`.
///
/// Tap toggles a left-to-right flip of the monitored picture (a body pointed back at the
/// operator). There is no H / V / both picker: `hasConfiguration` is false, so the toolbar
/// long-press does not open options. This menu exists for Display-settings exhaustiveness
/// and matches OpenZCine `AssistPanel` `.mirror` copy exactly.
enum MirrorAssist {
    static let explanation =
        "Flips the monitor left-to-right, for a camera pointed back at you. "
        + "The recording and the scopes are never mirrored."

    /// OpenZCine `LiveFrameRaster.feedScale` — negative X, never Y.
    static func feedScale(
        mirrored: Bool,
        squeeze: CGSize = CGSize(width: 1, height: 1)
    ) -> CGSize {
        guard mirrored else { return squeeze }
        return CGSize(width: -squeeze.width, height: squeeze.height)
    }

    /// OpenZCine `AssistPanel` `.mirror` body — help copy only.
    static func longPressMenu(
        assist _: LiveAssistState,
        compact: Bool = false
    ) -> MirrorLongPressMenu {
        MirrorLongPressMenu(compact: compact)
    }

    static func longPressMenu(compact: Bool = false) -> MirrorLongPressMenu {
        MirrorLongPressMenu(compact: compact)
    }
}

/// OpenZCine `AssistPanel` MIRROR copy: 13pt muted. Android `OptionCopy` is 11pt in the
/// compact settings strip — `compact` follows that.
struct MirrorLongPressMenu: View {
    var compact: Bool = false

    var body: some View {
        Text(MirrorAssist.explanation)
            .font(LiveType.ui(size: compact ? 11 : 13))
            .foregroundStyle(LiveDesign.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
