import MonitorPresentation
import Testing

struct MonitorZoomScaleTests {
    @Test func continuousDragPreservesSubHundredthMotionAcrossWholeStops() {
        let scale = MonitorZoomScale(minimum: 1, maximum: 12)
        for target in [1.531, 1.534, 2.981, 2.999, 3.001, 3.019] {
            let origin = target - 0.001
            let delta =
                (scale.position(origin) - scale.position(target)) * MonitorZoomScale.angularSpan
            let actual = scale.dragged(from: origin, angleDelta: delta, current: origin)
            #expect(
                abs(actual - target) < 1e-12,
                "Continuous pointer target \(target) was changed to \(actual)")
        }
    }

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
        #expect(abs(nearby - 1.53) < 1e-12)
        let ticks = MonitorZoomScale.minorTickPositions()
        #expect(ticks.count == 19)
        #expect(ticks.first == 0)
        #expect(ticks.last == 1)
        #expect(abs((ticks[1] - ticks[0]) - (ticks[2] - ticks[1])) < 1e-9)
        let step = scale.dragged(from: 1.00, angleDelta: -0.02)
        #expect(step > 1.00 && step < 1.10)
        #expect(abs(step / 0.01 - (step / 0.01).rounded()) > 0.001)
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
