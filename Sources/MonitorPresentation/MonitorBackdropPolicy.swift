import Foundation

/// Reference backdrop parameters, in logical display points and encoded RGB.
/// Blur, saturation and tint are independent; these are not material opacities.
public enum MonitorGlassDensity: CaseIterable, Hashable, Sendable {
    case compact, expanded, information, delivery, zoom, scope, recording

    public var blurRadius: Double {
        switch self {
        case .compact, .recording: 18
        case .expanded, .information, .delivery: 20
        case .zoom: 24
        case .scope: 8
        }
    }

    public var saturation: Double { self == .scope ? 1 : 1.25 }

    public var overlayOpacity: Double {
        switch self {
        case .compact: 0.52
        case .expanded: 0.62
        case .information: 0.82
        case .delivery: 0.86
        case .zoom: 0.72
        case .scope: 0.70
        case .recording: 0.08
        }
    }

    public var tintRGB: UInt32 {
        switch self {
        case .zoom: 0x121416
        case .scope: 0x060908
        case .recording: 0xFFFFFF
        default: 0x141618
        }
    }
}

public enum MonitorBackdropPolicy {
    public static let maximumDimension = 320
    /// Display-locked cap. Live SoftAP is ~25 fps; one job in flight is the
    /// real limiter. Do not sample a second decoder or a window capture.
    public static let minimumInterval: Double = 1.0 / 60.0
    public static let minimumIntervalNanoseconds: UInt64 = 16_666_667

    /// Native owners map their thermal state to this platform-neutral multiplier.
    public static func interval(serious: Bool, critical: Bool) -> Double {
        minimumInterval * (critical ? 5 : serious ? 3 : 1)
    }

    public static func intervalNanoseconds(serious: Bool, critical: Bool) -> UInt64 {
        minimumIntervalNanoseconds * (critical ? 5 : serious ? 3 : 1)
    }
}
