import MonitorUI
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine histogram rows + `MovablePanel` ("histo") onto PocketCine.
/// HISTO's plot against the shared scope plot rect (`MonitorScopeGeometry.plotRect`). The scope
/// itself is pinned in OpenCineCameraControlsTests.
final class HistogramAssistTests: XCTestCase {
    func testHistogramPlotUsesWaveIREAxis() {
        let size = MonitorScopePanelSize.histogram
        let plot = HistogramAssist.plotRect(in: size)
        XCTAssertEqual(plot.minX, HistogramAssist.trafficGutter, accuracy: 0.01)
        XCTAssertEqual(plot.minY, MonitorWaveformAxis.titleHeight, accuracy: 0.01)
        XCTAssertEqual(plot.width, size.width - HistogramAssist.trafficGutter * 2, accuracy: 0.01)
        XCTAssertEqual(
            plot.height, size.height - MonitorWaveformAxis.titleHeight - MonitorWaveformAxis.bottomPad,
            accuracy: 0.01)
        XCTAssertGreaterThan(
            plot.minX, MonitorWaveformAxis.plotRect(in: size).minX,
            "lamp gutters push 0 / 100 inward of WAVE's side pad")
        XCTAssertEqual(
            HistogramAssist.ireX(0, in: plot),
            plot.minX + MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.ireX(100, in: plot),
            plot.maxX - MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(0, in: plot), MonitorWaveformAxis.plotX(0, plot), accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(100, in: plot), MonitorWaveformAxis.plotX(100, plot), accuracy: 0.01)
        XCTAssertEqual(
            HistogramAssist.plotX(30.50, in: plot),
            MonitorWaveformAxis.plotX(MonitorWaveformAxis.middleGrayIRE(transfer: .dlog2), plot),
            accuracy: 0.05)

        let leftover = MonitorScopeGeometry.plotRect(size, top: 26)
        let leftover0 = leftover.minX + 0.04 * leftover.width
        XCTAssertNotEqual(
            HistogramAssist.ireX(0, in: plot), leftover0, accuracy: 0.5,
            "HISTO 0 is WAVE's edge of the guttered plot, not the leftover 4% crush inset")

        let clip = HistogramAssist.ireX(HistogramAssist.clipZoneIRE, in: plot)
        XCTAssertGreaterThan(clip, HistogramAssist.ireX(50, in: plot))
        XCTAssertLessThan(clip, HistogramAssist.ireX(100, in: plot))
    }
}
