import Testing

@testable import OpenPocketViewCore

@Suite("Session recovery copy")
struct SessionRecoveryCopyTests {
    @Test(arguments: [
        (
            SessionRecoveryState.retrying(attempt: 3, maxAttempts: 8), "Reconnecting…",
            ["Pocket 4 Pro", "attempt 3 of 8"]
        ),
        (.waitingForOperator(attemptsMade: 8), "Camera disconnected", ["8 tries", "held, not live"]),
        (
            .pausedAfterRepeatedDrops(drops: 3), "Connection keeps dropping",
            ["3 times", "protect the camera", "held, not live"]
        ),
        (.waitingForOperator(attemptsMade: 1), "Camera disconnected", ["1 try"]),
    ])
    func copyNamesStateAndCount(state: SessionRecoveryState, title: String, phrases: [String]) {
        #expect(SessionRecoveryCopy.title(state) == title)
        let detail = SessionRecoveryCopy.detail(state, deviceName: "Pocket 4 Pro")
        for phrase in phrases {
            #expect(detail.contains(phrase))
        }
        #expect(!detail.localizedCaseInsensitiveContains("Nikon"))
        #expect(!detail.localizedCaseInsensitiveContains("OpenZCine"))
    }
}
