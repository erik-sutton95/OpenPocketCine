import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class SessionRecoveryChromeTests: XCTestCase {
    func testOperatorExitClearsHeldMonitor() {
        let model = AppModel()
        XCTAssertFalse(model.session.holdsMonitor)
        model.session.holdsMonitor = true
        XCTAssertTrue(model.isLive, "A held monitor stays up while recovering")
        model.session.sessionRecovery = .waitingForOperator(attemptsMade: 8)
        model.exitMonitorToOperatorMenu()
        XCTAssertFalse(model.session.holdsMonitor)
        XCTAssertEqual(model.session.sessionRecovery, .idle)
    }
}
