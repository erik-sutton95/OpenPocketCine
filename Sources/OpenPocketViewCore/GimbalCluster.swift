import Foundation

/// Stick, zoom chip, and (later) gimbal controls as one parking spot.
/// Follow / speed / A·B·C attach to `controls` without moving the stick.
///
/// Zoom stacks above the stick, trailing-aligned. The cluster sits in the
/// cinema well's trailing-bottom (landscape and portrait fill) or just
/// under a 16:9 portrait strip (fit).
public struct GimbalCluster: Equatable, Sendable {
    public var stick: MonitorLayoutRegion
    public var zoom: MonitorLayoutRegion
    /// Leading of the stick, stick-tall. Width 0 until gimbal controls ship.
    public var controls: MonitorLayoutRegion

    public static let stickSize = 88.0
    public static let zoomSize = 44.0
    public static let gap = 8.0
    public static let inset = 16.0

    public var bounds: MonitorLayoutRegion {
        var minX = min(stick.x, zoom.x)
        var minY = min(stick.y, zoom.y)
        var maxX = max(stick.maxX, zoom.maxX)
        var maxY = max(stick.maxY, zoom.maxY)
        if controls.width > 1 {
            minX = min(minX, controls.x)
            minY = min(minY, controls.y)
            maxX = max(maxX, controls.maxX)
            maxY = max(maxY, controls.maxY)
        }
        return MonitorLayoutRegion(
            x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    public func offsetBy(dx: Double, dy: Double) -> GimbalCluster {
        GimbalCluster(
            stick: stick.offsetBy(dx: dx, dy: dy),
            zoom: zoom.offsetBy(dx: dx, dy: dy),
            controls: controls.offsetBy(dx: dx, dy: dy)
        )
    }

    /// On-well: stick.maxY is the lesser of `floorY` and the well's inset floor.
    public static func inTrailingBottom(
        well: MonitorLayoutRegion,
        floorY: Double,
        canvasMaxY: Double,
        avoid: MonitorLayoutRegion? = nil,
        stickSize: Double = stickSize,
        zoomSize: Double = zoomSize,
        gap: Double = gap,
        inset: Double = inset,
        controlsWidth: Double = 0
    ) -> GimbalCluster {
        let stickSize = max(0, stickSize)
        let inset = max(0, inset)
        let canvasFloor = canvasMaxY - inset
        let stickMaxY = min(min(floorY, well.maxY - inset), canvasFloor)
        var stickY = stickMaxY - stickSize
        stickY = max(well.y + inset, stickY)
        var stickX = well.maxX - inset - stickSize
        stickX = min(max(stickX, well.x + inset), max(well.x, well.maxX - inset - stickSize))
        var cluster = stacked(
            stickX: stickX, stickY: stickY, well: well,
            stickSize: stickSize, zoomSize: zoomSize, gap: gap,
            controlsWidth: controlsWidth)
        cluster = dodge(cluster, avoid: avoid, well: well, gap: gap, inset: inset)
        return cluster
    }

    /// Portrait 16:9 fit: zoom stays under the strip, stick sits on `floorY`.
    public static func belowWell(
        well: MonitorLayoutRegion,
        floorY: Double,
        stickSize: Double = stickSize,
        zoomSize: Double = zoomSize,
        gap: Double = gap,
        inset: Double = inset,
        controlsWidth: Double = 0
    ) -> GimbalCluster {
        let stickSize = max(0, stickSize)
        let zoomSize = max(0, zoomSize)
        let gap = max(0, gap)
        let inset = max(0, inset)
        let ceiling = well.maxY + gap
        let stickY = max(ceiling + zoomSize + gap, floorY - inset - stickSize)
        let stickX = max(well.x, well.maxX - inset - stickSize)
        return stacked(
            stickX: stickX, stickY: stickY, well: well,
            stickSize: stickSize, zoomSize: zoomSize, gap: gap,
            controlsWidth: controlsWidth, zoomFloor: ceiling)
    }

    private static func stacked(
        stickX: Double,
        stickY: Double,
        well: MonitorLayoutRegion,
        stickSize: Double,
        zoomSize: Double,
        gap: Double,
        controlsWidth: Double,
        zoomFloor: Double? = nil
    ) -> GimbalCluster {
        let zoomSize = max(0, zoomSize)
        let gap = max(0, gap)
        let controlsWidth = max(0, controlsWidth)
        let stick = MonitorLayoutRegion(x: stickX, y: stickY, width: stickSize, height: stickSize)
        let zoomX = min(max(well.x, stick.maxX - zoomSize), max(well.x, well.maxX - zoomSize))
        let stackedY = stick.y - gap - zoomSize
        let zoomY = max(zoomFloor ?? well.y, stackedY)
        let zoom = MonitorLayoutRegion(x: zoomX, y: zoomY, width: zoomSize, height: zoomSize)
        let controls: MonitorLayoutRegion
        if controlsWidth > 0 {
            controls = MonitorLayoutRegion(
                x: stick.x - gap - controlsWidth, y: stick.y,
                width: controlsWidth, height: stickSize)
        } else {
            controls = MonitorLayoutRegion(x: stick.x, y: stick.y, width: 0, height: 0)
        }
        return GimbalCluster(stick: stick, zoom: zoom, controls: controls)
    }

    private static func dodge(
        _ cluster: GimbalCluster,
        avoid: MonitorLayoutRegion?,
        well: MonitorLayoutRegion,
        gap: Double,
        inset: Double
    ) -> GimbalCluster {
        guard let avoid, avoid.width > 1, avoid.height > 1 else { return cluster }
        let padded = avoid.insetBy(dx: -gap, dy: -gap)
        guard cluster.bounds.intersects(padded) else { return cluster }
        // Width-constrained iPad parks record on the canvas floor. Lift the
        // cluster above it and keep the trailing edge — do not slide leading.
        let liftedMaxY = avoid.y - gap
        let liftedMinY = liftedMaxY - cluster.bounds.height
        if liftedMinY >= well.y + inset {
            return cluster.offsetBy(dx: 0, dy: liftedMaxY - cluster.bounds.maxY)
        }
        let dx: Double
        if avoid.midX >= cluster.bounds.midX {
            dx = avoid.x - gap - cluster.bounds.maxX
        } else {
            dx = avoid.maxX + gap - cluster.bounds.x
        }
        var next = cluster.offsetBy(dx: dx, dy: 0)
        let minX = well.x + inset
        if next.bounds.x < minX {
            next = next.offsetBy(dx: minX - next.bounds.x, dy: 0)
        }
        let maxX = well.maxX - inset
        if next.bounds.maxX > maxX {
            next = next.offsetBy(dx: maxX - next.bounds.maxX, dy: 0)
        }
        return next
    }
}
