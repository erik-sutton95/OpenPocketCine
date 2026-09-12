import MonitorPresentation
import Testing

struct MonitorReadoutInteractionTests {
    @Test func plainTapProducesOnePersistentPickerIntent() {
        var gesture = MonitorReadoutInteraction()
        gesture.begin()
        gesture.move(x: 3, y: 4)
        let tap = gesture.end()
        #expect(tap == .tap)
        let repeatedEnd = gesture.end()
        #expect(repeatedEnd == .cancelled)
    }

    @Test func horizontalActivationRebasesBefore56PointValueMovement() {
        var gesture = MonitorReadoutInteraction()
        gesture.begin()
        let threshold = gesture.move(x: -14, y: 0)
        #expect(!threshold)
        let opened = gesture.move(x: -15, y: 0)
        #expect(opened)
        #expect(gesture.translation == 0)
        let repeatedHold = gesture.hold()
        #expect(!repeatedHold)
        gesture.move(x: -71, y: 0)
        let commit = gesture.end()
        #expect(commit == .commit(translation: -56))
        let repeatedEnd = gesture.end()
        #expect(repeatedEnd == .cancelled)
    }

    @Test func stationaryHoldOpensTemporaryDrumWithoutCreatingTap() {
        var gesture = MonitorReadoutInteraction()
        gesture.begin()
        let opened = gesture.hold()
        #expect(opened)
        let repeatedHold = gesture.hold()
        #expect(!repeatedHold)
        gesture.move(x: 56, y: 8)
        let commit = gesture.end()
        #expect(commit == .commit(translation: 56))
    }

    @Test func verticalSwipeSlopAndInterruptionNeverCommitOrTap() {
        var gesture = MonitorReadoutInteraction()
        gesture.begin()
        gesture.move(x: 2, y: 28)
        let verticalHold = gesture.hold()
        #expect(!verticalHold)
        let verticalEnd = gesture.end()
        #expect(verticalEnd == .cancelled)
        gesture.begin()
        gesture.move(x: 10, y: 0)
        let slopEnd = gesture.end()
        #expect(slopEnd == .cancelled)
        gesture.begin()
        gesture.hold()
        gesture.move(x: 56, y: 0)
        gesture.cancel()
        let interruptedEnd = gesture.end()
        #expect(interruptedEnd == .cancelled)
        gesture.begin()
        gesture.move(x: .nan, y: 0)
        let invalidEnd = gesture.end()
        #expect(invalidEnd == .cancelled)
    }
}
