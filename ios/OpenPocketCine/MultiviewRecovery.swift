import OpenPocketViewCore

/// Each tile owns one bounded repair ladder. A healthy take resets its budget.
struct MultiviewRecovery {
    var watchdog = FeedWatchdog()
    private(set) var rejoins = 0
    private(set) var failed = false
    private var healthySince: Double?

    mutating func action(_ snapshot: FeedWatchdog.Snapshot) -> FeedWatchdog.Action {
        guard !failed else { return .none }
        if FeedWatchdog.udpReceiveAlive(snapshot) {
            if healthySince == nil { healthySince = snapshot.now }
            if snapshot.now - (healthySince ?? snapshot.now) >= 30 { rejoins = 0 }
        } else {
            healthySince = nil
        }
        let action = watchdog.tick(snapshot)
        // The base first-picture ladder ends at cooldown; Multiview then tries
        // a new verified session before offering tile-local actions.
        if snapshot.live, snapshot.pathReady, !snapshot.hadVideo, watchdog.stage == .cooldown,
            !FeedWatchdog.shouldHoldForGOPReset(
                secondsSinceLastEnable: snapshot.secondsSinceLastEnable,
                lastVideoPacketAge: snapshot.lastVideoPacketAge),
            !FeedWatchdog.shouldHoldForCameraSet(
                secondsSinceSet: snapshot.secondsSinceCameraSet,
                lastVideoPacketAge: snapshot.lastVideoPacketAge),
            snapshot.now - watchdog.lastActionAt >= FeedWatchdog.escalateAfter
        {
            return .fullSessionRejoin
        }
        return action
    }
    mutating func beginRejoin() -> Bool {
        guard !failed, rejoins < 2 else {
            failed = true
            return false
        }
        rejoins += 1
        watchdog = FeedWatchdog()
        return true
    }
    mutating func fail() { failed = true }
}
