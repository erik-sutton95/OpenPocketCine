import MonitorPresentation
import Testing

struct MonitorDialHapticTests {
    /// Coarse drums (15 options) tick every neighbor; dense Kelvin (81) and
    /// shutter speed (40) drums only tick round stops.
    @Test(arguments: [
        ("172°", "180°", 15, true), ("144°", "172°", 15, true), ("180°", "180°", 15, false),
        ("5500K", "5600K", 81, true), ("5500K", "5700K", 81, false),
        ("1/49", "1/50", 40, true), ("1/47", "1/49", 40, false),
    ])
    func labeledDrumTicks(previous: String, next: String, optionCount: Int, ticks: Bool) {
        #expect(
            MonitorDialHaptic.shouldTick(previous: previous, next: next, optionCount: optionCount)
                == ticks)
    }

    @Test(arguments: [("3200K", true), ("3300K", false), ("1/48", true), ("1/47", false)])
    func denseDrumMajors(label: String, major: Bool) {
        #expect(MonitorDialHaptic.isMajor(label) == major)
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
}
