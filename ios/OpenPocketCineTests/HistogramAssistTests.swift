import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine histogram rows + `MovablePanel` ("histo") onto PocketCine.
final class HistogramAssistTests: XCTestCase {
    func testOpenZCineOptionSet() {
        XCTAssertEqual(HistogramAssist.panelID, "histo")
        XCTAssertEqual(HistogramAssist.longPressPanelWidth, 400)
        XCTAssertEqual(HistogramAssist.baseSize, ScopePanelSize.histogram)
        XCTAssertEqual(HistogramAssist.scaleRange, 0.6...1.6)
        XCTAssertEqual(HistogramAssist.defaultScale, 1.0)
        XCTAssertEqual(HistogramAssist.holdDuration, 0.3)
        XCTAssertEqual(HistogramAssist.Options.default.trafficLights, true)
        XCTAssertEqual(HistogramAssist.Options.default.crushClipCompensation, .zero)
        XCTAssertEqual(HistogramAssist.Options.default.scale, 1.0)
        XCTAssertNil(HistogramAssist.Options.default.storedCenter)
    }

    func testOpenZCinePopupCopy() {
        XCTAssertEqual(HistogramAssist.panelTitle, "Histo")
        XCTAssertEqual(HistogramAssist.chip, "RGBL")
        XCTAssertEqual(HistogramAssist.trafficLightsTitle, "Traffic Lights")
        XCTAssertEqual(
            HistogramAssist.trafficLightsHelp,
            "Show small RGB edge blocks for crushed and clipped channels.")
        XCTAssertEqual(HistogramAssist.compensationTitle, "Crush/Clip Compensation")
        XCTAssertEqual(
            HistogramAssist.compensationHelp,
            "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."
        )
        XCTAssertEqual(HistogramAssist.clipZoneIRE, 95)
        XCTAssertEqual(HistogramAssist.plotTop, WaveformAxis.titleHeight)
        XCTAssertEqual(HistogramAssist.trafficLampWidth, 7.5)
        XCTAssertEqual(HistogramAssist.trafficOuterPad, 6)
        XCTAssertEqual(HistogramAssist.trafficLineGap, 4)
    }

    func testHistogramPlotUsesWaveIREAxis() {
        let size = ScopePanelSize.histogram
        let plot = HistogramAssist.plotRect(in: size)
        XCTAssertEqual(plot.minX, HistogramAssist.trafficGutter, accuracy: 0.01)
        XCTAssertEqual(plot.minY, WaveformAxis.titleHeight, accuracy: 0.01)
        XCTAssertEqual(plot.width, size.width - HistogramAssist.trafficGutter * 2, accuracy: 0.01)
        XCTAssertEqual(
            plot.height, size.height - WaveformAxis.titleHeight - WaveformAxis.bottomPad,
            accuracy: 0.01)
        XCTAssertGreaterThan(
            plot.minX, WaveformAxis.plotRect(in: size).minX,
            "lamp gutters push 0 / 100 inward of WAVE's side pad")
        XCTAssertEqual(
            HistogramAssist.ireX(0, in: plot),
            plot.minX + WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.ireX(100, in: plot),
            plot.maxX - WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(0, in: plot), WaveformAxis.plotX(0, plot), accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(100, in: plot), WaveformAxis.plotX(100, plot), accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(30.50, in: plot),
            WaveformAxis.plotX(WaveformAxis.middleGrayIRE(transfer: .dlog2), plot),
            accuracy: 0.05)

        let leftover = scopePlotRect(size, top: 26)
        let leftover0 = leftover.minX + 0.04 * leftover.width
        XCTAssertNotEqual(
            HistogramAssist.ireX(0, in: plot), leftover0, accuracy: 0.5,
            "HISTO 0 is WAVE's edge of the guttered plot, not the leftover 4% crush inset")

        let clip = HistogramAssist.ireX(HistogramAssist.clipZoneIRE, in: plot)
        XCTAssertGreaterThan(clip, HistogramAssist.ireX(50, in: plot))
        XCTAssertLessThan(clip, HistogramAssist.ireX(100, in: plot))
    }

    func testTrafficLightsSitOutsideMinMaxLines() {
        let size = ScopePanelSize.histogram
        let plot = HistogramAssist.plotRect(in: size)
        let leftLampMinX = HistogramAssist.trafficHorizontalInset
        let leftLampMaxX = leftLampMinX + HistogramAssist.trafficLampWidth
        let rightLampMaxX = size.width - HistogramAssist.trafficHorizontalInset
        let rightLampMinX = rightLampMaxX - HistogramAssist.trafficLampWidth
        let line0 = HistogramAssist.ireX(0, in: plot)
        let line100 = HistogramAssist.ireX(100, in: plot)
        XCTAssertLessThan(leftLampMaxX, line0, "crush lamps sit left of the 0 line")
        XCTAssertGreaterThan(rightLampMinX, line100, "clip lamps sit right of the 100 line")
        XCTAssertGreaterThan(leftLampMinX, 0)
        XCTAssertLessThan(rightLampMaxX, size.width)
        XCTAssertEqual(HistogramAssist.trafficHorizontalInset, HistogramAssist.trafficOuterPad)
        XCTAssertEqual(
            HistogramAssist.trafficGutter,
            HistogramAssist.trafficOuterPad + HistogramAssist.trafficLampWidth
                + HistogramAssist.trafficLineGap,
            accuracy: 0.01)
        XCTAssertEqual(
            line0 - leftLampMaxX, HistogramAssist.trafficLineGap + WaveformAxis.plotInset,
            accuracy: 0.01)
        XCTAssertEqual(
            rightLampMinX - line100, HistogramAssist.trafficLineGap + WaveformAxis.plotInset,
            accuracy: 0.01)
    }

    func testRemapPutsPaperBlackAndClipOnTheWaveEdges() {
        var bins = [Int](repeating: 0, count: 256)
        bins[5] = 8
        bins[16] = 100
        bins[78] = 40
        bins[188] = 25
        bins[247] = 20
        bins[255] = 10
        let out = WaveformAxis.remapHistogram(bins, transfer: .dlog2)
        XCTAssertEqual(out.reduce(0, +), 203)
        XCTAssertEqual(out[0], 108, "sub-black and paper black clamp onto IRE 0")
        XCTAssertEqual(out[255], 30, "live-tap 247 and overshoot 255 clamp onto IRE 100")
        let greyBucket = Int((WaveformAxis.ire(78.0 / 255, transfer: .dlog2) / 100 * 255).rounded())
        XCTAssertEqual(out[greyBucket], 40)
        XCTAssertEqual(greyBucket, 78)
        let earlyBucket = Int(
            (WaveformAxis.ire(188.0 / 255, transfer: .dlog2) / 100 * 255).rounded())
        XCTAssertEqual(out[earlyBucket], 25)
        XCTAssertLessThan(earlyBucket, 230, "188 is recoverable highlight, not the 100 line")
    }

    func testCrushClipCompensationMatchesOpenZCine() {
        XCTAssertEqual(
            HistogramAssist.CrushClipCompensation.allCases.map(\.rawValue),
            [0, 2, 5, 7, 10])
        XCTAssertEqual(
            HistogramAssist.CrushClipCompensation.allCases.map(\.label),
            ["0", "0.25", "0.5", "0.75", "1.0"])
        XCTAssertEqual(
            HistogramAssist.CrushClipCompensation.allCases.map(\.compactLabel),
            ["0", "¼", "½", "¾", "1"])
        XCTAssertEqual(HistogramAssist.CrushClipCompensation.zero.stops, 0)
        XCTAssertEqual(HistogramAssist.CrushClipCompensation.quarter.stops, 0.25)
        XCTAssertEqual(HistogramAssist.CrushClipCompensation.one.stops, 1.0)
        XCTAssertEqual(HistogramAssist.CrushClipCompensation.zero.pixelFractionThreshold, 0)
        XCTAssertEqual(
            HistogramAssist.CrushClipCompensation.quarter.pixelFractionThreshold, 0.025,
            accuracy: 1e-12)
        XCTAssertEqual(
            HistogramAssist.CrushClipCompensation.one.pixelFractionThreshold, 0.10,
            accuracy: 1e-12)
    }

    func testCompensationDecodeClampsLegacyOutOfRange() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(
                HistogramAssist.CrushClipCompensation.self, from: Data("15".utf8)),
            .one)
        XCTAssertEqual(
            try JSONDecoder().decode(
                HistogramAssist.CrushClipCompensation.self, from: Data("20".utf8)),
            .one)
        XCTAssertEqual(
            try JSONDecoder().decode(
                HistogramAssist.CrushClipCompensation.self, from: Data("-1".utf8)),
            .zero)
        XCTAssertEqual(
            try JSONDecoder().decode(
                HistogramAssist.CrushClipCompensation.self, from: Data("5".utf8)),
            .half)
    }

    func testScaleClampAndPanelSize() {
        XCTAssertEqual(HistogramAssist.Options.clampedScale(0.01), 0.6)
        XCTAssertEqual(HistogramAssist.Options.clampedScale(99), 1.6)
        XCTAssertEqual(HistogramAssist.Options.clampedScale(1.0), 1.0)
        XCTAssertEqual(HistogramAssist.Options(scale: 0.01).scale, 0.6)
        let sized = HistogramAssist.panelSize(scale: 0.7)
        XCTAssertEqual(sized.width, (250 * 0.7).rounded())
        XCTAssertEqual(sized.height, (77 * 0.7).rounded())
    }

    func testStoredCenterRoundTrip() {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 100)
        let stored = HistogramAssist.StoredCenter(center: CGPoint(x: 110, y: 70), in: bounds)
        XCTAssertEqual(stored.xFraction, 0.5, accuracy: 1e-12)
        XCTAssertEqual(stored.yFraction, 0.5, accuracy: 1e-12)
        let restored = stored.center(in: bounds)
        XCTAssertEqual(restored.x, 110, accuracy: 1e-9)
        XCTAssertEqual(restored.y, 70, accuracy: 1e-9)
    }

    func testDefaultCenterFallsInsideAboveAssistBar() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true,
            mirrored: false
        )
        let size = HistogramAssist.panelSize(scale: 1)
        let bounds = CGRect(origin: .zero, size: layout.viewport)
        let clearance = EdgeInsets(
            top: layout.topDeck.maxY,
            leading: 0,
            bottom: max(0, layout.viewport.height - layout.assist.minY),
            trailing: 0)
        let center = HistogramAssist.defaultCenter(
            feed: layout.feed, size: size, bounds: bounds, chromeClearance: clearance)
        XCTAssertEqual(center.x, layout.feed.maxX - size.width / 2, accuracy: 0.6)
        XCTAssertLessThan(center.y + size.height / 2, layout.assist.minY + 0.5)
        XCTAssertGreaterThan(center.y - size.height / 2, bounds.minY - 0.5)
        XCTAssertLessThanOrEqual(center.x + size.width / 2, bounds.maxX + 0.5)
    }

    func testResolvedCenterPrefersSessionThenStored() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let size = CGSize(width: 40, height: 20)
        let fallback = CGPoint(x: 20, y: 10)
        let stored = HistogramAssist.StoredCenter(center: CGPoint(x: 200, y: 100), in: bounds)
        XCTAssertEqual(
            HistogramAssist.resolvedCenter(
                session: CGPoint(x: 80, y: 60), stored: stored, defaultCenter: fallback,
                size: size, bounds: bounds),
            CGPoint(x: 80, y: 60))
        XCTAssertEqual(
            HistogramAssist.resolvedCenter(
                session: nil, stored: stored, defaultCenter: fallback,
                size: size, bounds: bounds),
            CGPoint(x: 200, y: 100))
        XCTAssertEqual(
            HistogramAssist.resolvedCenter(
                session: nil, stored: nil, defaultCenter: fallback,
                size: size, bounds: bounds),
            fallback)
    }

    func testSnapAndHapticCell() {
        let snapped = HistogramAssist.snap(CGPoint(x: 10.4, y: 21.6))
        XCTAssertEqual(snapped.x, 12, accuracy: 0.01)
        XCTAssertEqual(snapped.y, 20, accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.hapticCell(CGPoint(x: 22, y: 44)),
            1 &* 100_000 &+ 2)
    }

    func testOptionsDecodeFillsOpenZCineDefaults() throws {
        let decoded = try JSONDecoder().decode(HistogramAssist.Options.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .default)
        let scaled = try JSONDecoder().decode(
            HistogramAssist.Options.self, from: Data(#"{"scale":0.7,"trafficLights":false}"#.utf8))
        XCTAssertEqual(scaled.scale, 0.7, accuracy: 1e-12)
        XCTAssertFalse(scaled.trafficLights)
        XCTAssertEqual(scaled.crushClipCompensation, .zero)
    }

    func testCompensationThresholdDrivesTrafficLights() {
        // HISTO edge lights ride the core meter with the assist's stops/10 threshold.
        var bins = [Int](repeating: 0, count: 256)
        bins[16] = 3  // in the D-Log2 crush band [15…21]
        bins[128] = 97
        func crushes(_ threshold: Double) -> Bool {
            ScopeTrafficLights.reading(
                red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: threshold
            ).red.crush
        }
        XCTAssertTrue(crushes(0))
        XCTAssertTrue(
            crushes(HistogramAssist.CrushClipCompensation.quarter.pixelFractionThreshold))
        XCTAssertFalse(
            crushes(HistogramAssist.CrushClipCompensation.one.pixelFractionThreshold))
    }
}
