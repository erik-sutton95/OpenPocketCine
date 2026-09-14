import MonitorPresentation
import Testing

struct MonitorBackdropPolicyTests {
    @Test func displayLockedCadenceStaysInsideOneFrameAtSixtyHertz() {
        #expect(MonitorBackdropPolicy.minimumIntervalNanoseconds == 16_666_667)
        #expect(abs(MonitorBackdropPolicy.minimumInterval - 1.0 / 60.0) < 0.000_001)
        #expect(MonitorBackdropPolicy.maximumDimension == 320)
    }

    @Test func thermalBackoffKeepsTheSameMultipliers() {
        #expect(
            MonitorBackdropPolicy.intervalNanoseconds(serious: false, critical: false)
                == MonitorBackdropPolicy.minimumIntervalNanoseconds)
        #expect(
            MonitorBackdropPolicy.intervalNanoseconds(serious: true, critical: false)
                == MonitorBackdropPolicy.minimumIntervalNanoseconds * 3)
        #expect(
            MonitorBackdropPolicy.intervalNanoseconds(serious: true, critical: true)
                == MonitorBackdropPolicy.minimumIntervalNanoseconds * 5)
        #expect(MonitorBackdropPolicy.interval(serious: false, critical: false) == 1.0 / 60.0)
        #expect(MonitorBackdropPolicy.interval(serious: true, critical: false) == 3.0 / 60.0)
        #expect(MonitorBackdropPolicy.interval(serious: false, critical: true) == 5.0 / 60.0)
    }
}
