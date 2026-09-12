import Foundation

/// Geometry for chrome only. The native video host is independent of these
/// metrics and therefore stays mounted through orientation or inspector changes.
public struct MonitorPlaybackLayout: Equatable, Sendable {
    public static let transportSize: Double = 48
    public static let transportSpacing: Double = 8
    public static let actionSize: Double = 44
    public static let actionSpacing: Double = 3
    public static var transportWidth: Double { transportSize * 3 + transportSpacing * 2 }
    public static var actionsWidth: Double { actionSize * 4 + actionSpacing * 3 }

    public let portrait: Bool
    public let contentWidth: Double
    public let inspectorWidth: Double
    public let paletteWidth: Double
    public let paletteHeight: Double
    public let paletteBottom: Double

    public init(width: Double, height: Double, tablet: Bool) {
        let available = max(0, width - 24)
        portrait = height > width
        contentWidth = min(tablet ? 860 : 630, available)
        inspectorWidth = min(296, available)
        paletteWidth = portrait ? max(1, width - (tablet ? 140 : 126)) : min(640, available)
        paletteHeight =
            portrait
            ? min(max(80, height - 300), height * 0.62)
            : max(80, height - 180)
        paletteBottom = portrait ? 168 : 110
    }
}
