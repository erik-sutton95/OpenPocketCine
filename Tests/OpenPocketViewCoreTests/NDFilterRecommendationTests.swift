import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct NDFilterRecommendationTests {
    @Test func middleGrayNeedsNoGlass() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 0)
        #expect(rec.ndStops == 0)
        #expect(rec.ndLabel == "—")
        #expect(rec.stopsLabel == "0.0")
        #expect(rec.needsGlass == false)
    }

    @Test func twoStopsHotIsND4() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 2)
        #expect(rec.ndStops == 2)
        #expect(rec.opticalFactor == 4)
        #expect(rec.ndLabel == "ND4")
        #expect(rec.stopsLabel == "+2.0")
        #expect(rec.needsGlass == true)
    }

    @Test func fiveStopsHotIsND32() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 5)
        #expect(rec.ndStops == 5)
        #expect(rec.ndLabel == "ND32")
        #expect(rec.stopsLabel == "+5.0")
    }

    @Test func twoPointThreeRoundsToND4() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 2.3)
        #expect(rec.ndStops == 2)
        #expect(rec.ndLabel == "ND4")
        #expect(rec.stopsLabel == "+2.3")
    }

    @Test func halfStopRoundsUpToND2() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 0.5)
        #expect(rec.ndStops == 1)
        #expect(rec.ndLabel == "ND2")
    }

    @Test func underExposureDoesNotSuggestND() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: -1.5)
        #expect(rec.ndStops == 0)
        #expect(rec.ndLabel == "—")
        #expect(rec.stopsLabel == "−1.5")
        #expect(rec.needsGlass == false)
    }

    @Test func deadbandHoldsUnderHalfStop() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 0.3)
        #expect(rec.ndStops == 0)
        #expect(rec.ndLabel == "—")
    }

    @Test func tenStopCapIsND1000NotND1024() {
        let rec = NDFilterRecommendation.suggestion(pictureStops: 12)
        #expect(rec.ndStops == 10)
        #expect(rec.opticalFactor == 1_000)
        #expect(rec.ndLabel == "ND1000")
    }

    @Test func histogramMedianMapsToPictureStops() {
        var bins = [Int](repeating: 0, count: 256)
        let gray = Int((MonitorTransfer.dlog.middleGrayEncoded * 255).rounded())
        bins[gray] = 1_000
        let rec = NDFilterRecommendation.reading(lumaHistogram: bins, transfer: .dlog)
        #expect(rec != nil)
        #expect(abs(rec!.pictureStops) < 0.15)
        #expect(rec!.ndStops == 0)
    }

    @Test func emptyHistogramIsNotAMeter() {
        #expect(
            NDFilterRecommendation.reading(
                lumaHistogram: [Int](repeating: 0, count: 256), transfer: .dlog2)
                == nil)
        #expect(
            NDFilterRecommendation.reading(lumaHistogram: [], transfer: .rec709)
                == nil)
    }

    @Test func labelsFollowTheOpticalLadder() {
        #expect(NDFilterRecommendation.ndLabel(stops: 0) == "—")
        #expect(NDFilterRecommendation.ndLabel(stops: 1) == "ND2")
        #expect(NDFilterRecommendation.ndLabel(stops: 3) == "ND8")
        #expect(NDFilterRecommendation.ndLabel(stops: 5) == "ND32")
        #expect(NDFilterRecommendation.ndLabel(stops: 10) == "ND1000")
        #expect(NDFilterRecommendation.stopsLabel(0) == "0.0")
        #expect(NDFilterRecommendation.stopsLabel(2.3) == "+2.3")
        #expect(NDFilterRecommendation.stopsLabel(-1) == "−1.0")
    }
}
