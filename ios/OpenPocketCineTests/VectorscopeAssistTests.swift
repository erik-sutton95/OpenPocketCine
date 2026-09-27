import XCTest

@testable import OpenPocketCine

final class VectorscopeAssistTests: XCTestCase {
    func testRetiredSourceSelectionKeyIsIgnored() throws {
        let legacy = Data(
            #"{"vectorscopeSource":"Monitor","zoom":"4x","brightness":137}"#.utf8)
        let options = try JSONDecoder().decode(VectorscopeAssist.Options.self, from: legacy)
        XCTAssertEqual(options.zoom, .x4)
        XCTAssertEqual(options.brightness, 137)
    }

    func testNeutralsCarryNoChroma() {
        for value: UInt8 in [0, 18, 128, 255] {
            let chroma = ScopeChroma.rec709(red: value, green: value, blue: value)
            XCTAssertEqual(chroma.cb, 0, accuracy: 1e-9)
            XCTAssertEqual(chroma.cr, 0, accuracy: 1e-9)
        }
    }

    func testPrimariesLandAtBT709Positions() {
        let red = ScopeChroma.rec709(red: UInt8(255), green: 0, blue: 0)
        XCTAssertEqual(red.cr, 0.5, accuracy: 1e-9)
        XCTAssertEqual(red.cb, -0.2126 / 1.8556, accuracy: 1e-9)
        let blue = ScopeChroma.rec709(red: UInt8(0), green: 0, blue: 255)
        XCTAssertEqual(blue.cb, 0.5, accuracy: 1e-9)
        XCTAssertEqual(blue.cr, -0.0722 / 1.5748, accuracy: 1e-9)
        let yellow = ScopeChroma.rec709(red: UInt8(255), green: 255, blue: 0)
        XCTAssertEqual(yellow.cb, -0.5, accuracy: 1e-9)
    }

    func testSmpte75PercentBarsLandAtIndependentRec709Targets() {
        let bars: [(rgb: (UInt8, UInt8, UInt8), cb: Double, cr: Double)] = [
            ((191, 191, 0), -0.374_509_804, 0.034_340_371),
            ((0, 191, 191), 0.085_816_754, -0.374_509_804),
            ((0, 191, 0), -0.288_693_050, -0.340_169_433),
            ((191, 0, 191), 0.288_693_050, 0.340_169_433),
            ((191, 0, 0), -0.085_816_754, 0.374_509_804),
            ((0, 0, 191), 0.374_509_804, -0.034_340_371),
        ]
        for bar in bars {
            let actual = ScopeChroma.rec709(red: bar.rgb.0, green: bar.rgb.1, blue: bar.rgb.2)
            XCTAssertEqual(actual.cb, bar.cb, accuracy: 0.000_000_001)
            XCTAssertEqual(actual.cr, bar.cr, accuracy: 0.000_000_001)
        }
    }

    func testSmpte75PercentBarsHitOpenZCine128BinCoordinates() throws {
        let bars: [(rgb: (UInt8, UInt8, UInt8), column: Int, row: Int)] = [
            ((191, 0, 0), 53, 111),
            ((191, 0, 191), 100, 107),
            ((0, 0, 191), 111, 59),
            ((0, 191, 191), 74, 16),
            ((0, 191, 0), 27, 20),
            ((191, 191, 0), 16, 68),
        ]
        for bar in bars {
            let bin = try XCTUnwrap(
                VectorscopeRaster.binIndex(red: bar.rgb.0, green: bar.rgb.1, blue: bar.rgb.2))
            XCTAssertEqual(bin.column, bar.column)
            XCTAssertEqual(bin.row, bar.row)
        }
    }

    func testNeutralPixelsPileIntoTheCentreBin() throws {
        let bin = try XCTUnwrap(
            VectorscopeRaster.binIndex(red: 128, green: 128, blue: 128))
        XCTAssertEqual(bin.column, 64)
        XCTAssertEqual(bin.row, 64)
    }

    func testGainMagnifiesTheTraceAndClipsOvershoot() throws {
        let unity = try XCTUnwrap(
            VectorscopeRaster.binIndex(red: 140, green: 128, blue: 128, gain: 1))
        let zoomed = try XCTUnwrap(
            VectorscopeRaster.binIndex(red: 140, green: 128, blue: 128, gain: 2))
        let unityOffset = Double(unity.column) - 63.5
        let zoomedOffset = Double(zoomed.column) - 63.5
        XCTAssertEqual(zoomedOffset, 2 * unityOffset, accuracy: 1.5)
        XCTAssertNil(VectorscopeRaster.binIndex(red: 255, green: 0, blue: 0, gain: 2))
    }

    func testTraceZoomExpandsChromaBins() throws {
        let point = ScopePoint(
            xRatio: 0.5, yRatio: 0.5, red: 160, green: 80, blue: 80, luma: 100)
        let unity = try XCTUnwrap(VectorscopeRaster.pixels(from: [point], gain: 1, intensity: 1))
        let zoomed = try XCTUnwrap(VectorscopeRaster.pixels(from: [point], gain: 2, intensity: 1))
        let n = VectorscopeRaster.bins
        func peakOffset(_ pixels: [UInt8]) -> (x: Int, y: Int) {
            var best = 0
            var bestAlpha: UInt8 = 0
            for i in 0..<(n * n) where pixels[i * 4 + 3] > bestAlpha {
                bestAlpha = pixels[i * 4 + 3]
                best = i
            }
            return (best % n, best / n)
        }
        let a = peakOffset(unity)
        let b = peakOffset(zoomed)
        let mid = n / 2
        let unityRadius = hypot(Double(a.x - mid), Double(a.y - mid))
        let zoomedRadius = hypot(Double(b.x - mid), Double(b.y - mid))
        XCTAssertGreaterThan(zoomedRadius, unityRadius * 1.4)
    }

    func testNeutralBinUsesWhiteTraceTint() throws {
        let tint = ScopeChroma.traceTint(red: 32 / 255, green: 32 / 255, blue: 32 / 255)
        XCTAssertEqual(tint.red, 1, accuracy: 1e-9)
        XCTAssertEqual(tint.green, 1, accuracy: 1e-9)
        XCTAssertEqual(tint.blue, 1, accuracy: 1e-9)
        let grey = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 32, green: 32, blue: 32, luma: 32)
        let pixels = try XCTUnwrap(VectorscopeRaster.pixels(from: [grey], gain: 1, intensity: 1))
        let n = VectorscopeRaster.bins
        var found = false
        for i in 0..<(n * n) where pixels[i * 4 + 3] > 0 {
            XCTAssertEqual(pixels[i * 4], pixels[i * 4 + 3])
            XCTAssertEqual(pixels[i * 4 + 1], pixels[i * 4 + 3])
            XCTAssertEqual(pixels[i * 4 + 2], pixels[i * 4 + 3])
            found = true
        }
        XCTAssertTrue(found)
    }

    func testSaturatedRedKeepsHueInTraceTint() {
        let tint = ScopeChroma.traceTint(red: 1, green: 0, blue: 0)
        XCTAssertEqual(tint.red, 1, accuracy: 1e-9)
        XCTAssertEqual(tint.green, 0, accuracy: 1e-9)
        XCTAssertEqual(tint.blue, 0, accuracy: 1e-9)
    }

    func testBrightnessScalesDensityAlpha() throws {
        let red = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 191, green: 0, blue: 0, luma: 40)
        let full = try XCTUnwrap(VectorscopeRaster.pixels(from: [red], gain: 1, intensity: 1))
        let half = try XCTUnwrap(VectorscopeRaster.pixels(from: [red], gain: 1, intensity: 0.5))
        func peakAlpha(_ pixels: [UInt8]) -> UInt8 {
            var best: UInt8 = 0
            for i in 0..<(VectorscopeRaster.bins * VectorscopeRaster.bins) {
                best = max(best, pixels[i * 4 + 3])
            }
            return best
        }
        XCTAssertEqual(peakAlpha(full), 255)
        XCTAssertEqual(Double(peakAlpha(half)), 127, accuracy: 1)
    }

    func testSkinLineIsIPhaseAt123Degrees() {
        XCTAssertEqual(VectorscopeGraticule.skinAngleDegrees, 123, accuracy: 0.001)
        XCTAssertEqual(VectorscopeGraticule.skinLength, 0.92, accuracy: 0.001)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let end = VectorscopeGraticule.skinEnd(in: rect)
        let angle = 123.0 * Double.pi / 180
        XCTAssertEqual(end.x, 100 + CGFloat(cos(angle)) * 100 * 0.92, accuracy: 0.01)
        XCTAssertEqual(end.y, 100 - CGFloat(sin(angle)) * 100 * 0.92, accuracy: 0.01)
    }

    func testGraticuleTargetsUse75PercentBoxes() {
        XCTAssertEqual(
            VectorscopeGraticule.targets.map(\.label), ["R", "Mg", "B", "Cy", "G", "Yl"])
        XCTAssertEqual(VectorscopeGraticule.boxSide, 7)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let red = VectorscopeGraticule.targetCenter(red: 191, green: 0, blue: 0, in: rect)
        let chroma = ScopeChroma.rec709(red: UInt8(191), green: 0, blue: 0)
        XCTAssertEqual(red.x, 100 + CGFloat(chroma.cb) * 200, accuracy: 0.01)
        XCTAssertEqual(red.y, 100 - CGFloat(chroma.cr) * 200, accuracy: 0.01)
    }

    func testPlotSquareCentresInsideScopePlotRect() {
        let size = CGSize(width: 190, height: 190)
        let plot = scopePlotRect(size, top: 26)
        let square = vectorscopePlotSquare(in: size)
        XCTAssertEqual(square.width, square.height, accuracy: 0.01)
        XCTAssertEqual(square.midX, plot.midX, accuracy: 0.01)
        XCTAssertEqual(square.midY, plot.midY, accuracy: 0.01)
        XCTAssertEqual(square.width, min(plot.width, plot.height), accuracy: 0.01)
    }
}
