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
