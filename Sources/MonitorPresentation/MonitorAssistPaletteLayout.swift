import Foundation

/// The palette's rendered rectangle is also its hit rectangle. Native hosts
/// anchor this intrinsic size at the same bottom-leading point in either state.
public struct MonitorAssistPaletteLayout: Equatable, Sendable {
    public static let padding: Double = 4
    public static let spacing: Double = 3
    public let portrait: Bool
    public let expanded: Bool
    public let width: Double
    public let height: Double
    public let cellWidth: Double
    public let cellHeight: Double
    public let scrollWidth: Double
    public let scrollHeight: Double
    public let columns: Int

    public init(
        portrait: Bool, tablet: Bool, expanded: Bool, toolCount: Int,
        maximumWidth: Double, maximumHeight: Double
    ) {
        self.portrait = portrait
        self.expanded = expanded
        let limitW = max(1, maximumWidth.isFinite ? maximumWidth : 1)
        let limitH = max(1, maximumHeight.isFinite ? maximumHeight : 1)
        let count = max(0, toolCount)
        cellHeight = tablet ? 52 : 44
        // The reference shares seven landscape columns with the portrait rail.
        // Narrow canvases keep 44pt cells and scroll instead of shrinking taps.
        cellWidth = expanded ? max(44, floor((limitW - 44) / 7)) : cellHeight
        columns = max(1, (count + 1) / 2)
        let collapsedCount = min(count, portrait ? 1 : 2)
        let rowsHeight =
            Double(collapsedCount) * cellHeight
            + Double(max(0, collapsedCount - 1)) * Self.spacing
        if expanded {
            width = min(limitW, portrait ? cellWidth + 8 : limitW)
            let desiredHeight =
                portrait
                ? Double(count) * cellHeight + Double(max(0, count - 1)) * Self.spacing + 35
                : 2 * cellHeight + 11
            height = min(limitH, desiredHeight)
        } else {
            width = min(limitW, cellHeight + (portrait ? 8 : 26))
            height = min(limitH, rowsHeight + (portrait ? 35 : 8))
        }
        scrollWidth = max(0, width - (portrait ? 8 : 26))
        scrollHeight = max(0, height - (portrait ? 35 : 8))
    }

    public func anchored(leading: Double, bottom: Double) -> MonitorRect {
        MonitorRect(x: leading, y: bottom - height, width: width, height: height)
    }
}
