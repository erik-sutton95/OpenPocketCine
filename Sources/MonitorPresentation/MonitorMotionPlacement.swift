import Foundation

/// Placement for the floating Motion editor and its compact controls. An unset
/// preference follows the viewport; only an actual drag should store a center.
public enum MonitorMotionPlacement {
    /// Module-owned scalars keep optimized policy independent of platform
    /// geometry overlays. Native shells convert at their presentation boundary.
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public struct Size: Equatable, Sendable {
        public let width: Double
        public let height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public static func center(
        preferred: Point?, size: Size, viewport: Size, bounds: MonitorRect
    ) -> Point {
        // Both forms share a top edge while their measured widths center
        // independently. The 430pt reference height comes from the design.
        let top = max(16, (viewport.height - 430) / 2)
        let fallback = Point(x: viewport.width / 2, y: top + size.height / 2)
        return clamp(preferred ?? fallback, size: size, bounds: bounds)
    }

    /// Resolve visible bounds without rewriting the user's preferred position.
    public static func clamp(_ point: Point, size: Size, bounds: MonitorRect) -> Point {
        let halfWidth = max(size.width / 2, 20)
        let halfHeight = max(size.height / 2, 16)
        let left = bounds.x
        let top = bounds.y
        let right = bounds.maxX
        let bottom = bounds.maxY
        return Point(
            x: min(
                max(point.x, left + halfWidth),
                max(left + halfWidth, right - halfWidth)),
            y: min(
                max(point.y, top + halfHeight),
                max(top + halfHeight, bottom - halfHeight)))
    }
}
