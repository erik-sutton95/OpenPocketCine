import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct NDFilterRecommendationTests {
    /// The app's no-filter label (`NDAssist.noneLabel`).
    private static let noneLabel = "\u{2014}"

    /// Picture stops over grey to the suggested glass. Under half a stop is a
    /// deadband, under exposure never asks for ND, and the ladder caps at ND1000.
    @Test(
        arguments: [
            (0, 0, "—", "0.0", nil),
            (0.3, 0, "—", nil, nil),
            (0.5, 1, "ND2", nil, nil),
            (2, 2, "ND4", "+2.0", 4),
            (2.3, 2, "ND4", "+2.3", nil),
            (3, 3, "ND8", "+3.0", 8),
            (5, 5, "ND32", "+5.0", nil),
            (12, 10, "ND1000", nil, 1_000),
            (-1, 0, "—", "−1.0", nil),
            (-1.5, 0, "—", "−1.5", nil),
        ] as [(Double, Int, String, String?, Int?)])
    func suggestionFollowsTheOpticalLadder(
        pictureStops: Double, ndStops: Int, ndLabel: String, stopsLabel: String?,
        opticalFactor: Int?
    ) throws {
        let rec = try #require(
            MonitorNDFilterRecommendation.suggestion(
                pictureStops: pictureStops, noneLabel: Self.noneLabel))
        #expect(rec.ndStops == ndStops)
        #expect(rec.ndLabel == ndLabel)
        #expect(rec.needsGlass == (ndStops > 0))
        if let stopsLabel { #expect(rec.stopsLabel == stopsLabel) }
        if let opticalFactor { #expect(rec.opticalFactor == opticalFactor) }
    }

    @Test func histogramMedianMapsToPictureStops() {
        var bins = [Int](repeating: 0, count: 256)
        let gray = Int((MonitorTransfer.dlog.middleGrayEncoded * 255).rounded())
        bins[gray] = 1_000
        let rec = MonitorNDFilterRecommendation.reading(lumaHistogram: bins, transfer: .dlog)
        #expect(rec != nil)
        #expect(abs(rec!.pictureStops) < 0.15)
        #expect(rec!.ndStops == 0)
    }

    @Test func emptyHistogramIsNotAMeter() {
        #expect(
            MonitorNDFilterRecommendation.reading(
                lumaHistogram: [Int](repeating: 0, count: 256), transfer: .dlog2)
                == nil)
        #expect(
            MonitorNDFilterRecommendation.reading(lumaHistogram: [], transfer: .rec709)
                == nil)
    }

    @Test func densityIsThreeTenthsPerStop() {
        #expect(MonitorNDFilterRecommendation.densityPerStop == 0.3)
        #expect(MonitorNDFilterRecommendation.densityLabel(0) == "ND 0.0")
        #expect(MonitorNDFilterRecommendation.densityLabel(1) == "ND 0.3")
        #expect(MonitorNDFilterRecommendation.densityLabel(4.0 / 3.0) == "ND 0.4")
        #expect(MonitorNDFilterRecommendation.densityLabel(5) == "ND 1.5")
        #expect(MonitorNDFilterRecommendation.densityLabel(-1) == "ND −0.3")
    }

    @Test func chipLabelFollowsNotation() throws {
        let hot = try #require(
            MonitorNDFilterRecommendation.suggestion(pictureStops: 5, noneLabel: Self.noneLabel))
        #expect(hot.chipLabel(.stops) == "+5.0")
        #expect(hot.chipLabel(.factor) == "ND32")
        #expect(hot.chipLabel(.density) == "ND 1.5")
        let tiffen = try #require(
            MonitorNDFilterRecommendation.suggestion(
                pictureStops: 4.0 / 3.0, noneLabel: Self.noneLabel))
        #expect(tiffen.chipLabel(.density) == "ND 0.4")
        #expect(tiffen.chipLabel(.factor) == "ND2")
        let under = try #require(
            MonitorNDFilterRecommendation.suggestion(pictureStops: -1.5, noneLabel: Self.noneLabel))
        #expect(under.chipLabel(.factor) == "—")
        #expect(under.chipLabel(.stops) == "−1.5")
        #expect(MonitorNDFilterNotation.stops.editorLabel == "Stops")
        #expect(MonitorNDFilterNotation.factor.editorLabel == "ND32")
        #expect(MonitorNDFilterNotation.density.editorLabel == "ND 0.3")
    }
}
