import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

/// The WAVE popup on this app's assist state, and WAVE's floor against this app's legacy
/// LIGHTS scale (`scopeLevelY`). The scope itself is pinned in OpenCineCameraControlsTests.
final class WaveformAssistTests: XCTestCase {
    /// This test's monitored source (XCTest makes a fresh one per test).
    private let ceiling = DJIScopeExposureCeiling()

    @MainActor
    func testPresentOptionsWiresTheSharedPopup() {
        let assist = LiveAssistState()
        let frame = CGRect(x: 40, y: 80, width: 250, height: 153)
        WaveformAssist.presentOptions(anchor: frame, assist: assist)
        XCTAssertEqual(assist.configureTool, .waveform)
        XCTAssertEqual(assist.longPressAnchor, frame)
    }

    func testIREZeroAndHundredSitOnPlotEdges() {
        let size = CGSize(width: 250, height: 153)
        let plot = MonitorWaveformAxis.plotRect(in: size)
        let shared = MonitorScopeGeometry.plotRect(size, top: 26)
        let line0 = MonitorWaveformAxis.scaleLineY(0, plot)
        let line100 = MonitorWaveformAxis.scaleLineY(100, plot)
        let line5 = MonitorWaveformAxis.scaleLineY(5, plot)
        let line95 = MonitorWaveformAxis.scaleLineY(95, plot)
        let grayIRE = MonitorWaveformAxis.middleGrayIRE(transfer: .dlog2)
        let lineGray = MonitorWaveformAxis.scaleLineY(grayIRE, plot)
        XCTAssertEqual(plot.height, 125, accuracy: 0.01)
        XCTAssertEqual(plot.maxY, size.height - MonitorWaveformAxis.bottomPad, accuracy: 0.01)
        XCTAssertGreaterThan(
            plot.maxY - shared.maxY, 5,
            "WAVE 0 uses the panel floor, not the 8pt shared chrome pad")
        XCTAssertEqual(line0, plot.maxY - MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(line100, plot.minY + MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            MonitorWaveformAxis.plotX(0, plot), plot.minX + MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            MonitorWaveformAxis.plotX(100, plot), plot.maxX - MonitorWaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            MonitorWaveformAxis.plotX(50, plot), plot.midX, accuracy: 0.01)
        XCTAssertEqual(line0 - line5, (line0 - line100) * 0.05, accuracy: 0.2)
        XCTAssertEqual(line95 - line100, (line0 - line100) * 0.05, accuracy: 0.2)
        XCTAssertEqual(grayIRE, 30.50, accuracy: 0.05)
        XCTAssertGreaterThan(lineGray - line100, (line0 - line100) * 0.55)
        XCTAssertLessThan(line0 - lineGray, (line0 - line100) * 0.75)

        let blackByte = MonitorWaveformAxis.legalBlackByte(transfer: .dlog2)
        XCTAssertEqual(blackByte, 16, "D-Log2 paper black is tap byte 16")
        XCTAssertEqual(
            MonitorWaveformAxis.levelTable(for: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2))[
                Int(blackByte)], 0, accuracy: 0.002)
        XCTAssertEqual(
            MonitorWaveformAxis.traceY(
                blackByte, transfer: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2), plot),
            line0, accuracy: 0.1,
            "crushed paper black sits on the drawn 0 line")
        let leftoverParade0 = MonitorScopeGeometry.legacyLevelY(ScopeDisplayScale.crushLevel, shared)
        XCTAssertGreaterThan(
            line0 - leftoverParade0, 8,
            "PARADE's 4% inset + 8pt pad must not be WAVE's floor")

        let grey = UInt8((LiveColorScience.encode(0.18, transfer: .dlog2) * 255).rounded())
        XCTAssertEqual(
            MonitorWaveformAxis.traceY(
                grey, transfer: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2), plot),
            lineGray, accuracy: 0.5,
            "18% gray sits on the paper-IRE guide, not 50")
        XCTAssertEqual(
            MonitorWaveformAxis.traceY(
                247, transfer: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2), plot), line100,
            accuracy: 0.01)
        XCTAssertEqual(
            MonitorWaveformAxis.traceY(
                223, transfer: .dlog, clipByte: ceiling.clipByte(transfer: .dlog), plot), line100,
            accuracy: 0.01)
        XCTAssertEqual(
            MonitorWaveformAxis.legalBlackByte(transfer: .dlog), 24,
            "D-Log paper black is tap byte 24")

        let table = MonitorWaveformAxis.levelTable(
            for: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2))
        let black = ScopePoint(
            xRatio: 0.5, yRatio: 0.5, red: blackByte, green: blackByte, blue: blackByte,
            luma: blackByte)
        let mid = ScopePoint(
            xRatio: 0.5, yRatio: 0.5, red: grey, green: grey, blue: grey, luma: grey)
        let clip = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 247, green: 247, blue: 247, luma: 247)
        var vertices = [MonitorScopeTraceMetal.Vertex](
            repeating: MonitorScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
            count: MonitorScopeTraceMetal.maxVertexCount(points: 3, mode: .waveform(.rgb)))
        let written = vertices.withUnsafeMutableBufferPointer { out in
            MonitorScopeTraceMetal.fillVertices(
                out, from: 0, points: [black, mid, clip], mode: .waveform(.rgb), rect: plot,
                opacity: 1, levelTable: table)
        }
        XCTAssertEqual(written, 9)
        XCTAssertEqual(Double(vertices[0].position.y) + 0.5, Double(line0), accuracy: 0.1)
        XCTAssertEqual(Double(vertices[3].position.y) + 0.5, Double(lineGray), accuracy: 0.5)
        XCTAssertEqual(Double(vertices[6].position.y) + 0.5, Double(line100), accuracy: 0.1)

        let leftoverCrush = MonitorWaveformAxis.plotY(ScopeDisplayScale.crushLevel, plot)
        XCTAssertEqual(
            leftoverCrush, line0, accuracy: 0.5,
            "a leftover 0.05 table value is 0.05 IRE (on 0), not a 5% shelf")
        XCTAssertGreaterThan(line0 - line5, 4)
    }
}
