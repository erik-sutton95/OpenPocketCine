import MonitorPresentation
import Testing

struct MonitorDialHapticTests {
    @Test func coarseDrumsTickEveryNeighbor() {
        #expect(MonitorDialHaptic.shouldTick(previous: "172°", next: "180°", optionCount: 15))
        #expect(MonitorDialHaptic.shouldTick(previous: "144°", next: "172°", optionCount: 15))
        #expect(!MonitorDialHaptic.shouldTick(previous: "180°", next: "180°", optionCount: 15))
    }

    @Test func denseKelvinOnlyTicksRoundStops() {
        #expect(MonitorDialHaptic.shouldTick(previous: "5500K", next: "5600K", optionCount: 81))
        #expect(!MonitorDialHaptic.shouldTick(previous: "5500K", next: "5700K", optionCount: 81))
        #expect(MonitorDialHaptic.isMajor("3200K"))
        #expect(!MonitorDialHaptic.isMajor("3300K"))
    }

    @Test func zoomHundredthsStaySilentUntilAWholeStop() {
        let stops = MonitorZoomScale.wholeStops
        #expect(!MonitorDialHaptic.shouldTick(previous: 1.00, next: 1.01, majors: stops))
        #expect(MonitorDialHaptic.shouldTick(previous: 2.97, next: 3.00, majors: stops))
        #expect(MonitorDialHaptic.shouldTick(previous: 5.8, next: 6.1, majors: stops))
        #expect(MonitorDialHaptic.shouldTick(previous: 5.5, next: 6.0, majors: stops))
        #expect(!MonitorDialHaptic.shouldTick(previous: 5.0, next: 5.5, majors: stops))
        #expect(!MonitorDialHaptic.shouldTick(previous: 4.9, next: 5.0, majors: stops))
    }

    @Test func durationTicksWholeSecondsOnly() {
        #expect(MonitorDialHaptic.shouldTick(previous: 1.5, next: 2.0))
        #expect(!MonitorDialHaptic.shouldTick(previous: 1.0, next: 1.5))
        #expect(MonitorDialHaptic.shouldTick(previous: 4.5, next: 5.0))
    }

    @Test func continuousZoomTicksOnceWhenCrossingOrReachingAStop() {
        for values in [
            [2.994, 2.996, 3.001], [3.006, 3.004, 2.999],
            [2.996, 3.0, 3.004], [3.004, 3.0, 2.996],
        ] {
            let ticks = zip(values, values.dropFirst()).filter { previous, next in
                MonitorDialHaptic.shouldTick(previous: previous, next: next, majors: [3])
            }.count
            #expect(ticks == 1)
        }
    }

    @Test func denseShutterSpeedOnlyTicksRoundDenoms() {
        #expect(MonitorDialHaptic.shouldTick(previous: "1/49", next: "1/50", optionCount: 40))
        #expect(!MonitorDialHaptic.shouldTick(previous: "1/47", next: "1/49", optionCount: 40))
        #expect(MonitorDialHaptic.isMajor("1/48"))
        #expect(!MonitorDialHaptic.isMajor("1/47"))
    }
}
