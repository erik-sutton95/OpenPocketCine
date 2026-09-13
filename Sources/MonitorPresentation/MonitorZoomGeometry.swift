import Foundation

/// The scale stays clear of a trailing cutout; its material continues to the
/// physical edge as one shape. Coordinates are local to that material's bounds.
public struct MonitorZoomGeometry: Equatable, Sendable {
    public let radius: Double
    public let edgeExtension: Double

    public init(width: Double, height: Double, trailingInset: Double = 0) {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        edgeExtension = min(width, trailingInset.isFinite ? max(0, trailingInset) : 0)
        let reference = min(
            min(width, height) >= 600 ? 330.0 : 260.0,
            max(120, (height - 24) / 2))
        radius = min(reference * 1.10, height / 2, max(0, width - edgeExtension))
    }

    public var width: Double { radius + edgeExtension }
    public var height: Double { radius * 2 }

    /// Includes the edge extension but excludes the transparent arc corners.
    public func contains(x: Double, y: Double) -> Bool {
        guard radius > 0, x.isFinite, y.isFinite,
            x >= 0, x <= width, y >= 0, y <= height
        else { return false }
        if x >= radius { return true }
        return pow(x - radius, 2) + pow(y - radius, 2) <= radius * radius
    }

    /// Only the original half-disc can arm a zoom gesture. The flat edge is
    /// excluded because its radial origin is singular at the midpoint.
    public func canStartZoom(x: Double, y: Double) -> Bool {
        x < radius && contains(x: x, y: y)
    }

    /// Original radial mapping; the gesture policy excludes the extension.
    public func angle(x: Double, y: Double) -> Double {
        atan2(radius - x, y - radius)
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
        guard isArmed, x.isFinite, y.isFinite, x < geometry.radius else { return nil }
        return geometry.angle(x: x, y: y)
    }
}
