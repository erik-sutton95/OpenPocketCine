import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class SessionRecoveryLifecycleTests: XCTestCase {
    func testCanceledRepairCannotReleaseNewRepairOwnership() async {
        let session = CameraSession(borrowing: HevcDecoder())
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        session.startFeedRecovery { await withCheckedContinuation { first = $0 } }
        while first == nil { await Task.yield() }
        session.resetFeedWatchdog()
        session.startFeedRecovery { await withCheckedContinuation { second = $0 } }
        while second == nil { await Task.yield() }

        first?.resume()
        for _ in 0..<20 { await Task.yield() }
        var thirdStarted = false
        session.startFeedRecovery { thirdStarted = true }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(thirdStarted, "Old completion must not admit a competing repair")
        XCTAssertTrue(session.feedRecovering, "The second repair is still running")
        second?.resume()
        session.resetFeedWatchdog()
    }

    func testBluetoothPowerWaitEndsOnCancellationAndTimeout() async {
        let task = Task { await BleLink.waitForPower(timeout: .seconds(30)) { false } }
        task.cancel()
        let canceled = await task.value
        XCTAssertFalse(canceled)
        let timeout = await BleLink.waitForPower(timeout: .zero) { false }
        XCTAssertFalse(timeout)
        let ready = await BleLink.waitForPower(timeout: .zero) { true }
        XCTAssertTrue(ready)
    }

    func testHotspotCallbackCancellationIgnoresLateSuccess() async {
        var callback: ((Result<Void, Error>) -> Void)?
        let task = Task {
            try await WiFiJoiner.awaitCallback(timeout: .seconds(30)) { callback = $0 }
        }
        while callback == nil { await Task.yield() }
        task.cancel()
        do {
            try await task.value
            XCTFail("Canceled join must not succeed")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        callback?(.success(()))
        callback?(.success(()))
    }

    func testHotspotCallbackTimeoutDoesNotRequireOSCompletion() async {
        do {
            let _: Void = try await WiFiJoiner.awaitCallback(timeout: .zero) { _ in }
            XCTFail("A missing OS callback must exhaust its deadline")
        } catch WiFiJoiner.JoinError.timedOut {
            // The system did not call back and the app can offer another attempt.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHeldImageCannotCompleteNewRecoveryAttempt() async throws {
        let decoder = HevcDecoder()
        let session = CameraSession(borrowing: decoder)
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        let beforePicture = Date()
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = Date().addingTimeInterval(2)
        while decoder.lastPresentedAt == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(decoder.lastPresentedAt)
        XCTAssertTrue(session.hasFreshRecoveryPicture(since: beforePicture))
        let newAttempt = Date()
        XCTAssertFalse(session.hasFreshRecoveryPicture(since: newAttempt))
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer(), isNewSourceFrame: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(
            session.hasFreshRecoveryPicture(since: newAttempt),
            "LUT repaint is not a recovered source")
        decoder.reset()
    }

    func testRecoveryAllowsTheUnderlyingWifiAndHandshakeDeadlines() {
        XCTAssertGreaterThanOrEqual(
            CameraSession.recoveryDeadline(for: .joiningWifi),
            .seconds(CameraSoftAPSwitch.joinDeadlineSeconds))
        XCTAssertGreaterThanOrEqual(
            CameraSession.recoveryDeadline(for: .openingDatalink), .seconds(40))
        XCTAssertEqual(
            CameraSession.recoveryDeadline(for: .live),
            .seconds(2 * CameraSoftAP.foregroundPictureGrace))
    }
    func testRecoveryProgressDoesNotCallHandshakeALivePicture() {
        XCTAssertEqual(
            MonitorRecoveryOverlay.progressDetail(.live), "Waiting for a new live picture…")
        XCTAssertEqual(
            MonitorRecoveryOverlay.progressDetail(.joiningWifi), "Rejoining camera Wi-Fi…")
    }

    func testRecoveryEpisodeDeadlineKeepsHeldFrameAndOffersOperatorRetry() async {
        let session = CameraSession(borrowing: HevcDecoder())
        session.holdsMonitor = true
        await session.runSessionRecovery(budget: .milliseconds(20))
        guard case .waitingForOperator = session.sessionRecovery else {
            return XCTFail("Episode must stop even while an attempt backoff is waiting")
        }
        XCTAssertTrue(session.holdsMonitor)
        XCTAssertTrue(session.sessionRecoveryCardGraceElapsed)
    }

    func testFailedAttemptReleasesTransportBeforeNextScanWhileHoldingPicture() async throws {
        let decoder = HevcDecoder()
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        let session = CameraSession(borrowing: decoder)
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        let deadline = Date().addingTimeInterval(2)
        while decoder.lastPresentedAt == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let heldPicture = try XCTUnwrap(decoder.lastPresentedAt)
        let failedDriver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
        session.holdsMonitor = true
        var attempts = 0
        await session.runSessionRecoveryAttempts {
            attempts += 1
            if attempts == 1 {
                session.datalink = failedDriver
                session.phase = .openingDatalink
                return false
            }
            XCTAssertTrue(
                failedDriver.isClosed,
                "Close the failed attempt before looking for another advertisement")
            XCTAssertNil(
                session.datalink, "The next attempt cannot inherit a half-connected transport")
            XCTAssertTrue(session.holdsMonitor)
            XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
            XCTAssertFalse(decoder.displayedImageRemoved)
            return true
        }
        XCTAssertEqual(attempts, 2)
        failedDriver.close()
        decoder.reset()
    }

}
