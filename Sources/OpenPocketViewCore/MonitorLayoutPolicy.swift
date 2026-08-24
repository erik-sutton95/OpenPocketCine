import Foundation

/// Edge inset values used by the native monitor chrome.
public struct MonitorEdgeInsets: Equatable, Sendable {
    public static let zero = MonitorEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

    // Insets in points.
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Keeps the live camera surface full-bleed while placing touch chrome clear of device cutouts.
    public static func chrome(for safeArea: MonitorEdgeInsets) -> MonitorEdgeInsets {
        MonitorEdgeInsets(
            top: max(14, safeArea.top + 8),
            leading: max(16, safeArea.leading + 12),
            bottom: max(12, safeArea.bottom + 8),
            trailing: max(18, safeArea.trailing + 12)
        )
    }
}

/// Physical device orientation used to choose the live-view module direction.
public enum MonitorDeviceOrientation: Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
    case unknown
}

/// Horizontal orientation for live-view module layout.
public enum MonitorHorizontalLayoutDirection: Equatable, Sendable {
    /// Standard landscape-left layout.
    case standard

    /// Horizontally mirrored landscape-right layout.
    case mirrored

    /// Resolves the layout direction from the dominant landscape side cutout.
    public static func resolve(for safeArea: MonitorEdgeInsets) -> MonitorHorizontalLayoutDirection
    {
        let cutout = StartupSideCutoutAvoidance.resolve(for: safeArea)

        return cutout.trailing > cutout.leading ? .mirrored : .standard
    }

    /// Resolves the layout direction from device orientation first, with safe area as fallback.
    public static func resolve(
        deviceOrientation: MonitorDeviceOrientation,
        safeArea: MonitorEdgeInsets
    ) -> MonitorHorizontalLayoutDirection {
        switch deviceOrientation {
        case .landscapeRight:
            return .mirrored
        case .portrait, .portraitUpsideDown, .landscapeLeft:
            return .standard
        case .unknown:
            return resolve(for: safeArea)
        }
    }
}

/// Rectangular frame for the native monitor live feed.
public struct MonitorFeedFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Mirrors the frame around the viewport's vertical center line — the same operation the
    /// module frames carry, so the feed can follow the one-mirror-at-the-exit rule they follow.
    public func mirroredHorizontally(in viewportWidth: Double) -> MonitorFeedFrame {
        MonitorFeedFrame(
            x: max(0, viewportWidth) - x - width,
            y: y,
            width: width,
            height: height
        )
    }
}

/// Rectangular layout region used to anchor monitor modules.
public struct MonitorLayoutRegion: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    /// Creates a region covering the full viewport.
    public static func viewport(width: Double, height: Double) -> MonitorLayoutRegion {
        MonitorLayoutRegion(x: 0, y: 0, width: width, height: height)
    }

    /// Returns this region inset by the provided edges.
    public func inset(_ edges: MonitorEdgeInsets) -> MonitorLayoutRegion {
        MonitorLayoutRegion(
            x: x + max(0, edges.leading),
            y: y + max(0, edges.top),
            width: width - max(0, edges.leading) - max(0, edges.trailing),
            height: height - max(0, edges.top) - max(0, edges.bottom)
        )
    }

    /// Mirrors the region around the viewport's vertical center line.
    public func mirroredHorizontally(in viewportWidth: Double) -> MonitorLayoutRegion {
        MonitorLayoutRegion(
            x: max(0, viewportWidth) - x - width,
            y: y,
            width: width,
            height: height
        )
    }

    public func offsetBy(dx: Double, dy: Double) -> MonitorLayoutRegion {
        MonitorLayoutRegion(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func insetBy(dx: Double, dy: Double) -> MonitorLayoutRegion {
        MonitorLayoutRegion(
            x: x + dx, y: y + dy,
            width: max(0, width - 2 * dx), height: max(0, height - 2 * dy))
    }

    public func intersects(_ other: MonitorLayoutRegion) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
}

/// Side-cutout lanes used by landscape direction fallback.
///
/// Only insets at or above `minimumCutoutInset` count as hardware cutouts; ordinary
/// corner padding is ignored so an ambiguous landscape-right phone is not flipped
/// by a 44pt corner inset.
public struct StartupSideCutoutAvoidance: Equatable, Sendable {
    /// Minimum side safe-area inset that represents a hardware cutout rather than corner padding.
    public static let minimumCutoutInset = 50.0

    public static let none = StartupSideCutoutAvoidance(leading: 0, trailing: 0)

    /// Width to keep empty in the middle of the leading edge.
    public let leading: Double

    /// Width to keep empty in the middle of the trailing edge.
    public let trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }

    /// Whether either landscape side has a hardware cutout lane.
    public var hasSideCutout: Bool {
        leading > 0 || trailing > 0
    }

    /// Keeps only large side safe-area insets as cutout lanes, allowing normal corner padding.
    public static func resolve(for safeArea: MonitorEdgeInsets) -> StartupSideCutoutAvoidance {
        StartupSideCutoutAvoidance(
            leading: safeArea.leading >= minimumCutoutInset ? safeArea.leading : 0,
            trailing: safeArea.trailing >= minimumCutoutInset ? safeArea.trailing : 0
        )
    }
}
