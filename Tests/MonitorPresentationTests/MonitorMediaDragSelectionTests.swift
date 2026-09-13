import MonitorPresentation
import Testing

struct MonitorMediaDragSelectionTests {
    private let ids = (0..<12).map(String.init)

    @Test func selectionSweepsInBothDirectionsAndRestoresOriginalStateOnReversal() throws {
        var sweep = try #require(
            MonitorMediaDragSelection(
                orderedIDs: ids, originID: "4", selectedIDs: ["1", "6", "hidden"]))
        #expect(sweep.selectedIDs == ["1", "4", "6", "hidden"])
        let extended = sweep.move(to: 8)
        #expect(extended)
        #expect(sweep.selectedIDs == ["1", "4", "5", "6", "7", "8", "hidden"])
        let reversed = sweep.move(to: 2)
        #expect(reversed)
        #expect(sweep.selectedIDs == ["1", "2", "3", "4", "6", "hidden"])
        let restored = sweep.move(to: 4)
        #expect(restored)
        #expect(sweep.selectedIDs == ["1", "4", "6", "hidden"])
        let unchanged = sweep.move(to: 4)
        #expect(!unchanged)
    }

    @Test func selectedOriginDeselectsAndRestoresMixedPriorSelection() throws {
        var sweep = try #require(
            MonitorMediaDragSelection(
                orderedIDs: ids, originID: "4", selectedIDs: ["1", "4", "6", "9"]))
        #expect(sweep.selectedIDs == ["1", "6", "9"])
        sweep.move(to: 9)
        #expect(sweep.selectedIDs == ["1"])
        sweep.move(to: 2)
        #expect(sweep.selectedIDs == ["1", "6", "9"])
        sweep.move(to: 0)
        #expect(sweep.selectedIDs == ["6", "9"])
        sweep.move(to: 4)
        #expect(sweep.selectedIDs == ["1", "6", "9"])
    }

    @Test func missingOriginIsRejectedAndIndexJumpsAreBounded() throws {
        #expect(MonitorMediaDragSelection(orderedIDs: [], originID: "0", selectedIDs: []) == nil)
        var sweep = try #require(
            MonitorMediaDragSelection(orderedIDs: ids, originID: "0", selectedIDs: []))
        sweep.move(to: Int.max)
        #expect(sweep.selectedIDs == Set(ids))
        sweep.move(to: Int.min)
        #expect(sweep.selectedIDs == ["0"])
    }

    @Test func autoScrollHasQuietCenterEasedEdgesAndFiniteSpeed() {
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 200, viewportHeight: 400) == 0)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 28, viewportHeight: 400) == -180)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 372, viewportHeight: 400) == 180)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: -100, viewportHeight: 400) == -720)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 500, viewportHeight: 400) == 720)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: .nan, viewportHeight: 400) == 0)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 0, viewportHeight: 0) == 0)
        #expect(MonitorMediaSelectionScroll.velocity(pointerY: 15, viewportHeight: 30) == 0)
    }
}
