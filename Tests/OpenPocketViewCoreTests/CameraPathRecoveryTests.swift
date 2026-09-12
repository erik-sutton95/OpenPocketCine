import Testing

@testable import OpenPocketViewCore

@Suite("Camera SoftAP loss ownership")
struct CameraPathRecoveryTests {
    @Test func transientAddressFlapDoesNotReconnect() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(!loss(&policy, at: 17.9))
        #expect(
            !observe(
                &policy, now: 18, pathReady: true, videoFresh: false,
                sessionActive: true, repairInFlight: false))
        #expect(!loss(&policy, at: 19))
        #expect(!loss(&policy, at: 26.9))
    }

    @Test func sustainedLossRequestsFullRecoveryOnceAfterEightSeconds() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(!loss(&policy, at: 17.9))
        #expect(loss(&policy, at: 18))
        #expect(!loss(&policy, at: 19))
        #expect(!loss(&policy, at: 100))
    }

    @Test func freshVideoResetsAnUnreliableInterfaceObservation() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(
            !observe(
                &policy, now: 17, pathReady: false, videoFresh: true,
                sessionActive: true, repairInFlight: false))
        #expect(!loss(&policy, at: 18))
        #expect(!loss(&policy, at: 25.9))
        #expect(loss(&policy, at: 26))
    }

    @Test func inactiveSceneDoesNotSpendReassociationGrace() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(
            !observe(
                &policy, now: 17, pathReady: false, videoFresh: false,
                sessionActive: false, repairInFlight: false))
        #expect(!loss(&policy, at: 100))
        #expect(loss(&policy, at: 108))
    }

    @Test func existingRepairRetainsOwnershipUntilItFinishes() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(
            !observe(
                &policy, now: 18, pathReady: false, videoFresh: false,
                sessionActive: true, repairInFlight: true))
        #expect(loss(&policy, at: 19))
        #expect(!loss(&policy, at: 20))
    }

    @Test func resetStartsANewSessionGraceAndAllowsNewRecovery() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(loss(&policy, at: 18))
        policy.reset()
        #expect(!loss(&policy, at: 100))
        #expect(!loss(&policy, at: 107.9))
        #expect(loss(&policy, at: 108))
    }

    @Test func invalidOrRewoundClockDoesNotInventAnExpiredGrace() {
        var policy = CameraPathRecovery()
        #expect(!loss(&policy, at: 10))
        #expect(!loss(&policy, at: .nan))
        #expect(!loss(&policy, at: 100))
        #expect(!loss(&policy, at: 5))
        #expect(!loss(&policy, at: 12.9))
        #expect(loss(&policy, at: 13))
    }

    private func observe(
        _ policy: inout CameraPathRecovery, now: Double, pathReady: Bool,
        videoFresh: Bool, sessionActive: Bool, repairInFlight: Bool
    ) -> Bool {
        policy.tick(
            now: now, pathReady: pathReady, videoFresh: videoFresh,
            sessionActive: sessionActive, repairInFlight: repairInFlight)
    }

    private func loss(_ policy: inout CameraPathRecovery, at now: Double) -> Bool {
        policy.tick(
            now: now, pathReady: false, videoFresh: false,
            sessionActive: true, repairInFlight: false)
    }
}
