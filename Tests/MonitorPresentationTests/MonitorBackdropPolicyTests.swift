import MonitorPresentation
import Testing

struct MonitorBackdropPolicyTests {
    @Test func displayLockedCadenceStaysInsideOneFrameAtSixtyHertz() {
        #expect(MonitorBackdropPolicy.minimumIntervalNanoseconds == 16_666_667)
        #expect(abs(MonitorBackdropPolicy.minimumInterval - 1.0 / 60.0) < 0.000_001)
        #expect(MonitorBackdropPolicy.maximumDimension == 320)
    }
}
