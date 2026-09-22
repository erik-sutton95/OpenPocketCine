import Testing

@testable import OpenPocketViewCore

@Suite struct KnownReferenceLossTests {
    @Test(arguments: [true, false])
    func explicitLossRequestsTheExistingRepairBeforeTheOrdinaryTimeout(hasFormat: Bool) {
        func snapshot(elapsed: Double = 0) -> FeedWatchdog.Snapshot {
            var result = Self.snapshot(elapsed: elapsed)
            result.hasFormat = hasFormat
            return result
        }
        var dog = FeedWatchdog()
        #expect(dog.tick(snapshot()) == .rebuildVTSession)
        #expect(dog.stage == .rebuildVT)
        #expect(dog.lastActionAt == 100)
        for elapsed in [0.1, 1, 2, 8, 15.999] {
            #expect(dog.tick(snapshot(elapsed: elapsed)) == .none)
            #expect(dog.lastActionAt == 100, "Repeated loss cannot renew the repair deadline")
        }
        #expect(dog.tick(snapshot(elapsed: 16)) == .fullSessionRejoin)
        #expect(dog.tick(snapshot(elapsed: 17)) == .none)
    }

    @Test func clearingLossBeforeNewOutputDoesNotReleaseAnEarlyRepair() {
        var dog = FeedWatchdog()
        #expect(dog.tick(Self.snapshot()) == .rebuildVTSession)
        for elapsed in [0.1, 0.5, 1] {
            var snap = Self.snapshot(elapsed: elapsed)
            snap.referenceRecoveryNeeded = false
            #expect(dog.tick(snap) == .none)
            #expect(dog.stage == .rebuildVT, "The still-young output predates this action")
        }
        var recovered = Self.snapshot(elapsed: 1.1)
        recovered.lastDecoderOutputAge = 0.01
        #expect(dog.tick(recovered) == .none)
        #expect(dog.stage == .rebuildVT, "A late old-GOP output cannot clear explicit loss")
        recovered.referenceRecoveryNeeded = false
        #expect(dog.tick(recovered) == .none)
        #expect(dog.stage == .idle)
    }

    @Test func missingOutputProofCannotCompleteAnEarlyRepair() {
        var dog = FeedWatchdog()
        #expect(dog.tick(Self.snapshot()) == .rebuildVTSession)
        var snap = Self.snapshot(elapsed: 16)
        snap.referenceRecoveryNeeded = false
        snap.lastDecoderOutputAge = nil
        snap.lastDecodedFrameAge = nil
        #expect(dog.tick(snap) == .fullSessionRejoin)
    }

    @Test func noExplicitLossKeepsTheOrdinaryOutputThreshold() {
        var dog = FeedWatchdog()
        var snap = Self.snapshot()
        snap.referenceRecoveryNeeded = false
        snap.lastDecoderOutputAge = 1.999
        #expect(dog.tick(snap) == .none)
        snap.lastDecoderOutputAge = 2
        #expect(dog.tick(snap) == .rebuildVTSession)
    }

    @Test func referenceLossPreservesReadinessAndEveryControlGrace() {
        for gate in 0..<10 {
            var dog = FeedWatchdog()
            var snap = Self.snapshot()
            switch gate {
            case 0: snap.repairReady = false
            case 1: snap.pathReady = false
            case 2: snap.zoomPinchActive = true
            case 3: snap.gimbalStickHeld = true
            case 4: snap.secondsSinceCameraSet = 0.1
            case 5: snap.secondsSinceFocusTrackSet = 0.1
            case 6: snap.secondsSinceZoomSet = 0.1
            case 7: snap.secondsSinceGimbalThrow = 0.1
            case 8: snap.secondsSinceLastEnable = 1
            default: snap.live = false
            }
            #expect(dog.tick(snap) == .none)
            #expect(dog.stage == .idle, "A blocked request spends no repair action")
            #expect(dog.tick(Self.snapshot(elapsed: 0.1)) == .rebuildVTSession)
        }
    }

    @Test func startupAndUnobservableOutputCannotFastRepair() {
        for gate in 0..<2 {
            var snap = Self.snapshot()
            switch gate {
            case 0: snap.sawPicture = false
            default: snap.decoderOutputExpected = false
            }
            var dog = FeedWatchdog()
            #expect(dog.tick(snap) == .none)
        }
        var healthy = Self.snapshot()
        healthy.referenceRecoveryNeeded = false
        healthy.lastDecodedFrameAge = 20
        healthy.lastDecoderOutputAge = 0.01
        var dog = FeedWatchdog()
        #expect(dog.tick(healthy) == .none, "A presentation-only stall still owns no codec repair")
    }

    @Test func retiredAndCooldownOwnersCannotAcquireAnotherLossRepair() {
        for stage in [FeedWatchdog.Stage.fullRejoin, .cooldown] {
            var dog = FeedWatchdog()
            dog.stage = stage
            for elapsed in [0.0, 1, 20] {
                #expect(dog.tick(Self.snapshot(elapsed: elapsed)) == .none)
                #expect(dog.stage == stage)
            }
        }
    }

    private static func snapshot(elapsed: Double = 0) -> FeedWatchdog.Snapshot {
        FeedWatchdog.Snapshot(
            now: 100 + elapsed,
            lastDecodedFrameAge: 0.239 + elapsed,
            lastVideoPacketAge: 0.01, lastAccessUnitAge: 0.01, lastStatusAge: 0.01,
            flowHealthy: true, pathReady: true, hasFormat: true, decoderFailed: false,
            live: true, sawPicture: true,
            lastDecoderOutputAge: 0.239 + elapsed, decoderOutputExpected: true,
            referenceRecoveryNeeded: true)
    }
}
