import Foundation

/// Camera-value drawers sit on a bottom-center well. Format, color and shooting
/// mode hang from a top-center well. Compact vs details is content, not a
/// second anchor — hold and tap share the well of the control that opened them.
public enum MonitorCapturePopupEdge: Equatable, Sendable {
    case top, bottom
}

/// Tap keeps the full drawer; hold/drag shows only the dials.
public enum MonitorCapturePopupKind: Equatable, Sendable {
    case details
    case compact

    public var showsClose: Bool { self == .details }
    public var showsAccessoryChrome: Bool { self == .details }
    public var subtitle: String? {
        switch self {
        case .compact: "drag to set"
        case .details: nil
        }
    }
}

/// Field Monitor capture-drawer geometry. Width and horizontal centering match
/// the mockup (`min(viewport − 28, 480/620)`). Bottom camera values keep the
/// existing well; top recording categories use the mockup top edge.
public struct MonitorCapturePopupLayout: Equatable, Sendable {
    public let edge: MonitorCapturePopupEdge
    public let width: Double
    public let centerX: Double
    public let top: Double
    public let bottom: Double
    public let maximumHeight: Double
    public let topPadding: Double
    public let bottomPadding: Double
    public let topCornerRadius: Double
    public let bottomCornerRadius: Double

    public init(
        viewportWidth: Double, viewportHeight: Double, tablet: Bool,
        safeArea: MonitorSafeArea = .init(), bottomBoundary: Double? = nil,
        ceiling: Double = 0, edge: MonitorCapturePopupEdge = .bottom,
        topBoundary: Double? = nil
    ) {
        self.edge = edge
        let w = max(0, viewportWidth.isFinite ? viewportWidth : 0)
        let h = max(0, viewportHeight.isFinite ? viewportHeight : 0)
        let portrait = h > w
        let left = min(w, max(14, safeArea.leading + 8))
        let right = max(left, w - max(14, safeArea.trailing + 8))
        width = min(tablet ? 620 : 480, max(0, right - left))
        centerX = min(right - width / 2, max(left + width / 2, w / 2))
        let requestedBottom = bottomBoundary.flatMap { $0.isFinite ? $0 : nil } ?? h
        bottom = min(h, max(0, requestedBottom))
        switch edge {
        case .bottom:
            top = max(8, safeArea.top + 8, ceiling)
            topPadding = 11
            bottomPadding = max(12, safeArea.bottom > 0 ? safeArea.bottom + 6 : 12)
            topCornerRadius = 16
            bottomCornerRadius = portrait ? 16 : 0
        case .top:
            let requestedTop = topBoundary.flatMap { $0.isFinite ? $0 : nil } ?? 0
            top = min(h, max(0, requestedTop))
            topPadding = portrait ? 12 : 16
            bottomPadding = 14
            topCornerRadius = portrait ? 16 : 0
            bottomCornerRadius = 16
        }
        maximumHeight = max(0, bottom - top)
    }
}

/// Typography determines the distance between adjacent labels. Finger travel
/// deliberately remains the independent 56-point detent policy.
public struct MonitorDrumMetrics: Equatable, Sendable {
    public let cellWidth: Double
    public let selectedScale: Double

    public init(options: [String]) {
        let length = max(4, options.map(\.count).max() ?? 4)
        selectedScale = length > 9 ? 1.4 : length > 6 ? 1.6 : 1.95
        cellWidth = max(108, (Double(length) * 9.1 * selectedScale + 26).rounded())
    }
}
