import SwiftUI

/// OpenZCine centre crosshair — tap toggles; long-press has no style / color / centre-mark
/// controls (`AssistPanel` `.crosshair`, Android `AssistTool.CROSS`).
///
/// Overlay is OpenZCine `FeedCrosshairView` / Android `drawCentreCrosshair`: a 40pt cross,
/// 1.4pt stroke, white at 65% opacity, centred on the feed. The iOS comment about a 46pt
/// ring plus 34pt cross is leftover prototype copy — neither platform draws a ring or a
/// centre mark, and `AssistConfiguration` has no crosshair fields.
enum CrosshairAssist {
    /// OpenZCine `AssistPanel` / Android `OptionCopy` for CROSS.
    static let helpCopy = "Tap the toolbar button to show or hide the centre crosshair."

    /// Full arm length in points (Android `20.dp` each side).
    static let armLength: CGFloat = 40
    static let strokeWidth: CGFloat = 1.4
    static let opacity: Double = 0.65

    /// OpenZCine `AssistPanel` `.crosshair` body — help copy only.
    static func longPressMenu(
        assist _: LiveAssistState,
        compact: Bool = false
    ) -> CrosshairLongPressMenu {
        CrosshairLongPressMenu(compact: compact)
    }

    static func overlay(feed: CGRect) -> Overlay {
        Overlay(feed: feed)
    }

    /// OpenZCine `FeedCrosshairView` — two 40×1.4 rectangles, white 65%, feed centre.
    struct Overlay: View {
        let feed: CGRect

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(CrosshairAssist.opacity))
                    .frame(width: CrosshairAssist.strokeWidth, height: CrosshairAssist.armLength)
                Rectangle()
                    .fill(Color.white.opacity(CrosshairAssist.opacity))
                    .frame(width: CrosshairAssist.armLength, height: CrosshairAssist.strokeWidth)
            }
            .position(x: feed.midX, y: feed.midY)
        }
    }
}

/// OpenZCine `AssistPanel` CROSS copy: 13pt muted. Android `OptionCopy` is 11pt in the
/// compact settings strip — `compact` follows that.
struct CrosshairLongPressMenu: View {
    var compact: Bool = false

    var body: some View {
        Text(CrosshairAssist.helpCopy)
            .font(LiveType.ui(size: compact ? 11 : 13))
            .foregroundStyle(LiveDesign.muted)
    }
}
