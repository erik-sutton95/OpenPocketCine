import Testing

@testable import OpenPocketViewCore

@Suite struct DeliveryCadenceTests {
    @Test func firstBurstDoesNotHideInitialSilence() {
        var meter = DeliveryCadence(startedAt: 0)
        for tick in 36...40 { meter.note(at: Double(tick) / 40) }
        let window = meter.takeWindow(at: 1)!
        #expect(window.events == 5)
        #expect(abs(window.maximumGapMilliseconds - 900) < 0.001)
    }

    @Test func ackRateAndDelayedWindowUseActualElapsedTime() {
        var meter = DeliveryCadence(startedAt: 0)
        for tick in 1...40 { meter.note(at: Double(tick) / 40) }
        let first = meter.takeWindow(at: 1)!
        #expect(first.events == 40)
        #expect(first.hertz == 40)
        #expect(abs(first.maximumGapMilliseconds - 25) < 0.001)
        meter.note(at: 1.25)
        let delayed = meter.takeWindow(at: 2)!
        #expect(delayed.events == 1)
        #expect(delayed.maximumGapMilliseconds == 750)
        let silent = meter.takeWindow(at: 3)!
        #expect(silent.hertz == 0)
        #expect(silent.maximumGapMilliseconds == 1_750)
    }

    @Test func boundaryDoesNotHideHitchAndBadClockDoesNotPoisonCounters() {
        var meter = DeliveryCadence(startedAt: 0)
        meter.note(at: 0.8)
        _ = meter.takeWindow(at: 1)
        meter.note(at: 1.3)
        meter.note(at: 1.2)
        meter.note(at: .nan)
        #expect(meter.takeWindow(at: 1) == nil)
        #expect(meter.takeWindow(at: .infinity) == nil)
        let window = meter.takeWindow(at: 1.4)!
        #expect(window.events == 1)
        #expect(abs(window.maximumGapMilliseconds - 500) < 0.001)
    }
}
