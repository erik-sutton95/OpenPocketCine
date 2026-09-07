import Foundation

/// Screw-on ND stop so 180° shutter holds. Recommendation only — not a SET.
public struct NDFilterSuggestion: Equatable, Sendable {
    public var stops: Int
    public var opticalFactor: Int
    public var label: String
    public var line: String

    public init(stops: Int, opticalFactor: Int, label: String, line: String) {
        self.stops = stops
        self.opticalFactor = opticalFactor
        self.label = label
        self.line = line
    }
}

/// How many ND stops would keep 180° (and native ISO, when the curve has one)
/// given the live shutter, ISO, and an optional picture meter.
///
/// Does not write the camera. Shells show ``NDFilterSuggestion/line`` and must
/// not dress it as a control.
public enum NDFilterRecommendation: Sendable {
    public static let minStops = 1
    public static let maxStops = 10
    /// 1…9 are powers of two; 10 stops is the conventional ND1000, not 1024.
    public static let opticalFactors = [2, 4, 8, 16, 32, 64, 128, 256, 512, 1_000]
    /// Ignore a meter inside a third of a stop so sky noise does not hunt ND.
    public static let pictureDeadbandStops = 1.0 / 3.0

    public static func opticalFactor(stops: Int) -> Int {
        let idx = min(max(stops, minStops), maxStops) - 1
        return opticalFactors[idx]
    }

    public static func label(stops: Int) -> String {
        "ND\(opticalFactor(stops: stops))"
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

    /// Manual expo only. Nil when already within half a stop of 180° / native.
    public static func suggest(
        expoMode: ExpoMode?,
        shutterDenom: Int,
        fps: Int,
        iso: Int,
        isoIsAuto: Bool,
        transfer: MonitorTransfer?,
        pictureStops: Double? = nil
    ) -> NDFilterSuggestion? {
        guard expoMode == .manual else { return nil }
        guard shutterDenom > 0, (8...240).contains(fps) else { return nil }
        let targetDenom = ShutterAngle.denom(
            degrees: ShutterAngle.defaultDegrees, fps: fps)
        guard targetDenom > 0 else { return nil }

        let shutterStops = log2(Double(shutterDenom) / Double(targetDenom))
        var isoStops = 0.0
        if !isoIsAuto, iso > 0, let native = CamCapIso.baseISO(transfer: transfer) {
            isoStops = log2(Double(iso) / Double(native))
        }
        let picture: Double
        if let p = pictureStops, p.isFinite, abs(p) >= pictureDeadbandStops {
            picture = p
        } else {
            picture = 0
        }
        let needed = shutterStops + isoStops + picture
        guard needed.isFinite, needed >= 0.5 else { return nil }
        let stops = min(
            max(Int((needed + 0.5).rounded(.down)), minStops),
            maxStops)
        let factor = opticalFactor(stops: stops)
        let name = label(stops: stops)
        let angle = ShutterAngle.label(ShutterAngle.defaultDegrees)
        return NDFilterSuggestion(
            stops: stops,
            opticalFactor: factor,
            label: name,
            line: "Try \(name) so \(angle) holds")
    }
}
