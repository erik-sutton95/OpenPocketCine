import Foundation

/// Live-picture ND reading. Suggestion only — not a SET.
public struct NDFilterSuggestion: Equatable, Sendable {
    /// Stops vs 18% grey. Positive is hot.
    public var pictureStops: Double
    /// Rounded glass, 0…10. Zero means no ND.
    public var ndStops: Int
    public var opticalFactor: Int
    /// `"ND32"` or `"—"`.
    public var ndLabel: String
    /// `"+2.3"`, `"−1.0"`, or `"0.0"`.
    public var stopsLabel: String

    public var needsGlass: Bool { ndStops >= 1 }

    public init(
        pictureStops: Double, ndStops: Int, opticalFactor: Int, ndLabel: String, stopsLabel: String
    ) {
        self.pictureStops = pictureStops
        self.ndStops = ndStops
        self.opticalFactor = opticalFactor
        self.ndLabel = ndLabel
        self.stopsLabel = stopsLabel
    }
}

/// Meters the live luma histogram against middle gray and names a screw-on ND
/// that would balance the picture. Does not write the camera.
public enum NDFilterRecommendation: Sendable {
    public static let minStops = 1
    public static let maxStops = 10
    /// 1…9 are powers of two; 10 stops is the conventional ND1000, not 1024.
    public static let opticalFactors = [2, 4, 8, 16, 32, 64, 128, 256, 512, 1_000]
    public static let noneLabel = "—"

    public static func opticalFactor(stops: Int) -> Int {
        guard stops >= minStops else { return 1 }
        let idx = min(max(stops, minStops), maxStops) - 1
        return opticalFactors[idx]
    }

    public static func ndLabel(stops: Int) -> String {
        guard stops >= minStops else { return noneLabel }
        return "ND\(opticalFactor(stops: stops))"
    }

    public static func stopsLabel(_ stops: Double) -> String {
        guard stops.isFinite else { return "—" }
        if abs(stops) < 0.05 { return "0.0" }
        let sign = stops > 0 ? "+" : "−"
        return sign + String(format: "%.1f", abs(stops))
    }

    /// Median luma vs 18% grey, in stops. Nil when the histogram is empty.
    public static func pictureStops(lumaHistogram bins: [Int], transfer: MonitorTransfer) -> Double?
    {
        guard bins.count >= 2 else { return nil }
        var total = 0
        for count in bins { total += count }
        guard total > 0 else { return nil }
        var seen = 0
        let half = (total + 1) / 2
        let last = min(bins.count, 256)
        for code in 0..<last {
            seen += bins[code]
            if seen >= half {
                let encoded = Double(code) / 255.0
                let stops = LiveColorScience.stops(encoded: encoded, transfer: transfer)
                return stops.isFinite ? stops : nil
            }
        }
        return nil
    }

    /// Map measured picture stops onto glass. Under half a stop is no ND.
    public static func suggestion(pictureStops: Double) -> NDFilterSuggestion {
        let picture = pictureStops.isFinite ? pictureStops : 0
        let ndStops: Int
        if picture >= 0.5 {
            ndStops = min(
                max(Int((picture + 0.5).rounded(.down)), minStops),
                maxStops)
        } else {
            ndStops = 0
        }
        return NDFilterSuggestion(
            pictureStops: picture,
            ndStops: ndStops,
            opticalFactor: opticalFactor(stops: ndStops),
            ndLabel: ndLabel(stops: ndStops),
            stopsLabel: stopsLabel(picture))
    }

    /// Dynamic reading from the live tap. Nil only when the histogram is empty.
    public static func reading(lumaHistogram bins: [Int], transfer: MonitorTransfer)
        -> NDFilterSuggestion?
    {
        guard let picture = pictureStops(lumaHistogram: bins, transfer: transfer) else {
            return nil
        }
        return suggestion(pictureStops: picture)
    }
}
