import Foundation
import Network
import Observation
import OpenCineApple
import XCTest

@testable import OpenPocketCine

@MainActor private final class WatcherObservationReceipt {
    var source: MonitorVideoSourceToken?
    var invoked = false
}

/// SIMULATED actual-class publication reentry. No connection is started or camera stream fabricated.
final class WatcherSourceObservationTests: XCTestCase {
    @MainActor
    func testLeavePublicationCannotResetOrOverwriteASynchronousSuccessor() {
        let client = WatcherRelayClient()
        client.decoder.bindSourcePublication(client.samples)
        client.status = .live
        let receipt = WatcherObservationReceipt()
        withObservationTracking { _ = client.status } onChange: {
            MainActor.assumeIsolated {
                receipt.invoked = true
                client.leave()
                client.status = .live
                client.token = .init(holderName: "Successor", holderIsRecipient: true)
                receipt.source = client.decoder.sourceToken
            }
        }
        client.leave()
        XCTAssertTrue(receipt.invoked)
        XCTAssertEqual(client.status, .live)
        XCTAssertTrue(client.canControl)
        XCTAssertNotNil(receipt.source)
        XCTAssertEqual(client.decoder.sourceToken, receipt.source)
        client.leave()
    }

    @MainActor
    func testJoinTitlePublicationCannotOverwriteASynchronousSuccessor() {
        let client = WatcherRelayClient()
        let receipt = WatcherObservationReceipt()
        withObservationTracking { _ = client.hostTitle } onChange: {
            MainActor.assumeIsolated {
                receipt.invoked = true
                client.leave()
                client.state.cameraName = "Successor camera"
                client.hostTitle = "Successor feed"
                client.status = .live
                client.token = .init(holderName: "Successor", holderIsRecipient: true)
                client.receivedFPS = 37
                receipt.source = client.decoder.sourceToken
            }
        }
        client.join(endpoint: .hostPort(host: "127.0.0.1", port: 9), hostName: "Retired feed",
            passcode: "", watcherID: "test-watcher", deviceName: "SIMULATED watcher")
        XCTAssertTrue(receipt.invoked)
        XCTAssertEqual(client.hostTitle, "Successor feed")
        XCTAssertEqual(client.state.cameraName, "Successor camera")
        XCTAssertEqual(client.status, .live)
        XCTAssertTrue(client.canControl)
        XCTAssertEqual(client.receivedFPS, 37)
        XCTAssertNotNil(receipt.source)
        XCTAssertEqual(client.decoder.sourceToken, receipt.source)
        client.leave()
    }

    @MainActor
    func testNativePreparationRetirementRefusesTheFormerConnection() {
        let client = WatcherRelayClient()
        let prepare = client.preparePicture
        let receipt = WatcherObservationReceipt()
        client.preparePicture = {
            prepare?()
            receipt.invoked = true
            client.leave()
            client.hostTitle = "Successor feed"
            client.status = .live
            client.token = .init(holderName: "Successor", holderIsRecipient: true)
            receipt.source = client.decoder.sourceToken
        }
        client.join(endpoint: .hostPort(host: "127.0.0.1", port: 9), hostName: "Retired feed",
            passcode: "", watcherID: "test-watcher", deviceName: "SIMULATED watcher")
        XCTAssertTrue(receipt.invoked)
        XCTAssertEqual(client.hostTitle, "Successor feed")
        XCTAssertEqual(client.status, .live)
        XCTAssertTrue(client.canControl)
        XCTAssertNotNil(receipt.source)
        XCTAssertEqual(client.decoder.sourceToken, receipt.source)
        client.preparePicture = nil
        client.leave()
    }
}
