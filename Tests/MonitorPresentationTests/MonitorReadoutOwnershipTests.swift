import Foundation
import MonitorPresentation
import Testing

struct MonitorReadoutOwnershipTests {
    @Test func firstPointerReservesTheStripBeforeEitherHoldCanPublish() {
        var ownership = MonitorReadoutOwnership()
        let first = UUID()
        let second = UUID()
        let admitted = ownership.acquire(first)
        #expect(admitted != nil)
        let rejected = ownership.acquire(second)
        #expect(rejected == nil)
        #expect(ownership.owns(first))
        #expect(!ownership.owns(second))
        ownership.release(second)
        #expect(ownership.owns(first), "A denied pointer must not clear the active drum owner")
    }

    @Test func secondaryPointerCannotRearmWhenTheOwnerLifts() {
        var ownership = MonitorReadoutOwnership()
        var ownerGesture = MonitorReadoutInteraction()
        var secondaryGesture = MonitorReadoutInteraction()
        let owner = UUID()
        let secondary = UUID()
        let admitted = ownership.acquire(owner)
        #expect(admitted != nil)
        ownerGesture.begin()
        let rejected = ownership.acquire(secondary)
        #expect(rejected == nil)
        secondaryGesture.cancel()
        ownerGesture.hold()
        ownerGesture.move(x: 56, y: 0)
        let outcome = ownerGesture.end()
        #expect(outcome == .commit(translation: 56))
        ownership.release(owner)

        secondaryGesture.move(x: 80, y: 0)
        let held = secondaryGesture.hold()
        let secondaryOutcome = secondaryGesture.end()
        #expect(!held)
        #expect(secondaryOutcome == .cancelled)
        let freshPointer = ownership.acquire(UUID())
        #expect(freshPointer != nil, "A new pointer after release must remain usable")
    }

    @Test func staleReleaseCannotCancelAnotherPointersReservation() {
        var ownership = MonitorReadoutOwnership()
        let old = UUID()
        let next = UUID()
        let oldRevision = ownership.acquire(old)
        #expect(oldRevision != nil)
        ownership.release(old)
        let nextRevision = ownership.acquire(next)
        #expect(nextRevision != nil)
        ownership.release(old)
        #expect(ownership.owns(next))
    }

    @Test func newTouchInvalidatesDeferredCommitEvenIfItEndsBeforeDispatch() throws {
        var ownership = MonitorReadoutOwnership()
        let first = UUID()
        let firstAdmission = ownership.acquire(first)
        let revision = try #require(firstAdmission)
        #expect(!ownership.permitsDeferredCommit(revision))
        let rejected = ownership.acquire(UUID())
        #expect(rejected == nil)
        ownership.release(first)
        #expect(ownership.permitsDeferredCommit(revision))

        let next = UUID()
        let nextAdmission = ownership.acquire(next)
        let nextRevision = try #require(nextAdmission)
        #expect(!ownership.permitsDeferredCommit(revision))
        ownership.release(next)
        #expect(!ownership.permitsDeferredCommit(revision))
        #expect(ownership.permitsDeferredCommit(nextRevision))
    }
}
