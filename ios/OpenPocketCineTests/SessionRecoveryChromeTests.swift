import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class SessionRecoveryChromeTests: XCTestCase {
    func testMonitorStaysUpWhileRecovering() {
        let model = AppModel()
        XCTAssertFalse(model.session.holdsMonitor)
        model.session.holdsMonitor = true
        XCTAssertTrue(model.session.holdsMonitor)
        XCTAssertTrue(model.isLive)
    }

    func testRecoveryCardCopyMatchesAttemptsPopup() {
        let retrying = SessionRecoveryState.retrying(attempt: 2, maxAttempts: 8)
        XCTAssertEqual(SessionRecoveryCopy.title(retrying), "Reconnecting…")
        XCTAssertTrue(
            SessionRecoveryCopy.detail(retrying, deviceName: "Pocket 4 Pro")
                .contains("attempt 2 of 8"))
        XCTAssertEqual(SessionRecoveryCopy.heldFrameBadge, "NO LINK")
    }

    func testOperatorExitClearsHeldMonitor() {
        let model = AppModel()
        model.session.holdsMonitor = true
        model.session.sessionRecovery = .waitingForOperator(attemptsMade: 8)
        model.exitMonitorToOperatorMenu()
        XCTAssertFalse(model.session.holdsMonitor)
        XCTAssertEqual(model.session.sessionRecovery, .idle)
    }
}
