import Foundation
import OpenCineMedia

public typealias NDFilterNotation = OpenCineMedia.MonitorNDFilterNotation
public typealias NDFilterSuggestion = OpenCineMedia.MonitorNDFilterSuggestion

/// Existing app-facing factory/labels, with portable calculation owned by Media.
public enum NDFilterRecommendation {
    public static let minStops = MonitorNDFilterRecommendation.minStops
    public static let maxStops = MonitorNDFilterRecommendation.maxStops
    public static let opticalFactors = MonitorNDFilterRecommendation.opticalFactors
    public static let noneLabel = "\u{2014}"
    public static let densityPerStop = MonitorNDFilterRecommendation.densityPerStop

    public static func opticalFactor(stops: Int) -> Int {
        MonitorNDFilterRecommendation.opticalFactor(stops: stops)
    }
    public static func ndLabel(stops: Int) -> String {
        MonitorNDFilterRecommendation.ndLabel(stops: stops, noneLabel: noneLabel)
    }
    public static func stopsLabel(_ stops: Double) -> String {
        MonitorNDFilterRecommendation.stopsLabel(stops, noneLabel: noneLabel)
    }
    public static func densityLabel(_ stops: Double) -> String {
        MonitorNDFilterRecommendation.densityLabel(stops, noneLabel: noneLabel)
    }
    public static func pictureStops(lumaHistogram bins: [Int], transfer: MonitorTransfer) -> Double?
    {
        MonitorNDFilterRecommendation.pictureStops(lumaHistogram: bins, transfer: transfer)
    }
    public static func suggestion(pictureStops: Double) -> NDFilterSuggestion {
        // The legacy direct factory normalized nonfinite input; observed reading remains optional.
        MonitorNDFilterRecommendation.suggestion(pictureStops: pictureStops, noneLabel: noneLabel)
            ?? NDFilterSuggestion(
                pictureStops: 0, ndStops: 0, opticalFactor: 1,
                ndLabel: noneLabel, stopsLabel: "0.0")
    }
    public static func reading(lumaHistogram bins: [Int], transfer: MonitorTransfer)
        -> NDFilterSuggestion?
    {
        MonitorNDFilterRecommendation.reading(
            lumaHistogram: bins, transfer: transfer, noneLabel: noneLabel)
    }
}
