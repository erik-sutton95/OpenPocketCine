import Foundation

/// Capture drawers share one bottom-center anchor regardless of which readout
/// opened them. The host supplies the system-rail boundary in portrait and the
/// screen edge in landscape; a camera option never determines placement.
public struct MonitorCapturePopupLayout: Equatable, Sendable {
    public let width: Double
    public let centerX: Double
    public let bottom: Double
    public let maximumHeight: Double
    public let bottomPadding: Double

    public init(
        viewportWidth: Double, viewportHeight: Double, tablet: Bool,
        safeArea: MonitorSafeArea = .init(), bottomBoundary: Double? = nil,
        ceiling: Double = 0
    ) {
        let w = max(0, viewportWidth.isFinite ? viewportWidth : 0)
        let h = max(0, viewportHeight.isFinite ? viewportHeight : 0)
        let left = min(w, max(14, safeArea.leading + 8))
        let right = max(left, w - max(14, safeArea.trailing + 8))
        width = min(tablet ? 620 : 480, max(0, right - left))
        centerX = min(right - width / 2, max(left + width / 2, w / 2))
        let requestedBottom = bottomBoundary.flatMap { $0.isFinite ? $0 : nil } ?? h
        bottom = min(h, max(0, requestedBottom))
        let top = max(8, safeArea.top + 8, ceiling)
        maximumHeight = max(0, bottom - top)
        bottomPadding = max(12, safeArea.bottom > 0 ? safeArea.bottom + 6 : 12)
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
