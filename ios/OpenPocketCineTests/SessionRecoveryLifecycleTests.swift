import OpenCineDJIApple
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class SessionRecoveryLifecycleTests: XCTestCase {
    /// SIMULATED clock/transport cross the actual app-owned heartbeat and common close.
    func testOwnedCommonCloseRetiresHeartbeatAndLateWakeWithoutStoppingRecording() {
        let clock = HeartbeatClock()
        let session = CameraSession(heartbeatTiming: clock.timing)
        session.sessionHeartbeat.endpoint = clock.endpoint
        session.applyIncomingStatus(.init(sender: 1, receiver: 2, seq: 0,
            flags: Duml.flagResponse, cmdSet: 2, cmdId: 0x80,
            payload: [0x81] + Array(repeating: 0, count: 12)))
        XCTAssertTrue(session.cameraReportedCapture.recordingReported)
        XCTAssertTrue(session.cameraReportedCapture.isRecording)
        session.startKeepalive(ssid: nil)
        clock.advance(to: 0)
        XCTAssertEqual(clock.frames.map(\.cmdId), [0x2b])
        XCTAssertEqual(clock.registrations, 1)
        session.noteSceneBecameInactive()
        clock.advance(to: 1)
        XCTAssertEqual(clock.registrations, 2, "Scene inactivity must keep app registration")
        let oldWake = clock.wakes.first?.1
        session.control.close(.requested)
        oldWake?()
        clock.advance(to: 20)
        XCTAssertEqual(clock.frames.map(\.cmdId), [0x2b, 0x2b])
        XCTAssertEqual(clock.registrations, 2)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(clock.frames.contains { $0.cmdSet == 2 && $0.cmdId == 2 },
            "Closing while recording does not send a recording command")
    }

    func testBorrowedViewCannotStartConnectionHeartbeatOrRetireTileHeartbeat() {
        let clock = HeartbeatClock()
        let tileHeartbeat = DjiAppleSessionHeartbeat(endpoint: clock.endpoint, timing: clock.timing,
            context: { .init() }, event: { _ in XCTFail("No maintenance in this tile fixture") })
        tileHeartbeat.start(monitorMaintenanceEnabled: false)
        let decoder = HevcDecoder()
        let borrowed = CameraSession(borrowing: decoder, heartbeatTiming: clock.timing)
        borrowed.sessionHeartbeat.endpoint = .init(
            writeBLE: { _ in XCTFail("Borrowed view cannot register over BLE") },
            registerDatalink: { XCTFail("Borrowed view cannot register over UDP") },
            transport: { .init() })
        borrowed.startKeepalive(ssid: "SIMULATED")
        clock.advance(to: 0)
        borrowed.disconnect()
        clock.advance(to: 1)
        XCTAssertEqual(clock.registrations, 2, "Multiview tile remains the sole registration owner")
        XCTAssertEqual(clock.frames.map(\.cmdId), [0x2b, 0x2b])
        tileHeartbeat.stop()
        decoder.close()
    }

    func testActualNativeEndpointReportsUnknownTimesAndDoesNotReopenClosedDatalink() {
        let driver = DatalinkDriver(port: 9, tcpPoke: false, pairingToken: "")
        let endpoint = DjiAppleHeartbeatEndpoint(datalink: driver)
        let observed = endpoint.transport()
        XCTAssertNil(observed.lastVideoAt)
        XCTAssertNil(observed.lastSelfieFlipReplyAt)
        XCTAssertNil(observed.lastSelfieFlipSendAt)
        driver.close()
        endpoint.registerDatalink()
        XCTAssertTrue(driver.isClosed)
        XCTAssertNil(endpoint.transport().lastSelfieFlipSendAt)
    }

    @MainActor private final class HeartbeatClock {
        var time: TimeInterval = 0
        var wakes: [(TimeInterval, @MainActor @Sendable () -> Void)] = []
        var frames: [Duml.Frame] = []
        var registrations = 0
        var timing: DjiAppleHeartbeatTiming {
            .init(wallNow: { [unowned self] in time }, uptime: { [unowned self] in time },
                schedule: { [unowned self] delay, wake in
                    let c = delay.components
                    wakes.append((time + Double(c.seconds) + Double(c.attoseconds) / 1e18, wake))
                })
        }
        var endpoint: DjiAppleHeartbeatEndpoint {
            .init(writeBLE: { [unowned self] in frames.append($0) },
                registerDatalink: { [unowned self] in registrations += 1 },
                transport: { .init() })
        }
        func advance(to deadline: TimeInterval) {
            while let next = wakes.enumerated().filter({ $0.element.0 <= deadline + 1e-12 })
                .min(by: { $0.element.0 < $1.element.0 }) {
                time = next.element.0; wakes.remove(at: next.offset); next.element.1()
            }
            time = deadline
        }
    }

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
        // An open Bluetooth prompt does not spend the wait; Allow after it still pairs.
        let clock = ContinuousClock()
        let answeredAt = clock.now.advanced(by: .milliseconds(400))
        let allowedLate = await BleLink.waitForPower(
            timeout: .milliseconds(100), isPoweredOn: { clock.now >= answeredAt },
            awaitingPrompt: { clock.now < answeredAt })
        XCTAssertTrue(allowedLate)
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
