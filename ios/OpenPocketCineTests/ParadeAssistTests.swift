import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

final class ParadeAssistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
    }

    func testLaneXMatchesOpenZCineSplit() {
        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        XCTAssertEqual(
            ParadeAssist.laneWidth(mode: .rgb, plot: plot), plot.width / 3, accuracy: 0.001)
        XCTAssertEqual(
            ParadeAssist.laneWidth(mode: .yrgb, plot: plot), plot.width / 4, accuracy: 0.001)
        // OpenZCine: originX + xRatio * (laneWidth - 1)
        XCTAssertEqual(
            ParadeAssist.laneX(xRatio: 0, lane: 0, mode: .rgb, plot: plot),
            plot.minX, accuracy: 0.001)
        XCTAssertEqual(
            ParadeAssist.laneX(xRatio: 1, lane: 2, mode: .rgb, plot: plot),
            plot.minX + 2 * (plot.width / 3) + (plot.width / 3 - 1),
            accuracy: 0.001)
        XCTAssertEqual(
            ParadeAssist.laneX(xRatio: 0.5, lane: 0, mode: .yrgb, plot: plot),
            plot.minX + 0.5 * (plot.width / 4 - 1),
            accuracy: 0.001)
    }

    func testParadeYUsesWaveGeometryWithNoShelf() {
        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        let table = WaveformAxis.levelTable(for: .dlog2)
        let black = WaveformAxis.legalBlackByte(transfer: .dlog2)
        let grey = UInt8((LiveColorScience.encode(0.18, transfer: .dlog2) * 255).rounded())
        let bytes: [UInt8] = [black, grey, 247]
        let points = bytes.map {
            ScopePoint(xRatio: 0.25, yRatio: 0.5, red: $0, green: $0, blue: $0, luma: $0)
        }
        let rgbCapacity = ScopeTraceMetal.maxVertexCount(points: points.count, mode: .parade(.rgb))
        let yrgbCapacity = ScopeTraceMetal.maxVertexCount(
            points: points.count, mode: .parade(.yrgb))
        XCTAssertEqual(rgbCapacity, points.count * 3)
        XCTAssertEqual(yrgbCapacity, points.count * 4)

        var rgb = [ScopeTraceMetal.Vertex](
            repeating: ScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
            count: rgbCapacity)
        let rgbWritten = rgb.withUnsafeMutableBufferPointer { out in
            ScopeTraceMetal.fillVertices(
                out, from: 0, points: points, mode: .parade(.rgb), rect: plot,
                opacity: 1, levelTable: table)
        }
        XCTAssertEqual(rgbWritten, points.count * 3)

        let line0 = WaveformAxis.scaleLineY(0, plot)
        let lineGray = WaveformAxis.scaleLineY(
            WaveformAxis.middleGrayIRE(transfer: .dlog2), plot)
        let line100 = WaveformAxis.scaleLineY(100, plot)
        XCTAssertEqual(Double(rgb[0].position.y) + 0.5, Double(line0), accuracy: 0.1)
        XCTAssertEqual(Double(rgb[1].position.y) + 0.5, Double(lineGray), accuracy: 0.5)
        XCTAssertEqual(Double(rgb[2].position.y) + 0.5, Double(line100), accuracy: 0.1)

        for (index, point) in points.enumerated() {
            let expectedY = WaveformAxis.vertexPositionY(
                ire: Double(table[Int(point.red)]), pointSize: 1, rect: plot)
            for lane in 0..<3 {
                XCTAssertEqual(
                    Double(rgb[index + lane * points.count].position.y), Double(expectedY),
                    accuracy: 0.01,
                    "RGB lane \(lane) rides the WAVE IRE axis")
            }
            XCTAssertEqual(
                Double(rgb[index].position.x),
                Double(ParadeAssist.laneX(xRatio: point.xRatio, lane: 0, mode: .rgb, plot: plot)),
                accuracy: 0.01)
        }

        var yrgb = [ScopeTraceMetal.Vertex](
            repeating: ScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
            count: yrgbCapacity)
        let yrgbWritten = yrgb.withUnsafeMutableBufferPointer { out in
            ScopeTraceMetal.fillVertices(
                out, from: 0, points: points, mode: .parade(.yrgb), rect: plot,
                opacity: 1, levelTable: table)
        }
        XCTAssertEqual(yrgbWritten, points.count * 4)
        for (index, point) in points.enumerated() {
            let expectedY = WaveformAxis.vertexPositionY(
                ire: Double(table[Int(point.luma)]), pointSize: 1, rect: plot)
            XCTAssertEqual(
                Double(yrgb[index].position.y), Double(expectedY),
                accuracy: 0.01,
                "YRGB luma lane rides the WAVE IRE axis")
            XCTAssertEqual(
                Double(yrgb[index].position.x),
                Double(ParadeAssist.laneX(xRatio: point.xRatio, lane: 0, mode: .yrgb, plot: plot)),
                accuracy: 0.01)
        }
    }
}
