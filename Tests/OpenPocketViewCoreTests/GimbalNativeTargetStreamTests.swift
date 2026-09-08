import Foundation
import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalNativeTargetStreamTests {
    private func target(_ yaw: Double) -> Duml.Frame {
        Commands.gimbalTimedTarget(yawDeg: yaw, nativePitchDeg: 170, duration: 0.1)!
    }

    @Test func coalescesRapidTargetsAndHonorsWireBudget() {
        var stream = GimbalNativeTargetStream()
        stream.begin(token: 1)
        stream.submit(target(1), token: 1, now: 0)
        let first = stream.next(now: 0)
        #expect(first == target(1))
        stream.submit(target(2), token: 1, now: 0.01)
        stream.submit(target(3), token: 1, now: 0.02)
        let early = stream.next(now: 0.03)
        #expect(early == nil)
        let next = stream.next(now: 0.04)
        #expect(next == target(3))
        let empty = stream.next(now: 0.08)
        #expect(empty == nil)
    }

    @Test func stationaryTargetIsNotRepeatedAndDelayedQueueDoesNotBurst() {
        var stream = GimbalNativeTargetStream()
        stream.begin(token: 1)
        stream.submit(target(1), token: 1, now: 0)
        _ = stream.next(now: 0)
        stream.submit(target(1), token: 1, now: 0.1)
        let duplicate = stream.next(now: 0.1)
        #expect(duplicate == nil)
        stream.submit(target(2), token: 1, now: 0.2)
        let stale = stream.next(now: 0.5)
        #expect(stale == nil)
        stream.submit(target(2), token: 1, now: 0.51)
        let fresh = stream.next(now: 0.51)
        #expect(fresh == target(2))
    }

    @Test func unavailableSocketCannotAccumulateStaleTargets() {
        var stream = GimbalNativeTargetStream()
        stream.begin(token: 1)
        stream.submit(target(1), token: 1, now: 0)
        let waiting = stream.next(now: 0.1, connectionReady: false)
        #expect(waiting == nil)
        let expired = stream.next(now: 0.3, connectionReady: false)
        #expect(expired == nil)
        let ready = stream.next(now: 0.31)
        #expect(ready == nil)
        stream.submit(target(2), token: 1, now: 0.32)
        let fresh = stream.next(now: 0.33)
        #expect(fresh == target(2))
    }

    @Test func oldOwnerCannotStopOrOverwriteNewOwner() {
        var stream = GimbalNativeTargetStream()
        stream.begin(token: 1)
        stream.submit(target(1), token: 1, now: 0)
        stream.begin(token: 2)
        stream.submit(target(2), token: 2, now: 0.01)
        let oldUpdate = stream.submit(target(3), token: 1, now: 0.02)
        let oldStop = stream.cancel(token: 1)
        #expect(!oldUpdate && !oldStop)
        let next = stream.next(now: 0.04)
        #expect(next == target(2))
        stream.submit(target(4), token: 2, now: 0.05)
        let stopped = stream.cancel(token: 2)
        #expect(stopped)
        let afterStop = stream.next(now: 0.1)
        #expect(afterStop == nil)
    }
}
