import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct FeedEffectsWireTests {
    @Test
    func assistScalarsMapDLog2HighlightToLiveTapCeiling() {
        let scalars = FeedEffectsWire.assistScalars(
            colorModeCode: Int(ColorMode.dLog2.rawValue),
            iso: 1600,
            highlightIRE: LiveZebra.highlightIRE,
            midtoneIRE: LiveZebra.midtoneIRE)
        #expect(scalars.count == FeedEffectsWire.assistScalarCount)
        let clip = Float(ScopeExposureCeiling.dlog2LiveTapByteAt1600) / 255
        #expect(abs(scalars[0] - clip) < 0.01)
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
        #expect(abs(scalars[0] - 1) < 0.02)
    }

    @Test
    func packedIreWeightIsOpaque() throws {
        let packed = try #require(
            FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: 1,
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
