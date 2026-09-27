import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

final class WaveformAssistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
    }

    func testWaveAxisMatchesTrafficLightIRE() {
        let black = LiveColorScience.encode(0, transfer: .dlog2)
        let grey = LiveColorScience.encode(0.18, transfer: .dlog2)
        XCTAssertEqual(WaveformAxis.unit(black, transfer: .dlog2), 0, accuracy: 1e-9)
        XCTAssertEqual(
            WaveformAxis.unit(grey, transfer: .dlog2), 0.305, accuracy: 0.005,
            "D-Log2 18% gray stays at paper IRE 30.50, not remapped to 50")
        XCTAssertEqual(WaveformAxis.unit(247.0 / 255, transfer: .dlog2), 1, accuracy: 1e-4)
        XCTAssertEqual(WaveformAxis.unit(223.0 / 255, transfer: .dlog), 1, accuracy: 1e-4)
        XCTAssertLessThan(WaveformAxis.unit(188.0 / 255, transfer: .dlog2), 0.90)
        XCTAssertEqual(WaveformAxis.unit(1, transfer: .dlog2), 1, accuracy: 1e-9)
        XCTAssertEqual(WaveformAxis.unit(0, transfer: .dlog2), 0, accuracy: 1e-9)
        XCTAssertEqual(
            WaveformAxis.middleGrayIRE(transfer: .dlog2), 30.50, accuracy: 0.05)
        XCTAssertEqual(
            WaveformAxis.middleGrayIRE(transfer: .dlog), 39.88, accuracy: 0.05)
        let dlogBlack = LiveColorScience.encode(0, transfer: .dlog)
        let dlogGrey = LiveColorScience.encode(0.18, transfer: .dlog)
        XCTAssertEqual(WaveformAxis.unit(dlogBlack, transfer: .dlog), 0, accuracy: 1e-9)
        XCTAssertEqual(WaveformAxis.unit(dlogGrey, transfer: .dlog), 0.3988, accuracy: 0.005)
    }

    func testHoldWithoutDragOpensOptions() {
        XCTAssertTrue(WaveformAssist.shouldPresentOptions(translation: .zero))
        XCTAssertTrue(
            WaveformAssist.shouldPresentOptions(translation: CGSize(width: 3, height: -2)))
        XCTAssertFalse(
            WaveformAssist.shouldPresentOptions(translation: CGSize(width: 20, height: 0)))
    }

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
        let plot = WaveformAxis.plotRect(in: size)
        let shared = scopePlotRect(size, top: 26)
        let line0 = WaveformAxis.scaleLineY(0, plot)
        let line100 = WaveformAxis.scaleLineY(100, plot)
        let line5 = WaveformAxis.scaleLineY(5, plot)
        let line95 = WaveformAxis.scaleLineY(95, plot)
        let grayIRE = WaveformAxis.middleGrayIRE(transfer: .dlog2)
        let lineGray = WaveformAxis.scaleLineY(grayIRE, plot)
        XCTAssertEqual(plot.height, 125, accuracy: 0.01)
        XCTAssertEqual(plot.maxY, size.height - WaveformAxis.bottomPad, accuracy: 0.01)
        XCTAssertGreaterThan(
            plot.maxY - shared.maxY, 5,
            "WAVE 0 uses the panel floor, not the 8pt shared chrome pad")
        XCTAssertEqual(line0, plot.maxY - WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(line100, plot.minY + WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            WaveformAxis.plotX(0, plot), plot.minX + WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            WaveformAxis.plotX(100, plot), plot.maxX - WaveformAxis.plotInset, accuracy: 0.01)
        XCTAssertEqual(
            WaveformAxis.plotX(50, plot), plot.midX, accuracy: 0.01)
        XCTAssertEqual(line0 - line5, (line0 - line100) * 0.05, accuracy: 0.2)
        XCTAssertEqual(line95 - line100, (line0 - line100) * 0.05, accuracy: 0.2)
        XCTAssertEqual(grayIRE, 30.50, accuracy: 0.05)
        XCTAssertGreaterThan(lineGray - line100, (line0 - line100) * 0.55)
        XCTAssertLessThan(line0 - lineGray, (line0 - line100) * 0.75)

        let blackByte = WaveformAxis.legalBlackByte(transfer: .dlog2)
        XCTAssertEqual(blackByte, 16, "D-Log2 paper black is tap byte 16")
        XCTAssertEqual(
            WaveformAxis.levelTable(for: .dlog2)[Int(blackByte)], 0, accuracy: 0.002)
        XCTAssertEqual(
            WaveformAxis.traceY(blackByte, transfer: .dlog2, plot), line0, accuracy: 0.1,
            "crushed paper black sits on the drawn 0 line")
        let leftoverParade0 = scopeLevelY(ScopeDisplayScale.crushLevel, shared)
        XCTAssertGreaterThan(
            line0 - leftoverParade0, 8,
            "PARADE's 4% inset + 8pt pad must not be WAVE's floor")

        let grey = UInt8((LiveColorScience.encode(0.18, transfer: .dlog2) * 255).rounded())
        XCTAssertEqual(
            WaveformAxis.traceY(grey, transfer: .dlog2, plot), lineGray, accuracy: 0.5,
            "18% gray sits on the paper-IRE guide, not 50")
        XCTAssertEqual(
            WaveformAxis.traceY(247, transfer: .dlog2, plot), line100, accuracy: 0.01)
        XCTAssertEqual(
            WaveformAxis.traceY(223, transfer: .dlog, plot), line100, accuracy: 0.01)
        XCTAssertEqual(
            WaveformAxis.legalBlackByte(transfer: .dlog), 24,
            "D-Log paper black is tap byte 24")

        let table = WaveformAxis.levelTable(for: .dlog2)
        let black = ScopePoint(
            xRatio: 0.5, yRatio: 0.5, red: blackByte, green: blackByte, blue: blackByte,
            luma: blackByte)
        let mid = ScopePoint(
            xRatio: 0.5, yRatio: 0.5, red: grey, green: grey, blue: grey, luma: grey)
        let clip = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 247, green: 247, blue: 247, luma: 247)
        var vertices = [ScopeTraceMetal.Vertex](
            repeating: ScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
            count: ScopeTraceMetal.maxVertexCount(points: 3, mode: .waveform(.rgb)))
        let written = vertices.withUnsafeMutableBufferPointer { out in
            ScopeTraceMetal.fillVertices(
                out, from: 0, points: [black, mid, clip], mode: .waveform(.rgb), rect: plot,
                opacity: 1, levelTable: table)
        }
        XCTAssertEqual(written, 9)
        XCTAssertEqual(Double(vertices[0].position.y) + 0.5, Double(line0), accuracy: 0.1)
        XCTAssertEqual(Double(vertices[3].position.y) + 0.5, Double(lineGray), accuracy: 0.5)
        XCTAssertEqual(Double(vertices[6].position.y) + 0.5, Double(line100), accuracy: 0.1)

        let leftoverCrush = WaveformAxis.plotY(ScopeDisplayScale.crushLevel, plot)
        XCTAssertEqual(
            leftoverCrush, line0, accuracy: 0.5,
            "a leftover 0.05 table value is 0.05 IRE (on 0), not a 5% shelf")
        XCTAssertGreaterThan(line0 - line5, 4)
    }

    func testSafeBordersAreDottedFiveAndNinetyFive() {
        let on = WaveformAxis.guideStrokes(
            clip: true, crush: true, middle: true, transfer: .dlog2)
        XCTAssertEqual(on.count, 5)
        XCTAssertEqual(on[0].ire, 0, accuracy: 0.01)
        XCTAssertEqual(on[1].ire, 100, accuracy: 0.01)
        XCTAssertEqual(on[2].ire, 5, accuracy: 0.01)
        XCTAssertEqual(on[3].ire, 95, accuracy: 0.01)
        XCTAssertEqual(on[4].ire, 30.50, accuracy: 0.05)
        XCTAssertFalse(on[0].dashed || on[0].usesCrushClipColor, "0 is the solid min line")
        XCTAssertFalse(on[1].dashed || on[1].usesCrushClipColor, "100 is the solid max line")
        XCTAssertTrue(on[2].dashed && on[2].usesCrushClipColor, "5 is the dotted crush buffer")
        XCTAssertTrue(on[3].dashed && on[3].usesCrushClipColor, "95 is the dotted clip buffer")
        XCTAssertFalse(on[4].dashed || on[4].usesCrushClipColor, "gray is a solid paper-IRE line")
        XCTAssertEqual(WaveformAxis.crushClipDash, [3, 3])
        let off = WaveformAxis.guideStrokes(
            clip: false, crush: false, middle: false, transfer: .dlog2)
        XCTAssertEqual(off.map(\.ire), [0, 100])
        let dlog = WaveformAxis.guideStrokes(
            clip: false, crush: false, middle: true, transfer: .dlog)
        XCTAssertEqual(dlog.last?.ire ?? 0, 39.88, accuracy: 0.05)
    }

    func testISOMovesClipOnly() {
        let grey = LiveColorScience.encode(0.18, transfer: .dlog2)
        let black = LiveColorScience.encode(0, transfer: .dlog2)
        let at1600 = WaveformAxis.unit(grey, transfer: .dlog2, iso: 1600)
        let at400 = WaveformAxis.unit(grey, transfer: .dlog2, iso: 400)
        XCTAssertEqual(at1600, 0.305, accuracy: 0.005)
        XCTAssertEqual(at400, 0.305, accuracy: 0.005)
        XCTAssertEqual(WaveformAxis.unit(black, transfer: .dlog2, iso: 400), 0, accuracy: 1e-9)
        let clip1600 = ScopeExposureCeiling.clipEncoded(transfer: .dlog2, iso: 1600)
        let clip400 = ScopeExposureCeiling.clipEncoded(transfer: .dlog2, iso: 400)
        XCTAssertEqual(WaveformAxis.unit(clip1600, transfer: .dlog2, iso: 1600), 1, accuracy: 1e-9)
        XCTAssertEqual(WaveformAxis.unit(clip400, transfer: .dlog2, iso: 400), 1, accuracy: 1e-9)
        XCTAssertLessThan(clip400, clip1600, "lower EI pulls 100 down; gray stays at paper IRE")
    }

    @MainActor
    func testOrientationCentresStayIndependent() {
        let landscape = CGRect(x: 0, y: 0, width: 874, height: 402)
        let portrait = CGRect(x: 0, y: 0, width: 402, height: 874)
        XCTAssertEqual(ScopeCanvasSlot.forBounds(landscape), .landscape)
        XCTAssertEqual(ScopeCanvasSlot.forBounds(portrait), .portrait)

        let store = WaveformAssistStore(options: .default)
        store.beginDrag(center: CGPoint(x: 120, y: 80), in: landscape)
        store.endDrag(bounds: landscape)
        store.beginDrag(center: CGPoint(x: 200, y: 400), in: portrait)
        store.endDrag(bounds: portrait)

        let land = store.storedCenter(in: landscape)?.center(in: landscape)
        let port = store.storedCenter(in: portrait)?.center(in: portrait)
        XCTAssertEqual(land?.x ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(land?.y ?? 0, 80, accuracy: 0.5)
        XCTAssertEqual(port?.x ?? 0, 200, accuracy: 0.5)
        XCTAssertEqual(port?.y ?? 0, 400, accuracy: 0.5)
        XCTAssertNotEqual(store.options.storedCenter, store.options.storedCenterPortrait)
    }

    func testLegacyStoredCenterStaysLandscapeOnly() throws {
        let data = Data(#"{"storedCenter":{"xFraction":0.25,"yFraction":0.4}}"#.utf8)
        let decoded = try JSONDecoder().decode(WaveformAssist.Options.self, from: data)
        XCTAssertEqual(decoded.storedCenter?.xFraction ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(decoded.storedCenter?.yFraction ?? 0, 0.4, accuracy: 0.001)
        XCTAssertNil(decoded.storedCenterPortrait)
    }
}
