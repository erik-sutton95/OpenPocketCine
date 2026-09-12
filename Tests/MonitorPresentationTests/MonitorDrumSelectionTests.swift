import MonitorPresentation
import Testing

struct MonitorDrumSelectionTests {
    @Test func fingerTravelSelectsInEitherDirectionOnlyAtNearestDetent() {
        #expect(MonitorDrumSelection.settledIndex(origin: 3, translation: -56, count: 10) == 4)
        #expect(MonitorDrumSelection.settledIndex(origin: 3, translation: 56, count: 10) == 2)
        #expect(MonitorDrumSelection.settledIndex(origin: 3, translation: 27, count: 10) == 3)
        #expect(MonitorDrumSelection.settledIndex(origin: 3, translation: 29, count: 10) == 2)
    }

    @Test func changedOptionsAndExtremeTravelRemainInsideAvailableCapabilities() {
        #expect(MonitorDrumSelection.settledIndex(origin: 8, translation: 0, count: 3) == 2)
        #expect(MonitorDrumSelection.settledIndex(origin: 0, translation: 1000, count: 3) == 0)
        #expect(MonitorDrumSelection.settledIndex(origin: 0, translation: -1000, count: 3) == 2)
        #expect(MonitorDrumSelection.settledIndex(origin: 0, translation: 0, count: 0) == nil)
        #expect(MonitorDrumSelection.settledIndex(origin: 0, translation: -100, count: 1) == 0)
    }

    @Test func visualDetentPreservesWholeValuesAndToleratesInvalidGestureGeometry() {
        #expect(MonitorDrumSelection.position(origin: 4, translation: 0, count: 6) == 4)
        #expect(MonitorDrumSelection.position(origin: 4, translation: .nan, count: 6) == 4)
        #expect(MonitorDrumSelection.position(origin: 4, translation: .infinity, count: 6) == 4)
    }

    @Test func unknownOriginWobbleCannotChooseAnUnrequestedCameraValue() {
        // Empty camera state is rendered around fallback index zero. Neither
        // a 3pt wobble nor outward edge travel expresses a different choice.
        #expect(MonitorDrumSelection.changedIndex(origin: 0, translation: -3, count: 5) == nil)
        #expect(MonitorDrumSelection.changedIndex(origin: 0, translation: 56, count: 5) == nil)
        #expect(MonitorDrumSelection.changedIndex(origin: 0, translation: -56, count: 5) == 1)
        #expect(MonitorDrumSelection.changedIndex(origin: 0, translation: -56, count: 1) == nil)
        // A centered fallback such as unknown EV behaves identically.
        #expect(MonitorDrumSelection.changedIndex(origin: 3, translation: 3, count: 7) == nil)
        #expect(MonitorDrumSelection.changedIndex(origin: 3, translation: 56, count: 7) == 2)
    }

    @Test func sourceChangeAtLiftIsRejectedEvenBeforeTheChangeObserverRuns() {
        var pointer = MonitorDrumDrag<String>()
        let began = pointer.begin(selection: "1600", identity: "camera-a")
        #expect(began)
        let staleLift = pointer.end(identity: "camera-b")
        #expect(staleLift == nil)
        let freshBegan = pointer.begin(selection: "1600", identity: "camera-b")
        #expect(freshBegan)
        let freshLift = pointer.end(identity: "camera-b")
        #expect(freshLift == "1600")
    }

    @Test func invalidatedPointerCannotRearmUntilItHasEnded() {
        var pointer = MonitorDrumDrag<Int>()
        let began = pointer.begin(selection: "", identity: 1)
        #expect(began)
        let changedContext = pointer.begin(selection: "", identity: 2)
        #expect(!changedContext)
        let sameOldPointer = pointer.begin(selection: "", identity: 2)
        #expect(!sameOldPointer)
        let invalidLift = pointer.end(identity: 2)
        #expect(invalidLift == nil)
        let freshBegan = pointer.begin(selection: "", identity: 2)
        #expect(freshBegan)
        pointer.cancel(pointerIsActive: true)
        let cancelledLift = pointer.end(identity: 2)
        #expect(cancelledLift == nil)
        let afterCancellation = pointer.begin(selection: "", identity: 3)
        #expect(afterCancellation)
        let unknownOrigin = pointer.end(identity: 3)
        #expect(unknownOrigin == "", "Unknown camera selection is still a valid drag origin")
    }
}
