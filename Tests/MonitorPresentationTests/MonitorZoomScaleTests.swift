import MonitorPresentation
import Testing

struct MonitorZoomScaleTests {
    @Test func proportionalTravelHasEqualSpacingAtEachDoubling() {
        let scale = MonitorZoomScale(minimum: 1, maximum: 12)
        #expect(abs((scale.position(4) - scale.position(2)) - scale.position(2)) < 0.000001)
        for value in [1.0, 1.5, 2, 3, 4, 6, 9, 12] {
            #expect(abs(scale.value(at: scale.position(value)) - value) < 0.000001)
        }
        #expect(scale.dragged(from: 3, angleDelta: 100) == 1)
        #expect(scale.dragged(from: 3, angleDelta: -100) == 12)
    }

    @Test func dialTicksAndLabelsUseHundredths() {
        let scale = MonitorZoomScale(minimum: 1, maximum: 12)
        #expect(scale.quantized(1.534) == 1.53)
        #expect(scale.quantized(1.536) == 1.54)
        #expect(scale.dialLabel(1.534) == "1.53×")
        #expect(scale.dialLabel(1) == "1.00×")
        #expect(scale.isLabeledTick(1.5))
        #expect(scale.isLabeledTick(1.50))
        #expect(!scale.isLabeledTick(1.53))
        let nearby = scale.dragged(from: 1.53, angleDelta: 0)
        #expect(nearby == 1.53)
        let ticks = MonitorZoomScale.minorTickPositions()
        #expect(ticks.count == 19)
        #expect(ticks.first == 0)
        #expect(ticks.last == 1)
        #expect(abs((ticks[1] - ticks[0]) - (ticks[2] - ticks[1])) < 1e-9)
        let step = scale.dragged(from: 1.00, angleDelta: -0.02)
        #expect(step > 1.00 && step < 1.10)
        #expect(abs(step / 0.01 - (step / 0.01).rounded()) < 1e-9)
    }

    @Test func slowRotationSnapsToWholeStopsAndFastRotationDoesNot() {
        let scale = MonitorZoomScale(minimum: 1, maximum: 12)
        #expect(scale.slowSnap(2.98, current: 2.97) == 3)
        #expect(scale.slowSnap(3.02, current: 3.00) == 3)
        #expect(abs(scale.slowSnap(3.08, current: 3.00) - 3.08) < 1e-9)
        #expect(scale.slowSnap(3.12, current: 3.00) == 3.12)
        #expect(abs(scale.slowSnap(1.52, current: 1.51) - 1.52) < 1e-9)
        #expect(scale.slowSnap(6.02, current: 6.00) == 6)
        let fast = scale.dragged(from: 2.5, angleDelta: -0.4, current: 2.5)
        #expect(abs(fast - 3) > 0.05)
    }

    @Test func singleStopAndInvalidGeometryStayFinite() {
        let single = MonitorZoomScale(minimum: 2, maximum: 1)
        #expect(single.value(at: 0.5) == 2)
        #expect(single.position(2) == 0)
        let invalid = MonitorZoomScale(minimum: .nan, maximum: .infinity)
        #expect(invalid.value(at: .nan) == 1)
        #expect(invalid.dragged(from: .nan, angleDelta: .nan) == 1)
    }
    @Test func aGeometryChangeCannotRestartTheOldZoomGesture() {
        var gesture = MonitorZoomDrag()
        let began = gesture.begin(at: 2)
        let beganAgain = gesture.begin(at: 2.5)
        #expect(began)
        #expect(!beganAgain)
        #expect(gesture.anchor == 2)
        let cancelled = gesture.cancel()
        let resumedOldPointer = gesture.begin(at: 3)
        #expect(cancelled)
        #expect(!resumedOldPointer)
        #expect(gesture.anchor == nil)
        let endedCancelled = gesture.end()
        #expect(!endedCancelled, "Cancellation already ended camera editing")
        let beganNewPointer = gesture.begin(at: 3)
        #expect(beganNewPointer, "A new pointer gets a fresh anchor")
        let ended = gesture.end()
        let endedAgain = gesture.end()
        #expect(ended)
        #expect(!endedAgain, "A recognizer reset cannot end the same transaction twice")
    }
}
