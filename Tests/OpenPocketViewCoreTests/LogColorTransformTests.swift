import Testing

@testable import OpenPocketViewCore

@Suite struct LogColorTransformTests {
    @Test func convertsOnlyDLogAndDLog2() {
        #expect(LogColorTransform.converting(from: .dLog) == .dLogToDLog2)
        #expect(LogColorTransform.converting(from: .dLog2) == .dLog2ToDLog)
        #expect(LogColorTransform.converting(from: .dLogM) == nil)
        #expect(LogColorTransform.converting(from: .normal) == nil)
        #expect(LogColorTransform.converting(from: .normal10) == nil)
        #expect(LogColorTransform.converting(from: .hdr) == nil)
    }

    @Test func labelsAndFilenameTokensNameTheDestinationLog() {
        #expect(LogColorTransform.dLogToDLog2.label == "D-Log → D-Log2")
        #expect(LogColorTransform.dLogToDLog2.filenameToken == "dlog2")
        #expect(LogColorTransform.dLog2ToDLog.label == "D-Log2 → D-Log")
        #expect(LogColorTransform.dLog2ToDLog.filenameToken == "dlog")
        #expect(LogColorTransform.dLogToDLog2.source == .dlog)
        #expect(LogColorTransform.dLogToDLog2.destination == .dlog2)
        #expect(LogColorTransform.dLog2ToDLog.source == .dlog2)
        #expect(LogColorTransform.dLog2ToDLog.destination == .dlog)
    }

    @Test func eighteenPercentGreyLandsOnTheDestinationPaperCode() {
        let dlogGrey = LiveColorScience.encode(0.18, transfer: .dlog)
        let dlog2Grey = LiveColorScience.encode(0.18, transfer: .dlog2)
        let toDLog2 = LogColorTransform.dLogToDLog2.apply(r: dlogGrey, g: dlogGrey, b: dlogGrey)
        #expect(abs(toDLog2.r - dlog2Grey) < 1e-3)
        #expect(abs(toDLog2.g - dlog2Grey) < 1e-3)
        #expect(abs(toDLog2.b - dlog2Grey) < 1e-3)
        let toDLog = LogColorTransform.dLog2ToDLog.apply(r: dlog2Grey, g: dlog2Grey, b: dlog2Grey)
        #expect(abs(toDLog.r - dlogGrey) < 1e-3)
        #expect(abs(toDLog.g - dlogGrey) < 1e-3)
        #expect(abs(toDLog.b - dlogGrey) < 1e-3)
    }

    @Test func blackMapsToDestinationPaperBlack() {
        let dlog2Black = LiveColorScience.encode(0, transfer: .dlog2)
        let dlogBlack = LiveColorScience.encode(0, transfer: .dlog)
        let toDLog2 = LogColorTransform.dLogToDLog2.apply(r: 0, g: 0, b: 0)
        #expect(abs(toDLog2.r - dlog2Black) < 1e-3)
        let toDLog = LogColorTransform.dLog2ToDLog.apply(r: 0, g: 0, b: 0)
        #expect(abs(toDLog.r - dlogBlack) < 1e-3)
    }

    @Test func aStopAboveGreyStaysAStopAboveGrey() {
        let linear = 0.18 * 2
        let src = LiveColorScience.encode(linear, transfer: .dlog)
        let dest = LiveColorScience.encode(linear, transfer: .dlog2)
        let mapped = LogColorTransform.dLogToDLog2.apply(r: src, g: src, b: src)
        #expect(abs(mapped.r - dest) < 2e-3)
    }

    @Test func equalRgbStaysGreyThroughTheGamut() {
        let src = LiveColorScience.encode(0.18, transfer: .dlog)
        let mapped = LogColorTransform.dLogToDLog2.apply(r: src, g: src, b: src)
        #expect(abs(mapped.r - mapped.g) < 1e-4)
        #expect(abs(mapped.g - mapped.b) < 1e-4)
    }

    @Test func dLog2AboveDLogPeakClipsAtEncodedOne() {
        let hot = LiveColorScience.encode(DLogPeak.linear, transfer: .dlog2)
        let hotter = LiveColorScience.encode(min(DLogPeak.linear * 4, 475), transfer: .dlog2)
        let atPeak = LogColorTransform.dLog2ToDLog.apply(r: hot, g: hot, b: hot)
        #expect(abs(atPeak.r - 1) < 2e-3)
        let clipped = LogColorTransform.dLog2ToDLog.apply(r: hotter, g: hotter, b: hotter)
        #expect(clipped.r == 1)
        #expect(clipped.g == 1)
        #expect(clipped.b == 1)
    }

    @Test func cubeLatticeMatchesApply() {
        let transform = LogColorTransform.dLogToDLog2
        let cube = transform.cube(size: 5)
        #expect(cube.size == 5)
        let denom = Float(4)
        for b in 0..<5 {
            for g in 0..<5 {
                for r in 0..<5 {
                    let rf = Double(Float(r) / denom)
                    let gf = Double(Float(g) / denom)
                    let bf = Double(Float(b) / denom)
                    let applied = transform.apply(r: rf, g: gf, b: bf)
                    let sampled = cube.map(red: Float(rf), green: Float(gf), blue: Float(bf))
                    #expect(abs(Double(sampled.red) - applied.r) < 1e-5)
                    #expect(abs(Double(sampled.green) - applied.g) < 1e-5)
                    #expect(abs(Double(sampled.blue) - applied.b) < 1e-5)
                }
            }
        }
    }

    @Test func defaultCubeFitsCIColorCube() {
        let cube = LogColorTransform.dLogToDLog2.cube()
        #expect(cube.size == CubeLUT.colorCubeMaxDimension)
        #expect(cube.rgb.count == cube.size * cube.size * cube.size * 3)
    }
}

/// D-Log paper peak (4200% = 42 linear). Kept here so the clip test names the
/// contract without reaching into fileprivate `DLog`.
private enum DLogPeak {
    static let linear = 42.0
}
