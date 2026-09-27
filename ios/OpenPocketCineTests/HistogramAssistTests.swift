import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine histogram rows + `MovablePanel` ("histo") onto PocketCine.
final class HistogramAssistTests: XCTestCase {
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
}
