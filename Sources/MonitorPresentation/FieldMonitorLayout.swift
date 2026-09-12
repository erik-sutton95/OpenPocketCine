import Foundation

public struct MonitorRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public struct MonitorSafeArea: Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

/// Device-independent geometry from the Field Monitor design. Viewport and
/// real window insets are inputs; camera brands and marketed device names are
/// deliberately absent. No drawing, observation, timers, or camera I/O.
public struct FieldMonitorLayout: Equatable, Sendable {
    public let viewport: MonitorRect
    public let picture: MonitorRect
    public let status: MonitorRect
    public let values: MonitorRect
    public let system: MonitorRect
    public let lock: MonitorRect
    public let gauges: MonitorRect
    public let settings: MonitorRect
    public let media: MonitorRect
    public let record: MonitorRect
    public let display: MonitorRect
    public let assists: MonitorRect
    public let stick: MonitorRect
    public let zoom: MonitorRect
    public let gimbal: MonitorRect
    public let aspectToggle: MonitorRect
    public let focusReset: MonitorRect
    public let portrait: Bool
    public let tablet: Bool
    public let fillsPicture: Bool

    public init(
        width: Double, height: Double, safeArea: MonitorSafeArea = .init(),
        sourceAspect: Double = 16 / 9, fill: Bool = false, showsValues: Bool = true,
        topControlInset: Double = 0
    ) {
        let w = max(1, width.isFinite ? width : 1)
        let h = max(1, height.isFinite ? height : 1)
        let aspect = sourceAspect.isFinite && sourceAspect > 0 ? sourceAspect : 16 / 9
        let controlInset = max(0, min(h, topControlInset.isFinite ? topControlInset : 0))
        viewport = .init(width: w, height: h)
        portrait = h > w
        tablet = min(w, h) >= 600
        let rec = tablet ? 84.0 : 70.0
        let button = tablet ? 48.0 : 54.0
        let hasHome = safeArea.bottom > 0
        let edge = 14.0
        let floor: Double
        if portrait {
            let top = max(0, safeArea.top - 24)
            let systemH = tablet ? 116.0 : 100.0
            let systemY = max(0, h - max(0, safeArea.bottom - 14) - systemH)
            system = .init(y: systemY, width: w, height: h - systemY)
            let valuesH = showsValues ? (tablet ? 43.0 : 74.0) : 0
            values = .init(x: edge, y: systemY - 8 - valuesH, width: w - 28, height: valuesH)
            floor = values.y - (showsValues ? 8 : 0)
            fillsPicture = fill || aspect < 1
            let ratio = fillsPicture ? min(aspect, 9 / 16) : aspect
            let ceiling = top + (tablet ? 52 : 44)
            let wideCeiling = safeArea.top > 24 ? ceiling : 8
            let pillarbox = tablet && w / ratio > max(0, floor - wideCeiling)
            let pictureH = pillarbox ? max(1, floor - wideCeiling) : w / ratio
            let pictureW = pillarbox ? pictureH * ratio : w
            let tall = !pillarbox && pictureH > floor - ceiling
            let low = safeArea.top > 24 ? max(0, safeArea.top - 5) : top
            let pictureY: Double
            if pictureH > h {
                pictureY = (h - pictureH) / 2
            } else if tall {
                pictureY = min(max(low, systemY - pictureH), max(0, h - pictureH))
            } else {
                pictureY = max(pillarbox ? wideCeiling : ceiling, floor - pictureH)
            }
            picture = .init(x: (w - pictureW) / 2, y: pictureY, width: pictureW, height: pictureH)
            let cy = systemY + systemH / 2
            lock = .init(x: edge, y: cy - button / 2, width: button, height: button)
            display = .init(x: edge + button + 8, y: lock.y, width: button, height: button)
            record = .init(x: (w - rec) / 2, y: cy - rec / 2, width: rec, height: rec)
            media = .init(x: w - edge - button, y: lock.y, width: button, height: button)
            settings = .init(x: media.x - button - 8, y: lock.y, width: button, height: button)
            let gaugeTop = (tablet ? 82.0 : max(4, top - 16)) + controlInset
            gauges = .init(
                x: tablet ? edge : w - edge - 104, y: gaugeTop,
                width: tablet ? 49 : 104, height: tablet ? 58 : 28)
            status = .init(
                x: edge,
                y: tablet
                    ? 12 + controlInset : max(max(50 + controlInset, gaugeTop + 36), picture.y + 8),
                width: w - 28, height: 30)
            assists = .init(
                x: pillarbox ? edge : picture.x + edge, y: floor - 94,
                width: 52, height: 78)
            stick = .init(
                x: pillarbox ? w - 104 : picture.maxX - 104,
                y: floor - 104, width: 88, height: 88)
            zoom = .init(x: stick.x, y: stick.y - 44, width: 44, height: 36)
            gimbal = .init(x: stick.maxX - 36, y: zoom.y, width: 36, height: 36)
            aspectToggle = .init(
                x: picture.midX - 24, y: max(ceiling, floor - 56), width: 48, height: 48)
        } else {
            fillsPicture = false
            // The physical cutout is smaller than the full safe inset. The
            // picture stays centred across either landscape orientation.
            let cut = max(0, max(safeArea.leading, safeArea.trailing) - 14)
            let imageW = min(w - 2 * cut, h * aspect)
            let imageH = imageW / aspect
            picture = .init(x: (w - imageW) / 2, y: (h - imageH) / 2, width: imageW, height: imageH)
            system = .init()
            let bottom = hasHome ? 16.0 : 12.0
            record = .init(x: w - 10 - rec, y: h - bottom - rec, width: rec, height: rec)
            // On the cutout edge DISP occupies the remaining band above REC.
            // The trailing rail retains its horizontal center across rotation.
            let cutoutHeight = safeArea.trailing >= 55 ? 112.0 : 124.0
            let availableDisplayHeight =
                safeArea.trailing > 0 && !tablet
                ? record.y - 8 - (h + cutoutHeight) / 2 - 4 : button
            let dispH = max(36, min(button, availableDisplayHeight))
            display = .init(
                x: record.midX - button / 2, y: record.y - 8 - dispH, width: button, height: dispH)
            let hasCutout = max(safeArea.leading, safeArea.trailing) > 0
            let cornerTop = (tablet ? 12.0 : (hasCutout ? 8.0 : 52.0)) + controlInset
            settings = .init(
                x: tablet ? w - 14 - button * 2 - 8 : record.midX - button / 2,
                y: cornerTop, width: button, height: button)
            media = .init(
                x: tablet ? settings.maxX + 8 : settings.x,
                y: tablet ? cornerTop : settings.maxY + 8, width: button, height: button)
            lock = .init(x: 18, y: 12 + controlInset, width: button, height: button)
            gauges = .init(x: 18, y: lock.maxY + 6, width: 49, height: 52)
            status = .init(
                x: max(77, picture.x + 12), y: 4 + controlInset,
                width: settings.x - max(77, picture.x + 12) - 12, height: tablet ? 46 : 35)
            let side = 14 + rec + 28
            let valuesH = showsValues ? (w < 740 ? 68.0 : 43.0) : 0
            values = .init(
                x: side, y: h - (hasHome ? 14 : 8) - valuesH,
                width: w - side * 2, height: valuesH)
            floor = values.y - 8
            assists = .init(x: 18, y: h - (hasHome ? 14 : 8) - 99, width: 73, height: 99)
            stick = .init(
                x: w - max(16 + rec + 12, safeArea.trailing + 6) - 88,
                y: floor - 88, width: 88, height: 88)
            zoom = .init(x: stick.x, y: stick.y - 44, width: 44, height: 36)
            gimbal = .init(x: stick.maxX - 36, y: zoom.y, width: 36, height: 36)
            aspectToggle = .init()
        }
        focusReset = .init(
            x: max(safeArea.leading + 8, stick.x - 50),
            y: stick.maxY - 40, width: 40, height: 40)
    }
}
