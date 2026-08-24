import Testing

@testable import OpenPocketViewCore

@Suite struct LUTExposureCompensationTests {
    @Test func snapsHalfStopsAndClamps() {
        #expect(LUTExposureCompensation.snap(0) == 0)
        #expect(LUTExposureCompensation.snap(0.24) == 0)
        #expect(LUTExposureCompensation.snap(0.26) == 0.5)
        #expect(LUTExposureCompensation.snap(1.2) == 1.0)
        #expect(LUTExposureCompensation.snap(-1.24) == -1.0)
        #expect(LUTExposureCompensation.snap(-1.26) == -1.5)
        #expect(LUTExposureCompensation.snap(3.4) == 3)
        #expect(LUTExposureCompensation.snap(-4) == -3)
        #expect(LUTExposureCompensation.snap(.nan) == 0)
    }

    @Test func ticksAreThirteenHalfStops() {
        #expect(
            LUTExposureCompensation.stops == [
                -3, -2.5, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 3,
            ])
    }

    @Test func labelsUseSignedHalfStops() {
        #expect(LUTExposureCompensation.label(0) == "0.0")
        #expect(LUTExposureCompensation.label(0.5) == "+0.5")
        #expect(LUTExposureCompensation.label(2) == "+2.0")
        #expect(LUTExposureCompensation.label(-1.5) == "−1.5")
        #expect(LUTExposureCompensation.label(-3) == "−3.0")
    }

    @Test func stepperStopsAtTheRails() {
        #expect(!LUTExposureCompensation.canStep(-3, by: -0.5))
        #expect(LUTExposureCompensation.canStep(-3, by: 0.5))
        #expect(!LUTExposureCompensation.canStep(3, by: 0.5))
        #expect(LUTExposureCompensation.stepped(1.0, by: -0.5) == 0.5)
        #expect(LUTExposureCompensation.stepped(3, by: 0.5) == 3)
    }

    @Test func pullMapsAHotLogCodeBackTowardMidGrey() {
        let transfer = MonitorTransfer.dlog2
        let mid = transfer.middleGrayEncoded
        let hot = LUTExposureCompensation.compensateEncoded(mid, stops: 1, transfer: transfer)
        #expect(hot > mid)
        let pulled = LUTExposureCompensation.compensateEncoded(hot, stops: -1, transfer: transfer)
        #expect(abs(pulled - mid) < 0.002)
    }

    @Test func identityCubePullsInputBeforeTheLook() {
        let identity = Self.identityCube(size: 17)
        #expect(identity.compensatingExposure(stops: 0, transfer: .dlog2) == identity)
        let pulled = identity.compensatingExposure(stops: -1, transfer: .dlog2)
        let transfer = MonitorTransfer.dlog2
        let mid = transfer.middleGrayEncoded
        let expected = LUTExposureCompensation.compensateEncoded(mid, stops: -1, transfer: transfer)
        let out = pulled.map(red: Float(mid), green: Float(mid), blue: Float(mid))
        #expect(abs(Double(out.red) - expected) < 0.03)
        #expect(abs(Double(out.green) - expected) < 0.03)

        let hot = LUTExposureCompensation.compensateEncoded(mid, stops: 1, transfer: transfer)
        let restored = pulled.map(red: Float(hot), green: Float(hot), blue: Float(hot))
        #expect(abs(Double(restored.red) - mid) < 0.04)
    }

    @Test func exportCubeBakesExposureOnlyWhenAsked() {
        let identity = Self.identityCube(size: 9)
        let pulled = identity.compensatingExposure(stops: -1, transfer: .dlog2)
        #expect(
            identity.preparedForExport(bakeExposure: false, stops: -1, transfer: .dlog2)
                == identity.colorCube)
        #expect(
            identity.preparedForExport(bakeExposure: true, stops: -1, transfer: .dlog2)
                == pulled)
        #expect(
            identity.preparedForExport(bakeExposure: true, stops: 0, transfer: .dlog2)
                == identity.colorCube)
    }

    private static func identityCube(size: Int) -> CubeLUT {
        let denom = Float(size - 1)
        var rgb = [Float]()
        rgb.reserveCapacity(size * size * size * 3)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    rgb.append(Float(r) / denom)
                    rgb.append(Float(g) / denom)
                    rgb.append(Float(b) / denom)
                }
            }
        }
        return CubeLUT(size: size, rgb: rgb)
    }
}
