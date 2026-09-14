import Foundation

/// Media filter card on an `ignoresSafeArea` canvas. Clears the island, home
/// indicator and the Filter chip row.
///
/// Media pages zero the landscape *clean-edge* island so the sidebar can hug
/// that bezel. This card hangs from the trailing side, so it still uses the
/// larger short-edge inset (the island lane) even when trailing was zeroed.
public enum MonitorMediaFilterPopupLayout: Sendable {
    public static let width = 320.0
    public static let preferredHeight = 420.0
    public static let edge = 12.0
    /// Heading + Filter chip under `pageTop` (`safeTop + topControlInset + 10`).
    public static let belowPageTop = 56.0

    public static func card(
        viewportWidth: Double, viewportHeight: Double,
        safeTop: Double, safeLeading: Double, safeBottom: Double, safeTrailing: Double,
        topControlInset: Double = 0
    ) -> MonitorRect {
        let pageTop = max(0, safeTop) + max(0, topControlInset) + 10
        let top = pageTop + belowPageTop
        let bottomPad = max(0, safeBottom) + edge
        let hanging = max(max(0, safeLeading), max(0, safeTrailing), 14)
        let trailingPad = hanging + edge
        let leadingPad = edge
        let maxX = max(leadingPad, viewportWidth - trailingPad)
        let cardWidth = min(width, max(160, maxX - leadingPad))
        let x = max(leadingPad, maxX - cardWidth)
        let maxHeight = max(140, viewportHeight - top - bottomPad)
        return MonitorRect(
            x: x, y: top, width: cardWidth, height: min(preferredHeight, maxHeight))
    }
}
