import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct FeedEffectsWireTests {
    @Test
    func assistScalarsMapDLog2HighlightToTheClipShelf() {
        ScopeExposureCeiling.reset()
        let scalars = FeedEffectsWire.assistScalars(
            colorModeCode: Int(ColorMode.dLog2.rawValue),
            iso: 1600,
            highlightIRE: 100,
            midtoneIRE: LiveZebra.midtoneIRE)
        #expect(scalars.count == FeedEffectsWire.assistScalarCount)
        let shelf = Float(
            Int(ScopeExposureCeiling.dlog2LiveTapByteAt1600) - ScopeExposureCeiling.clipShelfCodes)
        #expect(abs(scalars[0] - shelf / 255) < 0.002, "zebra 100% fires on the clip shelf")
        #expect(scalars[3] == 1)
    }

    @Test
    func rec709PeakingGateIsSquaredDisplayGradient() {
        let scalars = FeedEffectsWire.assistScalars(
            colorModeCode: Int(ColorMode.normal.rawValue),
            iso: 100,
            highlightIRE: 100,
            midtoneIRE: 55)
        #expect(abs(Double(scalars[3]) - 1.57 * 1.57) < 1e-5)
        let shelf = Float(255 - ScopeExposureCeiling.clipShelfCodes) / 255
        #expect(abs(scalars[0] - shelf) < 0.002, "Rec.709 zebra 100% sits on the clip shelf")
    }

    @Test
    func packedCineStopPaintsEveryStopFlat() throws {
        ScopeExposureCeiling.reset()
        let packed = try #require(
            FeedEffectsWire.packedFalseColorPaint(
                scaleOrdinal: 3,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let size = FeedEffectsWire.falseColorCubeSize
        func neutral(_ i: Int) -> (Int, Int, Int) {
            let dst = (i * size * size + i * size + i) * 4
            return (Int(packed[dst]), Int(packed[dst + 1]), Int(packed[dst + 2]))
        }
        func index(stops: Double) -> Int {
            let encoded = LiveColorScience.encode(0.18 * pow(2, stops), transfer: .dlog2)
            return Int((encoded * Double(size - 1)).rounded())
        }
        let gray = neutral(index(stops: 0))
        #expect(abs(gray.0 - 127) < 6 && gray.0 == gray.1 && gray.1 == gray.2, "0 stops is gray")
        let upper = neutral(index(stops: 2))
        #expect(upper.0 > 240 && upper.1 > 220 && upper.2 < 120, "+2 is soft yellow")
        let shadows = neutral(index(stops: -4))
        #expect(abs(shadows.0 - 102) < 6 && shadows.0 == shadows.2, "−4 stops is flat dark gray")
        let highlights = neutral(index(stops: 5))
        #expect(abs(highlights.0 - 179) < 6, "+5 stops is flat light gray")
        let top = neutral(size - 1)
        #expect(top.0 > 200 && top.1 < 80 && top.2 < 40, "past the ceiling paints clip red")
    }

    @Test
    func packedCineStopPaintsTheWholeClipShelfFullyRed() throws {
        ScopeExposureCeiling.reset()
        let packed = try #require(
            FeedEffectsWire.packedFalseColorPaint(
                scaleOrdinal: 3,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let size = FeedEffectsWire.falseColorCubeSize
        func rgb(_ i: Int) -> (Int, Int, Int) {
            let dst = (i * size * size + i * size + i) * 4
            return (Int(packed[dst]), Int(packed[dst + 1]), Int(packed[dst + 2]))
        }
        // The GPU blends neighbouring lattice points: both points around the shelf byte
        // must already be clip red, or a blown window paints a pink blend.
        let shelf = Double(ScopeExposureCeiling.clipShelfByte(transfer: .dlog2))
        let below = Int((shelf / 255 * Double(size - 1)).rounded(.down))
        for i in [below, below + 1] {
            let (r, g, b) = rgb(i)
            #expect(r > 200 && g < 80 && b < 40, "lattice \(i) around the shelf is clip red")
        }
        let (r, g, _) = rgb(below - 1)
        #expect(abs(r - g) < 20, "one lattice step lower is still highlight gray")
    }

    @Test
    func packedLimitsPaintsTheWholeClipShelf() throws {
        ScopeExposureCeiling.reset()
        let code = Int(ColorMode.dLog2.rawValue)
        let paint = try #require(
            FeedEffectsWire.packedFalseColorPaint(scaleOrdinal: 2, colorModeCode: code, iso: 1600))
        let weight = try #require(
            FeedEffectsWire.packedFalseColorWeight(scaleOrdinal: 2, colorModeCode: code, iso: 1600))
        let size = FeedEffectsWire.falseColorCubeSize
        let shelf = Double(ScopeExposureCeiling.clipShelfByte(transfer: .dlog2))
        let below = Int((shelf / 255 * Double(size - 1)).rounded(.down))
        for i in [below, below + 1] {
            let dst = (i * size * size + i * size + i) * 4
            #expect(weight[dst] > 240, "lattice \(i) around the shelf is fully painted")
            #expect(
                paint[dst] > 180 && paint[dst + 1] < 90 && paint[dst + 2] < 70,
                "lattice \(i) is pure Limits clip red, not blended with the 94–98 band")
        }
    }

    @Test
    func packedIREOrdinalFiveReadsDLog2GreyThroughTheRec709Look() throws {
        ScopeExposureCeiling.reset()
        #expect(FeedEffectsWire.falseColorScale(5) == .ire)
        #expect(FeedEffectsWire.readsRec709Look(5) && !FeedEffectsWire.readsRec709Look(1))
        let size = FeedEffectsWire.falseColorCubeSize
        let i = Int((MonitorTransfer.dlog2.middleGrayEncoded * Double(size - 1)).rounded())
        func grey(_ ordinal: Int) throws -> (Int, Int, Int) {
            let packed = try #require(
                FeedEffectsWire.packedFalseColorPaint(
                    scaleOrdinal: ordinal, colorModeCode: Int(ColorMode.dLog2.rawValue),
                    iso: 1600))
            let dst = (i * size * size + i * size + i) * 4
            return (Int(packed[dst]), Int(packed[dst + 1]), Int(packed[dst + 2]))
        }
        let look = try grey(5)
        #expect(look.1 > look.0 + 40 && look.1 > look.2 + 40, "709: D-Log2 18% is 18%MG green")
        let log = try grey(1)
        #expect(abs(log.0 - log.1) < 12 && abs(log.1 - log.2) < 12, "LOG: D-Log2 18% is a gap")
    }

    @Test(arguments: [(0, LiveFalseColorScale.stops), (1, .ire), (3, .sceneStops)])
    func packedOpaqueWeightFillsTheCube(ordinal: Int, scale: LiveFalseColorScale) throws {
        #expect(FeedEffectsWire.falseColorScale(ordinal) == scale)
        let packed = try #require(
            FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: ordinal,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let size = FeedEffectsWire.falseColorCubeSize
        #expect(packed.count == size * size * size * 4)
        #expect(packed[0] == 255)
        #expect(packed[4] == 255)
        #expect(packed[packed.count - 4] == 255)
    }

    @Test
    func packedLimitsWeightHasHoles() throws {
        let packed = try #require(
            FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: 2,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let opaque = packed.enumerated().filter { $0.offset % 4 == 0 }.filter { $0.element == 255 }
            .count
        let clear = packed.enumerated().filter { $0.offset % 4 == 0 }.filter { $0.element == 0 }
            .count
        #expect(opaque > 0)
        #expect(clear > 0)
    }
}
