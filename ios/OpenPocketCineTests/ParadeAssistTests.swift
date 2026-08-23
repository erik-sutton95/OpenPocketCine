import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

final class ParadeAssistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
    }

    func testOpenZCineOptionSet() {
        XCTAssertEqual(ParadeAssist.panelID, "parade")
        XCTAssertEqual(ParadeAssist.Mode.allCases.map(\.rawValue), ["RGB", "YRGB"])
        XCTAssertEqual(ParadeAssist.Mode.rgb.laneCount, 3)
        XCTAssertEqual(ParadeAssist.Mode.yrgb.laneCount, 4)
        XCTAssertEqual(ParadeAssist.laneLabels(.rgb), ["R", "G", "B"])
        XCTAssertEqual(ParadeAssist.laneLabels(.yrgb), ["Y", "R", "G", "B"])
        XCTAssertEqual(ParadeAssist.chip(.rgb), "RGB")
        XCTAssertEqual(ParadeAssist.chip(.yrgb), "YRGB")
        XCTAssertEqual(ParadeAssist.accessibilityLabel(.rgb), "RGB parade")
        XCTAssertEqual(ParadeAssist.accessibilityLabel(.yrgb), "YRGB parade")
        XCTAssertEqual(
            ParadeAssist.popupRows,
            ["Mode", "Brightness", "Safe Border Clip", "Safe Border Crush", "Middle Gray"])
        XCTAssertEqual(
            ParadeAssist.brightnessHelp,
            "Raise trace intensity when channel separation is hard to see.")
        XCTAssertEqual(ParadeAssist.Options.default.mode, .rgb)
        XCTAssertEqual(ParadeAssist.Options.default.brightness, 100)
        XCTAssertEqual(ParadeAssist.Options.default.scale, 1)
        XCTAssertTrue(ParadeAssist.Options.default.guides.clip)
        XCTAssertTrue(ParadeAssist.Options.default.guides.crush)
        XCTAssertTrue(ParadeAssist.Options.default.guides.middle)
        XCTAssertEqual(ParadeAssist.longPressPanelWidth, 400)
        XCTAssertEqual(ParadeAssist.scaleRange, 0.6...1.6)
        XCTAssertEqual(ParadeAssist.brightnessRange, 0...200)
        XCTAssertEqual(ParadeAssist.holdDuration, 0.3, accuracy: 0.001)
        XCTAssertEqual(ParadeAssist.baseSize, ScopePanelSize.parade)
    }

    func testScaleAndBrightnessClamp() {
        XCTAssertEqual(ParadeAssist.Options.clampedScale(0.2), 0.6)
        XCTAssertEqual(ParadeAssist.Options.clampedScale(2), 1.6)
        XCTAssertEqual(ParadeAssist.Options.clampedScale(1.1), 1.1)
        XCTAssertEqual(ParadeAssist.Options.clampedBrightness(-10), 0)
        XCTAssertEqual(ParadeAssist.Options.clampedBrightness(250), 200)
        XCTAssertEqual(ParadeAssist.panelSize(scale: 1), ScopePanelSize.parade)
        XCTAssertEqual(ParadeAssist.panelSize(scale: 2).width, (250 * 1.6).rounded())
        XCTAssertEqual(ParadeAssist.intensity(0), 0)
        XCTAssertEqual(ParadeAssist.intensity(100), 1)
        XCTAssertEqual(ParadeAssist.intensity(200), 2)
    }

    func testStoredCenterRoundTrip() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 200)
        let center = CGPoint(x: 90, y: 70)
        let stored = ParadeAssist.StoredCenter(center: center, in: bounds)
        XCTAssertEqual(stored.xFraction, 0.2, accuracy: 0.0001)
        XCTAssertEqual(stored.yFraction, 0.25, accuracy: 0.0001)
        let restored = stored.center(in: bounds)
        XCTAssertEqual(restored.x, center.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.001)
    }

    func testSnapClampAndHapticGrid() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        let size = CGSize(width: 100, height: 50)
        let snapped = ParadeAssist.snap(CGPoint(x: 11, y: 7))
        XCTAssertEqual(snapped.x, 12)
        XCTAssertEqual(snapped.y, 8)
        let clamped = ParadeAssist.clamp(CGPoint(x: -20, y: 400), size: size, bounds: bounds)
        XCTAssertEqual(clamped.x, 50)
        XCTAssertEqual(clamped.y, 175)
        XCTAssertEqual(
            ParadeAssist.hapticCell(CGPoint(x: 22, y: 44)),
            ParadeAssist.hapticCell(CGPoint(x: 23, y: 45)))
    }

    func testDefaultCenterIsTopTrailingInsideFullBleedFeed() {
        let layout = LiveMonitorLayout.fit(
            viewportWidth: 874,
            viewportHeight: 402,
            safeLeading: 59,
            safeTrailing: 0,
            showsBottomBars: true,
            mirrored: false
        )
        let size = ScopePanelSize.parade
        let canvas = CGRect(origin: .zero, size: layout.viewport)
        let center = ParadeAssist.defaultCenter(
            feed: layout.feed,
            size: size,
            bounds: canvas,
            chromeClearance: EdgeInsets(
                top: layout.topDeck.maxY, leading: 0, bottom: 0, trailing: 0)
        )
        XCTAssertEqual(center.x, layout.feed.maxX - size.width / 2, accuracy: 0.6)
        XCTAssertGreaterThan(center.y, layout.topDeck.maxY)
        XCTAssertLessThan(center.y, layout.feed.midY)
        XCTAssertGreaterThanOrEqual(center.x - size.width / 2, canvas.minX - 0.5)
        XCTAssertLessThanOrEqual(center.x + size.width / 2, canvas.maxX + 0.5)
    }

    func testResolvedCenterPrefersSessionThenStored() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let size = CGSize(width: 250, height: 153)
        // resolvedCenter clamps every source; the fallback must fit the panel
        // (half-size 125 × 76.5) to survive unchanged.
        let fallback = CGPoint(x: 150, y: 100)
        let stored = ParadeAssist.StoredCenter(center: CGPoint(x: 300, y: 120), in: bounds)
        let fromStored = ParadeAssist.resolvedCenter(
            session: nil, stored: stored, defaultCenter: fallback, size: size, bounds: bounds)
        XCTAssertEqual(fromStored.x, 300, accuracy: 0.5)
        let fromSession = ParadeAssist.resolvedCenter(
            session: CGPoint(x: 400, y: 200),
            stored: stored,
            defaultCenter: fallback,
            size: size,
            bounds: bounds)
        XCTAssertEqual(fromSession.x, 400, accuracy: 0.5)
        let fromDefault = ParadeAssist.resolvedCenter(
            session: nil, stored: nil, defaultCenter: fallback, size: size, bounds: bounds)
        XCTAssertEqual(fromDefault, fallback)
    }

    func testOptionsDecodeFillsOpenZCineDefaults() throws {
        let decoded = try JSONDecoder().decode(ParadeAssist.Options.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.mode, .rgb)
        XCTAssertEqual(decoded.brightness, 100)
        XCTAssertEqual(decoded.scale, 1)
        XCTAssertTrue(decoded.guides.clip)
        XCTAssertNil(decoded.storedCenter)
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
