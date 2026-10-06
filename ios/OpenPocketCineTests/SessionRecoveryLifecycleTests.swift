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
        let driver = DjiAppleDatalink(port: 9, tcpPoke: false, pairingToken: "")
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
        let session = CameraSession()
        let peer = ConnectionDonorPeer(cached: true)
        defer { session.disconnect(); session.decoder.close(); withExtendedLifetime(peer) {} }
        guard await peer.admitExistingConnection(session) else { return }
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        guard session.startFeedRecovery({ _ in await withCheckedContinuation { first = $0 } }) else {
            XCTFail("Current real run must admit the first repair"); return
        }
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while first == nil, ContinuousClock.now < firstDeadline { await Task.yield() }
        guard first != nil else { XCTFail("First admitted repair must reach its manual wait"); return }
        session.resetFeedWatchdog()
        guard session.startFeedRecovery({ _ in await withCheckedContinuation { second = $0 } }) else {
            first?.resume(); XCTFail("Current real run must admit the replacement repair"); return
        }
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while second == nil, ContinuousClock.now < secondDeadline { await Task.yield() }
        guard second != nil else {
            first?.resume(); XCTFail("Replacement repair must reach its manual wait"); return
        }

        first?.resume()
        for _ in 0..<20 { await Task.yield() }
        var thirdStarted = false
        XCTAssertFalse(session.startFeedRecovery { _ in thirdStarted = true })
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(thirdStarted, "Old completion must not admit a competing repair")
        XCTAssertTrue(session.feedRecovering, "The second repair is still running")
        second?.resume()
        session.resetFeedWatchdog()
    }

    func testBluetoothPowerWaitEndsOnCancellationAndTimeout() async {
        let task = Task { await DjiAppleBluetoothLink.waitForPower(timeout: .seconds(30)) { false } }
        task.cancel()
        let canceled = await task.value
        XCTAssertFalse(canceled)
        let timeout = await DjiAppleBluetoothLink.waitForPower(timeout: .zero) { false }
        XCTAssertFalse(timeout)
        let ready = await DjiAppleBluetoothLink.waitForPower(timeout: .zero) { true }
        XCTAssertTrue(ready)
        // An open Bluetooth prompt does not spend the wait; Allow after it still pairs.
        let clock = ContinuousClock()
        let answeredAt = clock.now.advanced(by: .milliseconds(400))
        let allowedLate = await DjiAppleBluetoothLink.waitForPower(
            timeout: .milliseconds(100), isPoweredOn: { clock.now >= answeredAt },
            awaitingPrompt: { clock.now < answeredAt })
        XCTAssertTrue(allowedLate)
    }

    func testHotspotCallbackCancellationIgnoresLateSuccess() async {
        var callback: ((Result<Void, Error>) -> Void)?
        let task = Task {
            try await DjiAppleWiFiJoiner.awaitCallback(timeout: .seconds(30)) { callback = $0 }
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
            let _: Void = try await DjiAppleWiFiJoiner.awaitCallback(timeout: .zero) { _ in }
            XCTFail("A missing OS callback must exhaust its deadline")
        } catch DjiAppleWiFiJoiner.JoinError.timedOut {
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

    /// SIMULATED actual owned session, discovery and the original total180s deadline.
    func testRecoveryEpisodeDeadlineKeepsHeldFrameAndOffersOperatorRetry() async {
        let clock = SessionRecoveryDonorClock()
        let peer = ConnectionDonorPeer(cached: true)
        peer.recoveryClock = clock
        let session = await peer.establishedRecoverySession(clock: clock)
        defer { session.disconnect(); clock.cancelAll(); session.decoder.close() }
        peer.advertisesRecoveryCamera = false
        let started = clock.time
        session.beginSessionRecovery(reason: "SIMULATED native episode deadline")
        let finished = await clock.drive {
            if case .waitingForOperator = session.sessionRecovery { return true }; return false
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(clock.time - started, 180, accuracy: 1e-9)
        XCTAssertTrue(session.holdsMonitor)
        XCTAssertTrue(session.sessionRecoveryCardGraceElapsed)
        XCTAssertFalse(peer.trace.contains("GATT"))
    }

    /// SIMULATED real ConnectionRun misses preserve an actual native decoded image;
    /// the real unopened failed driver must close before the second advertisement scan.
    func testFailedAttemptReleasesTransportBeforeNextScanWhileHoldingPicture() async throws {
        let clock = SessionRecoveryDonorClock()
        let peer = ConnectionDonorPeer(cached: true)
        peer.recoveryClock = clock
        let session = await peer.establishedRecoverySession(clock: clock)
        let decoder = session.decoder
        let failedDriver = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        defer { session.disconnect(); clock.cancelAll(); failedDriver.close(); decoder.close() }
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        let presented = expectation(description: "Actual native held picture")
        let originalPresented = decoder.onPresentedFrame
        decoder.onPresentedFrame = { originalPresented?(); presented.fulfill() }
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer())
        await fulfillment(of: [presented], timeout: 2)
        decoder.onPresentedFrame = originalPresented
        let heldPicture = try XCTUnwrap(decoder.lastPresentedAt)
        peer.handshakeMisses = 6
        var installedDriver = false
        peer.onOpen = {
            if !installedDriver {
                installedDriver = true
                session.datalink = failedDriver
            }
        }
        var scans = 0
        peer.onRecoveryScan = {
            scans += 1
            if scans == 2 {
                XCTAssertTrue(failedDriver.isClosed, "Failed attempt closes before its next scan")
                XCTAssertNil(session.datalink)
                XCTAssertTrue(session.holdsMonitor)
                XCTAssertEqual(decoder.lastPresentedAt, heldPicture)
                XCTAssertFalse(decoder.displayedImageRemoved)
            }
        }
        peer.onRegistered = { clock.schedule(.milliseconds(1)) { peer.recoveryPicture = clock.freshPicture } }
        session.beginSessionRecovery(reason: "SIMULATED failed endpoint with native held picture")
        let finished = await clock.drive { session.sessionRecovery == .idle && !session.holdsMonitor }
        XCTAssertTrue(finished)
        XCTAssertTrue(installedDriver)
        XCTAssertEqual(scans, 2)
    }

}
