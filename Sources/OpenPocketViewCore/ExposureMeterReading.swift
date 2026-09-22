import Foundation

/// Picture brightness relative to 18% gray, independent of camera exposure compensation.
/// Shares the ND assist's median of native, pre-LUT luma codes and transfer curve.
public struct ExposureMeterReading: Equatable, Sendable {
    public let stops: Double?
    public let isEstimated: Bool

    public init(stops: Double?, isEstimated: Bool = false) {
        self.stops = stops.flatMap { $0.isFinite ? $0 : nil }
        self.isEstimated = isEstimated
    }

    public init(lumaHistogram: [Int], transfer: MonitorTransfer) {
        self.init(
            stops: NDFilterRecommendation.pictureStops(
                lumaHistogram: lumaHistogram, transfer: transfer),
            isEstimated: transfer == .dlogm)
    }

    /// Only the needle is bounded to the six-stop scale; the number retains the reading.
    public var needleFraction: Double? {
        stops.map { (min(3, max(-3, $0)) + 3) / 6 }
    }

    public var label: String {
        guard let stops else { return "—" }
        if abs(stops) < 0.05 { return "0.0" }
        return (stops > 0 ? "+" : "−")
            + String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), abs(stops))
    }

    public var accessibilityValue: String {
        guard let stops else { return "Unavailable, waiting for picture" }
        let estimate = isEstimated ? "Estimated, " : ""
        if abs(stops) < 0.05 { return estimate + "At middle gray" }
        return estimate + label + " stops relative to middle gray"
    }
}
