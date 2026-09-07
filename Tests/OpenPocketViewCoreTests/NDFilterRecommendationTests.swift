import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct NDFilterRecommendationTests {
    @Test func oneEightyAtNativeNeedsNoGlass() {
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: .manual,
                shutterDenom: 48,
                fps: 24,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog)
                == nil)
    }

    @Test func fourStopsOfShutterIsND16() {
        // 24 fps 180° is 1/48. 1/768 is four stops faster (768/48 = 16).
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 768,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.stops == 4)
        #expect(rec?.opticalFactor == 16)
        #expect(rec?.label == "ND16")
        #expect(rec?.line == "Try ND16 so 180° holds")
    }

    @Test func fiveStopsOfShutterIsND32() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 1_536,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.stops == 5)
        #expect(rec?.label == "ND32")
        #expect(rec?.line == "Try ND32 so 180° holds")
    }

    @Test func twoThousandthsRoundsToNearestStop() {
        // log2(2000/48) ≈ 5.38 → ND32.
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 2_000,
            fps: 24,
            iso: 1_600,
            isoIsAuto: false,
            transfer: .dlog2)
        #expect(rec?.stops == 5)
        #expect(rec?.label == "ND32")
    }

    @Test func isoAboveNativeAddsStops() {
        // 180° already, ISO 1600 vs D-Log 400 is two stops.
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 48,
            fps: 24,
            iso: 1_600,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.stops == 2)
        #expect(rec?.label == "ND4")
    }

    @Test func rec709IgnoresISOWhenThereIsNoNative() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 384,
            fps: 24,
            iso: 6_400,
            isoIsAuto: false,
            transfer: .rec709)
        #expect(rec?.stops == 3)
        #expect(rec?.label == "ND8")
    }

    @Test func autoExpoNeverSuggests() {
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: .auto,
                shutterDenom: 2_000,
                fps: 24,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog)
                == nil)
    }

    @Test func autoISODoesNotCountSensitivity() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 48,
            fps: 24,
            iso: 6_400,
            isoIsAuto: true,
            transfer: .dlog)
        #expect(rec == nil)
    }

    @Test func twentyFiveFpsUsesOneFiftieth() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 400,
            fps: 25,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.stops == 3)
        #expect(rec?.label == "ND8")
    }

    @Test func pictureOverexposureAddsStops() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 48,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog,
            pictureStops: 2)
        #expect(rec?.stops == 2)
        #expect(rec?.label == "ND4")
    }

    @Test func pictureDeadbandDoesNotNudge() {
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: .manual,
                shutterDenom: 48,
                fps: 24,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog,
                pictureStops: 0.3)
                == nil)
    }

    @Test func underexposedFastShutterNeedsLessND() {
        // Four shutter stops minus two of underexposure → ND4.
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 768,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog,
            pictureStops: -2)
        #expect(rec?.stops == 2)
        #expect(rec?.label == "ND4")
    }

    @Test func tenStopCapIsND1000NotND1024() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 16_000,
            fps: 24,
            iso: 25_600,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.stops == 10)
        #expect(rec?.opticalFactor == 1_000)
        #expect(rec?.label == "ND1000")
        #expect(rec?.line == "Try ND1000 so 180° holds")
    }

    @Test func halfStopRoundsUpToND2() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 48,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog,
            pictureStops: 0.5)
        #expect(rec?.stops == 1)
        #expect(rec?.label == "ND2")
    }

    @Test func missingShutterOrFpsIsSilent() {
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: .manual,
                shutterDenom: -1,
                fps: 24,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog)
                == nil)
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: .manual,
                shutterDenom: 2_000,
                fps: 0,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog)
                == nil)
        #expect(
            NDFilterRecommendation.suggest(
                expoMode: nil,
                shutterDenom: 2_000,
                fps: 24,
                iso: 400,
                isoIsAuto: false,
                transfer: .dlog)
                == nil)
    }

    @Test func copyIsASuggestionNotASET() {
        let rec = NDFilterRecommendation.suggest(
            expoMode: .manual,
            shutterDenom: 384,
            fps: 24,
            iso: 400,
            isoIsAuto: false,
            transfer: .dlog)
        #expect(rec?.line.hasPrefix("Try ") == true)
        #expect(rec?.line.localizedCaseInsensitiveContains("set") == false)
    }

    @Test func histogramMedianMapsToPictureStops() {
        var bins = [Int](repeating: 0, count: 256)
        let gray = Int((MonitorTransfer.dlog.middleGrayEncoded * 255).rounded())
        bins[gray] = 1_000
        let stops = NDFilterRecommendation.pictureStops(lumaHistogram: bins, transfer: .dlog)
        #expect(stops != nil)
        #expect(abs(stops!) < 0.15)

        var hot = [Int](repeating: 0, count: 256)
        let plusTwo = MonitorTransfer.dlog.encodeLinear(0.18 * 4)
        hot[Int((plusTwo * 255).rounded())] = 1_000
        let over = NDFilterRecommendation.pictureStops(lumaHistogram: hot, transfer: .dlog)
        #expect(over != nil)
        #expect(abs(over! - 2) < 0.15)
    }

    @Test func emptyHistogramIsNotAMeter() {
        #expect(
            NDFilterRecommendation.pictureStops(
                lumaHistogram: [Int](repeating: 0, count: 256),
                transfer: .dlog2)
                == nil)
        #expect(
            NDFilterRecommendation.pictureStops(lumaHistogram: [], transfer: .rec709)
                == nil)
    }

    @Test func labelsFollowTheOpticalLadder() {
        #expect(NDFilterRecommendation.label(stops: 1) == "ND2")
        #expect(NDFilterRecommendation.label(stops: 3) == "ND8")
        #expect(NDFilterRecommendation.label(stops: 5) == "ND32")
        #expect(NDFilterRecommendation.label(stops: 10) == "ND1000")
        #expect(NDFilterRecommendation.opticalFactor(stops: 10) == 1_000)
    }
}
