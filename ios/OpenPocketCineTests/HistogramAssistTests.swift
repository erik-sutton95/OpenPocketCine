import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine histogram rows + `MovablePanel` ("histo") onto PocketCine.
/// HISTO's plot against this app's legacy scope plot rect (`scopePlotRect`). The scope
/// itself is pinned in OpenCineCameraControlsTests.
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
}
