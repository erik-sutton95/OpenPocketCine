import OpenPocketViewCore
import OpenCineCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class SessionRecoveryChromeTests: XCTestCase {
    func testOperatorExitClearsHeldMonitor() async {
        let model = AppModel()
        XCTAssertFalse(model.session.holdsMonitor)
        model.shell.present(ConnectedCamera(saved: OpenCineCore.SavedCamera(
            id: "simulated-recovery", integration: DJICameraSessionAdapter.integration,
            advertisedName: "SIMULATED recovery", model: "SIMULATED"), session: model.session.control))
        let monitor = model.shell.monitor?.id
        model.session.holdsMonitor = true
        XCTAssertTrue(model.isLive, "A held monitor stays up while recovering")
        model.session.sessionRecovery = .waitingForOperator(attemptsMade: 8)
        XCTAssertEqual(model.shell.monitor?.id, monitor)
        model.exitMonitorToOperatorMenu()
        for _ in 0..<200 where model.session.holdsMonitor { await Task.yield() }
        XCTAssertNil(model.shell.monitor)
        XCTAssertFalse(model.session.holdsMonitor)
        XCTAssertEqual(model.session.sessionRecovery, .idle)
    }
}
