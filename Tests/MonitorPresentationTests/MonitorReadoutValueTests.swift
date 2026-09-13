import Foundation
import MonitorPresentation
import Testing

struct MonitorReadoutValueTests {
    @Test func unknownNativeValueRemainsUnselectedUntilADifferentDetentIsChosen() {
        let snapshot = MonitorReadoutSnapshot(
            title: "Exposure", options: ["−0.3", "0.0", "+0.3"], selection: "", fallbackIndex: 1)
        for travel in [0.0, -3, -56, 0] {
            let value = MonitorReadoutValue(
                id: UUID(), sourceIdentity: "camera-a", snapshot: snapshot,
                position: snapshot.position(translation: travel))
            #expect(value.selection == (travel == -56 ? "+0.3" : ""))
            #expect(value.changedValue == (travel == -56 ? "+0.3" : nil))
        }
    }

    @Test func nativeSelectionWinsOverFallbackAndReturningToItDoesNotCommit() {
        let snapshot = MonitorReadoutSnapshot(
            title: "Sensitivity", options: ["100", "200", "400"], selection: "400",
            marked: ["400"], fallbackIndex: 0)
        #expect(snapshot.originIndex == 2)
        #expect(snapshot.selection(at: snapshot.position(translation: 56)) == "200")
        #expect(snapshot.changedValue(at: snapshot.position(translation: 56)) == "200")
        #expect(snapshot.selection(at: snapshot.position(translation: 0)) == "400")
        #expect(snapshot.changedValue(at: snapshot.position(translation: 0)) == nil)
        #expect(snapshot.marked == ["400"])
    }

    @Test func invalidOrEmptyPreviewCannotProduceACameraIntent() {
        let empty = MonitorReadoutSnapshot(title: "Empty", options: [], selection: "")
        let unknown = MonitorReadoutSnapshot(
            title: "Unknown", options: ["First", "Second"], selection: "unreported",
            fallbackIndex: 99)
        #expect(empty.selection(at: 100) == "")
        #expect(empty.changedValue(at: 100) == nil)
        #expect(unknown.originIndex == 1)
        #expect(unknown.selection(at: 1) == "")
        #expect(unknown.changedValue(at: .nan) == nil)
        #expect(unknown.changedValue(at: .infinity) == nil)
    }

    @Test func releaseCarriesFrozenSourceAndOwnershipRevisionAcrossNewPointerAdmission() throws {
        let source = UUID()
        let pointer = UUID()
        var ownership = MonitorReadoutOwnership()
        let admission = ownership.acquire(pointer)
        let revision = try #require(admission)
        let snapshot = MonitorReadoutSnapshot(
            title: "Focus", options: ["Single", "Continuous", "Track"], selection: "Single")
        var gesture = MonitorReadoutInteraction()
        gesture.begin()
        let armed = gesture.move(x: -15, y: 0)
        #expect(armed)
        gesture.move(x: -127, y: 0)
        guard case .commit(let translation) = gesture.end() else {
            Issue.record("An armed drag must release its final detent")
            return
        }
        let release = MonitorReadoutValue(
            id: pointer, sourceIdentity: source, snapshot: snapshot,
            position: snapshot.position(translation: translation))
        ownership.release(pointer)
        #expect(release.changedValue == "Track")
        #expect(release.sourceIdentity == source)
        #expect(ownership.permitsDeferredCommit(revision))
        let nextPointer = UUID()
        let nextAdmission = ownership.acquire(nextPointer)
        #expect(nextAdmission != nil)
        ownership.release(nextPointer)
        #expect(!ownership.permitsDeferredCommit(revision))
        #expect(release.snapshot.selection == "Single", "Release is not native camera truth")
    }

    @Test func immutablePreviewCanBeReadOnABackgroundRendererWithoutHostAccess() async {
        let snapshot = MonitorReadoutSnapshot(
            title: "Temperature", options: ["5500K", "5600K", "5700K"], selection: "5600K")
        let preview = MonitorReadoutValue(
            id: UUID(), sourceIdentity: 42, snapshot: snapshot, position: 2)
        let rendered = await Task.detached { (preview.selection, preview.snapshot.title) }.value
        #expect(rendered.0 == "5700K")
        #expect(rendered.1 == "Temperature")
    }
}
