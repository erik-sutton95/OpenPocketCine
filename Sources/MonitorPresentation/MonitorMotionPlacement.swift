import Foundation

/// Placement for the floating Motion editor and its compact controls. An unset
/// preference follows the viewport; only an actual drag should store a center.
public enum MonitorMotionPlacement {
    public static func center(
        preferred: CGPoint?, size: CGSize, viewport: CGSize, bounds: MonitorRect
    ) -> CGPoint {
        // Both forms share a top edge while their measured widths center
        // independently. The 430pt reference height comes from the design.
        let top = max(16, (viewport.height - 430) / 2)
        let fallback = CGPoint(x: viewport.width / 2, y: top + size.height / 2)
        return clamp(preferred ?? fallback, size: size, bounds: bounds)
    }

    /// Resolve visible bounds without rewriting the user's preferred position.
    public static func clamp(_ point: CGPoint, size: CGSize, bounds: MonitorRect) -> CGPoint {
        let halfWidth = max(size.width / 2, 20)
        let halfHeight = max(size.height / 2, 16)
        let left = CGFloat(bounds.x)
        let top = CGFloat(bounds.y)
        let right = CGFloat(bounds.maxX)
        let bottom = CGFloat(bounds.maxY)
        return CGPoint(
            x: min(
                max(point.x, left + halfWidth),
                max(left + halfWidth, right - halfWidth)),
            y: min(
                max(point.y, top + halfHeight),
                max(top + halfHeight, bottom - halfHeight)))
    }
}
