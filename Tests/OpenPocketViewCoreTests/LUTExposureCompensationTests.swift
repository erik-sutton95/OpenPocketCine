import Testing

@testable import OpenPocketViewCore

/// LUT exposure math moved to OpenCineMedia. The DJI integration keeps its curve choice.
@Suite struct LUTExposureCompensationTests {
    @Test func dLogMScopeEstimateDoesNotChangeExistingBakedExposure() {
        for byte in 0...255 {
            for stops in [-2.0, 0, 2.0] {
                let signal = Double(byte) / 255
                #expect(
                    LUTExposureCompensation.compensateEncoded(
                        signal, stops: stops, transfer: MonitorTransfer.dlogm.lutExposureTransfer)
                        == LUTExposureCompensation.compensateEncoded(
                            signal, stops: stops, transfer: .dlog))
            }
        }
    }
}
