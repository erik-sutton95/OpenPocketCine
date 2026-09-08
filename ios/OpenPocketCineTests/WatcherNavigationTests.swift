import Network
import XCTest

@testable import OpenPocketCine

final class WatcherNavigationTests: XCTestCase {
    @MainActor
    func testSelectingFeedKeepsBrowserVisibleWhileConnecting() {
        let model = AppModel()
        model.showsWatcherBrowse = true
        model.joinWatcher(
            .init(
                id: "test-relay", name: "Test relay", cameraName: "Test camera",
                endpoint: .hostPort(host: "127.0.0.1", port: 9)))
        XCTAssertEqual(model.relayClient.status, .connecting)
        XCTAssertTrue(model.showsWatcherBrowse)
        XCTAssertFalse(model.showsWatcherMonitor)
        model.stopWatching()
    }

    @MainActor
    func testAcceptedWatcherDoesNotReturnToPairingWhenTransportFails() {
        let model = AppModel()
        model.showsWatcherBrowse = true
        model.relayClient.status = .live
        model.noteWatcherStatusChanged(.live)
        XCTAssertTrue(model.showsWatcherMonitor)
        XCTAssertFalse(model.showsWatcherBrowse)

        model.relayClient.status = .failed("The host stopped sharing.")
        model.noteWatcherStatusChanged(model.relayClient.status)
        XCTAssertTrue(
            model.showsWatcherMonitor,
            "Keep the watcher error and Leave controls visible; never reveal the camera pairing wizard"
        )

        model.relayClient.status = .needsPasscode
        model.noteWatcherStatusChanged(.needsPasscode)
        XCTAssertTrue(model.showsWatcherBrowse)
        XCTAssertFalse(model.showsWatcherMonitor)
        model.stopWatching()
        XCTAssertFalse(model.showsWatcherMonitor)
    }

    @MainActor
    func testPasscodeAndInitialFailureStayOnJoinScreen() {
        let model = AppModel()
        model.showsWatcherBrowse = true
        for status: WatcherRelayClientStatus in [
            .connecting, .needsPasscode, .failed("Unavailable"),
        ] {
            model.relayClient.status = status
            model.noteWatcherStatusChanged(status)
            XCTAssertTrue(model.showsWatcherBrowse)
            XCTAssertFalse(model.showsWatcherMonitor)
        }
        model.relayClient.status = .needsPasscode
        model.stopWatching()
        XCTAssertEqual(model.relayClient.status, .idle)
        XCTAssertFalse(model.showsWatcherBrowse)
    }
}
