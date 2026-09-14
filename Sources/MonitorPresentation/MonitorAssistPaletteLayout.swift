import Foundation

/// The palette's rendered rectangle is also its hit rectangle. Native hosts
/// anchor this intrinsic size at the same bottom-leading point in either state.
public struct MonitorAssistPaletteLayout: Equatable, Sendable {
    public static let padding: Double = 4
    public static let spacing: Double = 3
    /// The arrow retains its original 15-point lane; another 12 points catch right-side misses.
    public static let expansionButtonWidth: Double = 27
    public static let horizontalInsets: Double = padding * 2 + spacing + expansionButtonWidth
    public let portrait: Bool
    public let expanded: Bool
    public let width: Double
    public let height: Double
    public let cellWidth: Double
    public let cellHeight: Double
    public let scrollWidth: Double
    public let scrollHeight: Double
    public let columns: Int
    private let tablet: Bool
    private let toolCount: Int
    private let maximumWidth: Double
    private let maximumHeight: Double

    public var iconSide: Double {
        MonitorSystemButtonMetrics.iconSide(tablet: tablet)
    }

    public init(
        portrait: Bool, tablet: Bool, expanded: Bool, toolCount: Int,
        maximumWidth: Double, maximumHeight: Double
    ) {
        self.portrait = portrait
        self.expanded = expanded
        self.tablet = tablet
        self.toolCount = toolCount
        self.maximumWidth = maximumWidth
        self.maximumHeight = maximumHeight
        let limitW = max(1, maximumWidth.isFinite ? maximumWidth : 1)
        let limitH = max(1, maximumHeight.isFinite ? maximumHeight : 1)
        let count = max(0, toolCount)
        cellHeight = MonitorSystemButtonMetrics.side(tablet: tablet)
        // Expanded catalog cells match the collapsed favorites, including icon
        // size. Narrow canvases scroll instead of shrinking the tap target.
        cellWidth = cellHeight
        columns = max(1, (count + 1) / 2)
        let collapsedCount = min(count, portrait ? 1 : 2)
        let rowsHeight =
            Double(collapsedCount) * cellHeight
            + Double(max(0, collapsedCount - 1)) * Self.spacing
        if expanded {
            let catalogWidth =
                Double(columns) * cellWidth + Double(max(0, columns - 1)) * Self.spacing
                + Self.horizontalInsets
            width = min(
                limitW, portrait ? cellWidth + 8 : max(cellHeight + Self.horizontalInsets, catalogWidth))
            let desiredHeight =
                portrait
                ? Double(count) * cellHeight + Double(max(0, count - 1)) * Self.spacing + 35
                : 2 * cellHeight + 11
            height = min(limitH, desiredHeight)
        } else {
            width = min(limitW, cellHeight + (portrait ? 8 : Self.horizontalInsets))
            height = min(limitH, rowsHeight + (portrait ? 35 : 8))
        }
        scrollWidth = max(0, width - (portrait ? 8 : Self.horizontalInsets))
        scrollHeight = max(0, height - (portrait ? 35 : 8))
    }

    public func anchored(leading: Double, bottom: Double) -> MonitorRect {
        MonitorRect(x: leading, y: bottom - height, width: width, height: height)
    }

    /// Live and playback share this Field Monitor slot. Collapsed chrome equals
    /// `geometry.assists`; expansion grows up and trailing from that anchor.
    public static func fieldMonitor(
        _ geometry: FieldMonitorLayout, toolCount: Int, safeTop: Double
    ) -> (layout: Self, frame: MonitorRect) {
        let ceiling = max(8, safeTop.isFinite ? safeTop : 0)
        let maximumWidth =
            geometry.portrait
            ? geometry.viewport.width - (geometry.tablet ? 140 : 126)
            : geometry.values.maxX - geometry.assists.x
        let maximumHeight =
            geometry.portrait
            ? min(geometry.viewport.height * 0.62, geometry.assists.maxY - ceiling)
            : geometry.assists.maxY - ceiling
        let layout = Self(
            portrait: geometry.portrait, tablet: geometry.tablet, expanded: true,
            toolCount: toolCount, maximumWidth: maximumWidth, maximumHeight: maximumHeight)
        return (
            layout,
            layout.anchored(leading: geometry.assists.x, bottom: geometry.assists.maxY))
    }

    /// Both states use the same viewport limits during a clipped reveal.
    public func resolving(expanded: Bool) -> Self {
        Self(
            portrait: portrait, tablet: tablet, expanded: expanded, toolCount: toolCount,
            maximumWidth: maximumWidth, maximumHeight: maximumHeight)
    }
}
