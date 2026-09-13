import Foundation

/// Trailing landscape disc vs portrait disc that sits above bottom chrome.
public enum MonitorZoomAttachment: Equatable, Sendable {
    case trailing
    case bottom
}

/// The scale stays clear of a trailing cutout or bottom chrome; its material
/// continues to the attached physical edge as one shape. Coordinates are local
/// to that material's bounds.
public struct MonitorZoomGeometry: Equatable, Sendable {
    public let radius: Double
    public let edgeExtension: Double
    public let attachment: MonitorZoomAttachment

    public init(
        width: Double, height: Double, trailingInset: Double = 0, bottomInset: Double = 0,
        attachment: MonitorZoomAttachment = .trailing
    ) {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        self.attachment = attachment
        switch attachment {
        case .trailing:
            edgeExtension = min(width, trailingInset.isFinite ? max(0, trailingInset) : 0)
            let reference = min(
                min(width, height) >= 600 ? 330.0 : 260.0,
                max(120, (height - 24) / 2))
            radius = min(reference * 1.10, height / 2, max(0, width - edgeExtension))
        case .bottom:
            edgeExtension = min(height, bottomInset.isFinite ? max(0, bottomInset) : 0)
            let reference = min(
                min(width, height) >= 600 ? 330.0 : 260.0,
                max(120, (width - 24) / 2))
            radius = min(reference * 1.10, width / 2, max(0, height - edgeExtension))
        }
    }

    public var width: Double {
        attachment == .trailing ? radius + edgeExtension : radius * 2
    }
    public var height: Double {
        attachment == .trailing ? radius * 2 : radius + edgeExtension
    }

    /// Includes the edge extension but excludes the transparent arc corners.
    public func contains(x: Double, y: Double) -> Bool {
        guard radius > 0, x.isFinite, y.isFinite,
            x >= 0, x <= width, y >= 0, y <= height
        else { return false }
        let inExtension = attachment == .trailing ? x >= radius : y >= radius
        if inExtension { return true }
        return pow(x - radius, 2) + pow(y - radius, 2) <= radius * radius
    }

    /// Only the original half-disc can arm a zoom gesture. The flat edge is
    /// excluded because its radial origin is singular at the midpoint.
    public func canStartZoom(x: Double, y: Double) -> Bool {
        guard contains(x: x, y: y) else { return false }
        return attachment == .trailing ? x < radius : y < radius
    }

    /// Original radial mapping; the gesture policy excludes the extension.
    public func angle(x: Double, y: Double) -> Double {
        switch attachment {
        case .trailing:
            return atan2(radius - x, y - radius)
        case .bottom:
            return atan2(radius - y, radius - x)
        }
    }
}

/// One pointer's radial projection, separate from the native edit transaction.
/// The material extension consumes input but cannot arm a gesture. Entering it
/// pauses an armed gesture; the first point back rebases without applying the
/// missing arc. Ordinary disc movement keeps its original angular mapping.
public struct MonitorZoomRadialGesture {
    private let geometry: MonitorZoomGeometry
    public let isArmed: Bool
    private var lastAngle: Double?
    private var accumulatedAngle = 0.0

    public init(geometry: MonitorZoomGeometry, startX: Double, startY: Double) {
        self.geometry = geometry
        isArmed = geometry.canStartZoom(x: startX, y: startY)
        lastAngle = isArmed ? geometry.angle(x: startX, y: startY) : nil
    }

    /// Native drag detectors may discard touch-slop movement before arming.
    /// This advances only the angle reference, never the accumulated output.
    public mutating func rebase(x: Double, y: Double) {
        lastAngle = radialAngle(x: x, y: y)
    }

    public mutating func angleDelta(x: Double, y: Double) -> Double? {
        guard isArmed else { return nil }
        guard let next = radialAngle(x: x, y: y) else {
            lastAngle = nil
            return nil
        }
        guard let previous = lastAngle else {
            lastAngle = next
            return nil
        }
        accumulatedAngle += next - previous
        lastAngle = next
        return accumulatedAngle
    }

    private func radialAngle(x: Double, y: Double) -> Double? {
        guard isArmed, x.isFinite, y.isFinite else { return nil }
        let onScale = geometry.attachment == .trailing ? x < geometry.radius : y < geometry.radius
        guard onScale else { return nil }
        return geometry.angle(x: x, y: y)
    }
}
