import SwiftUI

/// Scope bodies have equal horizontal margins in the space reserved for overlays.
/// The corner stays visible; its expanded touch area may extend past a side boundary.
/// Stored centres remain relative to the full canvas, so rotation does not rewrite preferences.
enum ScopePanelPlacement {
    static let padding: CGFloat = 8
    static let gripExtent: CGFloat = 44
    static let gripInterior: CGFloat = 12
    static let gripBottomExtent: CGFloat = 12
    static let gripTopInterior: CGFloat = 44

    static func bounds(in canvas: CGRect, clearance: EdgeInsets = EdgeInsets()) -> CGRect {
        let left = canvas.minX + max(0, clearance.leading) + padding
        let top = canvas.minY + max(0, clearance.top) + padding
        let right = canvas.maxX - max(0, clearance.trailing) - padding
        let bottom = canvas.maxY - max(0, clearance.bottom) - padding
        return CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }

    static func isUsable(_ bounds: CGRect) -> Bool {
        bounds.width >= gripExtent + gripInterior && bounds.height >= gripExtent + gripInterior
    }

    static func fittedSize(_ preferred: CGSize, in bounds: CGRect) -> CGSize {
        let scale = min(
            1, max(1, bounds.width) / max(1, preferred.width),
            max(1, bounds.height - gripBottomExtent) / max(1, preferred.height))
        return CGSize(
            width: max(1, floor(preferred.width * scale)),
            height: max(1, floor(preferred.height * scale)))
    }

    static func size(_ preferred: CGSize, canvas: CGRect, clearance: EdgeInsets) -> CGSize {
        guard canvas.width > 1, canvas.height > 1 else { return preferred }
        return fittedSize(preferred, in: bounds(in: canvas, clearance: clearance))
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let minX = bounds.minX + size.width / 2
        let minY = bounds.minY + max(size.height / 2, gripTopInterior - size.height / 2)
        return CGPoint(
            x: min(max(minX, point.x), max(minX, bounds.maxX - size.width / 2)),
            y: min(max(minY, point.y), max(minY, bounds.maxY - size.height / 2 - gripBottomExtent)))
    }
}
