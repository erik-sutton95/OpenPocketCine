import Foundation
import MonitorPresentation
import Testing

struct MonitorPreviewAdmissionTests {
    @Test func remountPreservesBusyUntilTheOldOperationCompletes() throws {
        var admission = MonitorPreviewAdmission()
        let old = UUID()
        let next = UUID()
        admission.activate(owner: old)
        let attempt1 = admission.acquire(owner: old, nowNanoseconds: 0)
        let first = try #require(attempt1)
        admission.deactivate(owner: old)
        admission.activate(owner: next)
        #expect(!admission.isCurrent(first))
        let attempt2 = admission.acquire(owner: next, nowNanoseconds: 1_000_000_000)
        #expect(attempt2 == nil)
        admission.complete(first)
        let attempt3 = admission.acquire(owner: next, nowNanoseconds: 1_000_000_000)
        #expect(attempt3 != nil)
    }

    @Test func rapidOwnerChangesCannotRestartTheMinimumInterval() throws {
        var admission = MonitorPreviewAdmission()
        let firstOwner = UUID()
        admission.activate(owner: firstOwner)
        let attempt4 = admission.acquire(owner: firstOwner, nowNanoseconds: 0)
        let first = try #require(attempt4)
        admission.complete(first)
        admission.deactivate(owner: firstOwner)
        let times: [UInt64] = [20_000_000, 80_000_000, 160_000_000, 199_999_999]
        for time in times {
            let owner = UUID()
            admission.activate(owner: owner)
            let attempt5 = admission.acquire(owner: owner, nowNanoseconds: time)
            #expect(attempt5 == nil)
            admission.deactivate(owner: owner)
        }
        let owner = UUID()
        admission.activate(owner: owner)
        let attempt6 = admission.acquire(owner: owner, nowNanoseconds: 200_000_000)
        #expect(attempt6 != nil)
    }

    @Test func sourceAndOptionEpochsRejectResultsWithoutReleasingTheirJob() throws {
        var admission = MonitorPreviewAdmission()
        let owner = UUID()
        admission.activate(owner: owner)
        let attempt7 = admission.acquire(owner: owner, nowNanoseconds: 0)
        let first = try #require(attempt7)
        admission.invalidate(owner: owner)
        admission.invalidate(owner: owner)
        #expect(!admission.isCurrent(first))
        let attempt8 = admission.acquire(owner: owner, nowNanoseconds: 400_000_000)
        #expect(attempt8 == nil)
        admission.complete(first)
        let attempt9 = admission.acquire(owner: owner, nowNanoseconds: 400_000_000)
        let next = try #require(attempt9)
        #expect(admission.isCurrent(next))
    }

    @Test func staleOwnerAndDuplicateCompletionCannotDisturbCurrentWork() throws {
        var admission = MonitorPreviewAdmission()
        let old = UUID()
        let owner = UUID()
        admission.activate(owner: old)
        admission.activate(owner: owner)
        let attempt10 = admission.acquire(owner: owner, nowNanoseconds: 0)
        let first = try #require(attempt10)
        admission.complete(first)
        let attempt11 = admission.acquire(owner: owner, nowNanoseconds: 200_000_000)
        let second = try #require(attempt11)
        #expect(
            !admission.isCurrent(first), "A completed older frame is no longer the latest result")
        admission.deactivate(owner: old)
        admission.invalidate(owner: old)
        admission.complete(first)
        #expect(admission.isCurrent(second))
        let attempt12 = admission.acquire(owner: owner, nowNanoseconds: 400_000_000)
        #expect(attempt12 == nil)
        admission.complete(second)
        let attempt13 = admission.acquire(owner: owner, nowNanoseconds: 400_000_000)
        #expect(attempt13 != nil)
    }

    @Test func clockRegressionAndInactiveRequestsCannotBypassAdmission() throws {
        var admission = MonitorPreviewAdmission()
        let owner = UUID()
        let attempt14 = admission.acquire(owner: owner, nowNanoseconds: 0)
        #expect(attempt14 == nil)
        admission.activate(owner: owner)
        let attempt15 = admission.acquire(owner: owner, nowNanoseconds: 1_000_000_000)
        let first = try #require(attempt15)
        admission.complete(first)
        let attempt16 = admission.acquire(owner: owner, nowNanoseconds: 0)
        #expect(attempt16 == nil)
        let attempt17 = admission.acquire(owner: owner, nowNanoseconds: 1_199_999_999)
        #expect(attempt17 == nil)
        let attempt18 = admission.acquire(owner: owner, nowNanoseconds: 1_200_000_000)
        #expect(attempt18 != nil)
    }
}
