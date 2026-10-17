import Foundation
import Network
import Observation
import OpenCineDJIApple
import UIKit
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// SIMULATED OS services establish a real public ConnectionRun and bind the actual
/// loopback native endpoint. The DEBUG registered label supplies host phase only;
/// it never sends an enable or fabricates a camera/picture observation.
@MainActor
private func establishAdmittedLiveView(_ session: CameraSession, driver: DjiAppleDatalink,
    modelID: Int = 0x0022, policy: ConnectionDonorPeer,
    network: String? = nil,
    endpointProvider: (() -> DjiAppleDatalink)? = nil) async {
    XCTAssertFalse(session.isMultiviewBorrowed, "Fixture setup cannot promote a borrowed transport")
    guard !session.isMultiviewBorrowed else { return }
    policy.app = session
    var transport = policy.transport
    transport.makeEndpoint = { _, _, _ in endpointProvider?() ?? driver }
    session.connectionNativePeers = .init(transport: transport, timing: policy.timing,
        exchangeTiming: policy.exchangeTiming, currentEndpoint: { policy.current },
        attach: { [weak session] endpoint in
            policy.current = endpoint
            session?.datalink = endpoint as? DjiAppleDatalink
        }, registered: { [weak session] endpoint, attempt in
            XCTAssertTrue(attempt.isCurrent)
            XCTAssertTrue(endpoint === (endpointProvider?() ?? driver))
            policy.trace.append("registered SIMULATED host phase; no enable")
            session?.phase = .live
        }, ssid: network ?? policy.network, password: "SIMULATED-PASSWORD", stationNetwork: nil,
        persist: { _, _ in policy.trace.append("persist SIMULATED fixture only") }, forget: {})
    let camera = DjiAppleSighting(id: UUID(), name: "SIMULATED admitted live-view",
        model: .resolve(modelId: modelID, name: "SIMULATED admitted live-view"), modelId: modelID)
    session.connect(camera)
    let registered = ContinuousClock.now.advanced(by: .seconds(2))
    while session.phase != .live, ContinuousClock.now < registered { await Task.yield() }
    XCTAssertEqual(session.phase, .live, "Actual public connection must reach registered before measured recipe")
    XCTAssertTrue(policy.current === driver)
    XCTAssertNotNil(session.connectedCamera)
}

@MainActor
private final class LiveViewReplacementProbe {
    var replaced = false
    var endpoint: DjiAppleDatalink
    init(endpoint: DjiAppleDatalink) { self.endpoint = endpoint }
}

@MainActor
final class HandshakeBindTests: XCTestCase {
    private func performEndpointRepair(
        _ session: CameraSession, reason: String,
        pictureDeadline: Duration = .seconds(2 * CameraSoftAP.foregroundPictureGrace)
    ) async {
        await withCheckedContinuation { continuation in
            let admitted = session.startFeedRecovery { attempt in
                await session.repairDatalink(
                    reason: reason, pictureDeadline: pictureDeadline, attempt: attempt)
                continuation.resume()
            }
            if !admitted {
                XCTFail("Native endpoint regression must cross an admitted shared attempt")
                continuation.resume()
            }
        }
    }

    func testShortHandshakeAckCannotRegisterUntilTheInitialCommandWindowArrives() async throws {
        let peer = try EndpointPinnedCamera(holdInitialWindow: true)
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let opening = Task { try await driver.open() }
        defer {
            opening.cancel()
            driver.close()
            peer.stop()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while peer.snapshot.handshakes == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(peer.snapshot.handshakes, 0)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(
            peer.snapshot.registrations, 0, "A short ACK cannot seed registration at sequence 9")
        peer.releaseInitialWindow()
        try await opening.value
        let registeredDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while peer.snapshot.registrations == 0, ContinuousClock.now < registeredDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(peer.snapshot.registrationSequences, [0x6008])
    }

    func testRepairRetiresAnActiveAudioChainEvenWhenAnotherWorkItemOwnsItsTail() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession()
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
        }
        let admission = ConnectionDonorPeer(cached: true)
        await establishAdmittedLiveView(session, driver: driver, policy: admission)
        var refreshFinished = false
        let refresh = Task {
            await session.refreshAudioState()
            refreshFinished = true
        }
        let initialDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while peer.snapshot.cameraSettings == 0, ContinuousClock.now < initialDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(peer.snapshot.cameraSettings, 0)
        let queuedRefresh = Task { await session.refreshAudioState() }
        for _ in 0..<10 { await Task.yield() }
        peer.rejectNewHandshakes()
        let repair = Task { await performEndpointRepair(session, reason: "audio ownership regression") }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(peer.snapshot.unnegotiatedCommands, 0)
        XCTAssertTrue(refreshFinished, "Retired audio work must not install another request waiter")
        driver.close()
        repair.cancel()
        refresh.cancel()
        queuedRefresh.cancel()
        session.disconnect()
        await repair.value
        await refresh.value
        await queuedRefresh.value
    }

    func testRepairRetiresOldControlRetriesAndRequestWaitersBeforeNewHandshake() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession()
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
        }
        let admission = ConnectionDonorPeer(cached: true)
        await establishAdmittedLiveView(session, driver: driver, policy: admission)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        session.setWhiteBalanceCustom(kelvin: 5700, tint: 0)
        var waiterInstalled = false
        var waiterFinished = false
        let waiter = Task {
            defer { waiterFinished = true }
            _ = try? await session.waitFrame(2, 0xff, timeout: .seconds(3)) {
                waiterInstalled = true
            }
        }
        while !waiterInstalled { await Task.yield() }
        peer.rejectNewHandshakes()
        let repair = Task { await performEndpointRepair(session, reason: "command ownership regression") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while peer.snapshot.handshakes < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(
            peer.snapshot.unnegotiatedCommands, 0,
            "A pre-repair SET must not retry on a new endpoint before negotiation")
        XCTAssertTrue(waiterFinished, "Old request waiters cannot outlive their wire session")
        driver.close()
        repair.cancel()
        waiter.cancel()
        await repair.value
        await waiter.value
    }

    func testNegotiatedEndpointWithoutFreshPictureTransfersToSessionRecovery() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession()
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
        }
        let admission = ConnectionDonorPeer(cached: true)
        await establishAdmittedLiveView(session, driver: driver, policy: admission)
        _ = session.pictureRecovery.requestLiveView(
            .initial(pathProven: true, displayAttached: session.decoder.isDisplayReady),
            reason: "first picture")
        let initialDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while peer.snapshot.enables < 1, ContinuousClock.now < initialDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(peer.snapshot.enables, 1)
        await performEndpointRepair(session,
            reason: "picture regression", pictureDeadline: .milliseconds(40))
        XCTAssertTrue(session.holdsMonitor, "Handshake alone cannot release recovery ownership")
        XCTAssertTrue(session.sessionRecovery.isRecovering)
        XCTAssertTrue(driver.isClosed, "The failed picture attempt must release its transport")
        XCTAssertEqual(peer.snapshot.handshakes, 2)
        XCTAssertEqual(peer.snapshot.enables, 2, "No duplicate enable within one repair")
    }

    func testCancelledEndpointNegotiationCannotPublishSuccessOrKeepSending() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        defer {
            driver.close()
            peer.stop()
        }
        try await driver.open()
        driver.startLiveView()
        let initialDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while peer.snapshot.enables < 1, ContinuousClock.now < initialDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(peer.snapshot.enables, 1)
        peer.rejectNewHandshakes()
        let repair = Task { try await driver.rebuildUDP(reason: "cancel regression") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while peer.snapshot.handshakes < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(peer.snapshot.handshakes, 2)
        driver.keepalive()
        driver.send(Commands.setWhiteBalanceCustom(kelvin: 5600, tint: 0))
        driver.sendUntracked(Commands.setGimbalSpeed(.fast))
        try await Task.sleep(for: .milliseconds(40))
        driver.close()
        repair.cancel()
        do {
            try await repair.value
            XCTFail("Canceled negotiation cannot report success")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(driver.isRebuilding)
        XCTAssertEqual(peer.snapshot.registrations, 1)
        XCTAssertEqual(peer.snapshot.enables, 1)
        XCTAssertEqual(peer.snapshot.unnegotiatedCommands, 0)
    }

    func testUDPRepairRenegotiatesPeerDestinationBeforeResumingLive() async throws {
        let peer = try EndpointPinnedCamera()
        let port = try await peer.start()
        let driver = DjiAppleDatalink.loopbackForTesting(port: port)
        defer {
            driver.close()
            peer.stop()
        }
        try await driver.open()
        driver.startLiveView()
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while driver.lastStatusAt == nil || peer.snapshot.enables < 1,
            ContinuousClock.now < firstDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(driver.lastStatusAt, "Initial negotiated endpoint receives the peer")
        XCTAssertEqual(peer.snapshot.handshakes, 1)

        try await driver.rebuildUDP(reason: "endpoint regression")
        driver.startLiveView()  // the shell owns exactly one enable after repair
        let repairedDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while driver.lastStatusAt == nil || peer.snapshot.enables < 2,
            ContinuousClock.now < repairedDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        let result = peer.snapshot
        XCTAssertEqual(result.handshakes, 2, "A new local endpoint must renegotiate")
        XCTAssertEqual(result.registrations, 2)
        XCTAssertEqual(result.enables, 2, "One enable per negotiated session")
        XCTAssertNotNil(
            driver.lastStatusAt,
            "The camera keeps sending to its old peer until a new handshake retargets it")
    }

    /// A replacement bind must invalidate the old socket's receive callbacks before
    /// reset, or an already armed old ACK re-registers; a first bind must not discard.
    func testHandshakeBindDiscardsOnlyAnExistingSocketAndBeforeReset() {
        let cases: [(name: String, socket: NWConnection?, calls: [String])] = [
            ("first bind", nil, ["reset"]),
            (
                "replacement bind", NWConnection(host: "127.0.0.1", port: 9004, using: .udp),
                ["discard", "reset"]
            ),
        ]
        for testCase in cases {
            var calls: [String] = []
            DjiAppleDatalink.prepareHandshakeBind(
                existingSocket: testCase.socket,
                discard: { calls.append("discard") },
                reset: { calls.append("reset") })
            XCTAssertEqual(calls, testCase.calls, testCase.name)
        }
    }
}

/// Migrated SIMULATED fixtures on real Network.framework UDP exercise the current
/// live-view adopter through a public run. Original donor bytes/traces are archived
/// separately; these cases do not qualify a physical camera.
@MainActor
final class LiveEnableDonorTests: XCTestCase {
    private func bind(_ modelID: Int, session: CameraSession, driver: DjiAppleDatalink,
        borrowed: Bool = false, policy: ConnectionDonorPeer? = nil, network: String? = nil) async {
        if borrowed {
            XCTAssertTrue(session.isMultiviewBorrowed, "Borrowed contract requires a genuinely borrowed session")
            guard session.isMultiviewBorrowed else { return }
            session.updateMultiview(camera: DjiAppleSighting(id: UUID(), name: "SIMULATED borrowed",
                model: .resolve(modelId: modelID, name: "SIMULATED borrowed"), modelId: modelID),
                driver: driver, status: CameraStatus())
            do { try await driver.open() }
            catch { XCTFail("SIMULATED borrowed transport setup failed: \(error)") }
            return
        }
        await establishAdmittedLiveView(session, driver: driver, modelID: modelID,
            policy: policy ?? ConnectionDonorPeer(cached: true), network: network)
    }

    private func fence(_ driver: DjiAppleDatalink, peer: EndpointPinnedCamera) async {
        // An explicit known read reaches the same serialized UDP queue after the
        // operation. The peer observes it; a negative assertion cannot use a dead sink.
        // This read is fixture-owned and excluded from live recipe comparisons.
        let probe = Commands.getIsoLimit()
        let arrived = expectation(description: "SIMULATED explicit UDP read fence")
        peer.observeNext(probe) { arrived.fulfill() }
        XCTAssertNotEqual(driver.send(probe), 0)
        await fulfillment(of: [arrived], timeout: 2)
    }

    private func recipe(_ frames: [Duml.Frame]) -> [String] {
        frames.filter {
            ($0.cmdSet == 2 && ($0.cmdId == 0x09 || $0.cmdId == 0x68))
                || ($0.cmdSet == 9 && $0.cmdId == 0xa8)
        }.map { "\($0.cmdSet)/\($0.cmdId) receiver=\($0.receiver) payload=\(Duml.hex($0.payload))" }
    }

    private func trace(_ label: String, peer: EndpointPinnedCamera) {
        print("SIMULATED LIVE ENABLE DONOR \(label): \(recipe(peer.snapshot.commands))")
    }

    func testPocketDonorPreparesBeforeOneUDPEnable() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let policy = ConnectionDonorPeer(cached: true)
        // capturedRecipe does not mark initial history, so hold the independent monitor's
        // manual wake for this migrated direct-recipe comparison. Initial/native cadence
        // remain exercised below with their original clocks.
        let session = CameraSession(heartbeatTiming: policy.heartbeatTiming)
        await bind(0x0022, session: session, driver: driver, policy: policy)
        defer { session.disconnect(); driver.close(); peer.stop() }
        XCTAssertTrue(session.startCapturedLiveView(reason: "SIMULATED donor Pocket"))
        await fence(driver, peer: peer)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08)]))
        XCTAssertEqual(peer.snapshot.enables, 1)
        trace("Pocket", peer: peer)
    }

    func testNanoDonorPairsItsGateWithEnableWithoutPocketPrepare() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let policy = ConnectionDonorPeer(cached: true)
        // Isolate this migrated direct recipe without advancing its monitor wake.
        let session = CameraSession(heartbeatTiming: policy.heartbeatTiming)
        await bind(0x0019, session: session, driver: driver, policy: policy,
            network: "OsmoNano-SIMULATED")
        defer { session.disconnect(); driver.close(); peer.stop() }
        XCTAssertTrue(session.startCapturedLiveView(reason: "SIMULATED donor Nano"))
        await fence(driver, peer: peer)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.nanoLiveViewGate(start: true),
            Commands.liveViewEnable(seq: 0, receiver: 0x41)]))
        XCTAssertEqual(peer.snapshot.enables, 1)
        trace("Nano", peer: peer)
    }

    func testActionSixDonorUsesCapturedReceiverWithoutEitherPreparation() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let policy = ConnectionDonorPeer(cached: true)
        // Isolate this migrated direct recipe without advancing its monitor wake.
        let session = CameraSession(heartbeatTiming: policy.heartbeatTiming)
        await bind(0x0018, session: session, driver: driver, policy: policy)
        defer { session.disconnect(); driver.close(); peer.stop() }
        XCTAssertTrue(session.startCapturedLiveView(reason: "SIMULATED donor Action6"))
        await fence(driver, peer: peer)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.liveViewEnable(seq: 0, receiver: 0x41)]))
        XCTAssertEqual(peer.snapshot.enables, 1)
        trace("Action6", peer: peer)
    }

    func testKnownUncapturedDonorRefusesWithoutARecipeWrite() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession()
        await bind(0x0017, session: session, driver: driver)
        defer { session.disconnect(); driver.close(); peer.stop() }
        XCTAssertFalse(session.startCapturedLiveView(reason: "SIMULATED uncaptured donor"))
        await fence(driver, peer: peer)
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        XCTAssertEqual(peer.snapshot.enables, 0)
        XCTAssertEqual(session.controlNote, "Live view for this camera is not captured yet.")
        trace("known uncaptured", peer: peer)
    }

    // Historical nil-model wire donor is preserved outside source. The actual
    // app connect API requires a model; public owner nil-recipe/real-run coverage
    // lives in DJIAppleLiveViewTests without clearing private app observations.

    func testMediaGateBlocksOrdinaryEnableAndRetainsExplicitReturnException() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession()
        await bind(0x0022, session: session, driver: driver)
        defer { session.disconnect(); driver.close(); peer.stop() }
        session.isBrowsingMedia = true
        XCTAssertFalse(session.startCapturedLiveView(reason: "SIMULATED watchdog"))
        await fence(driver, peer: peer)
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        XCTAssertTrue(session.startCapturedLiveView(reason: "media browse ended"))
        await fence(driver, peer: peer)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08)]))
        XCTAssertEqual(peer.snapshot.enables, 1)
        trace("media gate and explicit return", peer: peer)
    }

    func testLegacyLocalAcceptanceWithoutAnEndpointIsNotWireEvidence() {
        let session = CameraSession()
        XCTAssertFalse(session.isMultiviewBorrowed)
        defer { session.disconnect() }
        XCTAssertNil(session.datalink)
        XCTAssertNil(session.connectedCamera)
        XCTAssertTrue(session.startCapturedLiveView(reason: "SIMULATED legacy missing endpoint"))
        XCTAssertNil(session.datalink)
        XCTAssertNil(session.connectedCamera)
        print("SIMULATED LIVE ENABLE DONOR missing endpoint: localBool=true; wire evidence absent")
    }

    /// SIMULATED OS policy and manual timing with actual public connection admission,
    /// UDP/native picture facts, and an explicitly labeled registered host phase.
    private func timedSession(_ clock: SessionRecoveryDonorClock,
        wallNow: @escaping () -> TimeInterval, recordWait: ((Duration) -> Void)? = nil) -> (CameraSession, ConnectionDonorPeer) {
        let policy = ConnectionDonorPeer(cached: true)
        policy.recoveryClock = clock
        let timing = DjiApplePictureRecoveryTiming(wallNow: wallNow,
            monotonicNow: { clock.time }, wait: { recordWait?($0); try await clock.pause($0) })
        let heartbeat = DjiAppleHeartbeatTiming(wallNow: wallNow, uptime: { clock.time },
            schedule: { clock.schedule($0, $1) })
        let session = CameraSession(heartbeatTiming: heartbeat,
            pictureRecoveryTiming: timing)
        session.liveViewDonorTiming = timing
        return (session, policy)
    }

    /// The real programmed-motion teardown notification replaces A through the
    /// public connect API. A must stop before touching B or submitting its recipe.
    func testRecoverNativeCleanupCannotWriteOrClearSuccessorsFacts() async throws {
        let clock = SessionRecoveryDonorClock()
        let wallOrigin = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time })
        let oldPeer = try EndpointPinnedCamera()
        let newPeer = try EndpointPinnedCamera()
        let oldDriver = DjiAppleDatalink.loopbackForTesting(port: try await oldPeer.start())
        let newDriver = DjiAppleDatalink.loopbackForTesting(port: try await newPeer.start())
        let probe = LiveViewReplacementProbe(endpoint: oldDriver)
        await establishAdmittedLiveView(session, driver: oldDriver, policy: policy,
            endpointProvider: { probe.endpoint })
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); oldDriver.close(); newDriver.close()
            oldPeer.stop(); newPeer.stop(); session.decoder.close()
            withExtendedLifetime((policy, display)) {}
        }
        let successor = DjiAppleSighting(id: UUID(), name: "SIMULATED successor live-view",
            model: .resolve(modelId: 0x0022, name: "SIMULATED successor live-view"), modelId: 0x0022)
        session.gimbalMoveRunning = true
        session.gimbalMovePaused = true
        withObservationTracking { _ = session.gimbalMovePaused } onChange: {
            MainActor.assumeIsolated {
                guard !probe.replaced else { return }
                probe.replaced = true
                probe.endpoint = newDriver
                session.connect(successor)
                // Actual native B sentinel; the new public run adopts it on its
                // next turn. No camera report, readiness or wire receipt is invented.
                session.datalink = newDriver
                policy.current = newDriver
                session.gimbalMoveCanPause = true
                session.status.meteredEv = EvComp(thirds: 7)
            }
        }
        XCTAssertFalse(session.donorRecoverLiveView(force: true, reason: "SIMULATED retired A"))
        XCTAssertTrue(probe.replaced)
        XCTAssertEqual(session.connectedCamera?.id, successor.id)
        XCTAssertTrue(session.datalink === newDriver)
        XCTAssertFalse(newDriver.isClosed)
        XCTAssertTrue(oldDriver.isClosed)
        XCTAssertTrue(session.gimbalMoveCanPause, "A cannot clear the native B sentinel after the observer returns")
        XCTAssertEqual(session.status.meteredEv, EvComp(thirds: 7))
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 0)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime, .distantPast)
        XCTAssertFalse(session.liveViewDonorHistory.gateInFlight)
        XCTAssertTrue(recipe(oldPeer.snapshot.commands).isEmpty)
        XCTAssertTrue(recipe(newPeer.snapshot.commands).isEmpty)
        let registered = ContinuousClock.now.advanced(by: .seconds(2))
        while session.phase != .live, ContinuousClock.now < registered { await Task.yield() }
        XCTAssertEqual(session.phase, .live, "B must finish the same real public admission spine")
        XCTAssertTrue(policy.current === newDriver)
        XCTAssertTrue(session.startCapturedLiveView(reason: "SIMULATED admitted B"))
        await fence(newDriver, peer: newPeer)
        XCTAssertEqual(newPeer.snapshot.enables, 1)
        XCTAssertTrue(recipe(oldPeer.snapshot.commands).isEmpty)
        trace("observable retired A/current B", peer: newPeer)
    }

    /// Real repair negotiation reaches native.enable and the unchanged initial body.
    /// Early real heartbeat maintenance proves no duplicate initial write, not8s cadence.
    func testActualEndpointRepairExecutesInitialOnceAcrossEarlyMaintenance() async throws {
        let clock = SessionRecoveryDonorClock()
        let wallOrigin = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime(policy) {}
        }
        XCTAssertFalse(session.liveViewDonorHistory.initialAccepted)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime, .distantPast)
        let enabled = expectation(description: "SIMULATED actual repair peer receives initial enable")
        peer.observeNext(Commands.liveViewEnable(seq: 0, receiver: 0x08)) { enabled.fulfill() }
        XCTAssertTrue(session.startFeedRecovery { attempt in
            await session.repairDatalink(reason: "SIMULATED initial timing donor", attempt: attempt)
        })
        await fulfillment(of: [enabled], timeout: 2)
        await clock.settle()
        XCTAssertTrue(session.liveViewDonorHistory.initialAccepted)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime.timeIntervalSinceReferenceDate,
            wallOrigin, accuracy: 1e-9)
        XCTAssertEqual(session.liveViewDonorHistory.idrHoldEnableCount, 1)
        XCTAssertFalse(session.liveViewDonorHistory.gateInFlight)
        session.pictureRecovery.cancel()
        clock.cancelAll()
        await clock.settle()
        session.startKeepalive(ssid: "SIMULATED early maintenance")
        clock.advance(to: 2)
        await clock.settle()
        await fence(driver, peer: peer)
        XCTAssertEqual(peer.snapshot.enables, 1)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1)
        XCTAssertTrue(session.liveViewDonorHistory.initialAccepted)
        trace("actual initial repair plus early maintenance", peer: peer)
    }

    func testForcedRecoverBypassesCooldownButUnforcedWaitsUntilFiveSeconds() async throws {
        let clock = SessionRecoveryDonorClock()
        let wallOrigin = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime((policy, display)) {}
        }
        XCTAssertTrue(session.decoder.isPresentationReady, "Actual laid-out native host, no readiness override")
        XCTAssertTrue(session.donorRecoverLiveView(force: false, reason: "SIMULATED first recover"))
        clock.advance(to: 1)
        XCTAssertTrue(session.donorRecoverLiveView(force: true, reason: "SIMULATED forced recover"))
        clock.advance(to: 5.999)
        XCTAssertFalse(session.donorRecoverLiveView(force: false, reason: "SIMULATED before cooldown"))
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 2)
        clock.advance(to: 6)
        XCTAssertTrue(session.donorRecoverLiveView(force: false, reason: "SIMULATED exact cooldown"))
        await fence(driver, peer: peer)
        XCTAssertEqual(peer.snapshot.enables, 3)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 3)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime.timeIntervalSinceReferenceDate,
            wallOrigin + 6, accuracy: 1e-9)
        XCTAssertFalse(session.liveViewDonorHistory.initialAccepted, "Recover does not fabricate initial acceptance")
        trace("forced and five-second boundary", peer: peer)
    }

    func testCooldownUsesWallClockWhileWaitClockStaysStill() async throws {
        let clock = SessionRecoveryDonorClock()
        var wall = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wall })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime((policy, display)) {}
        }
        XCTAssertTrue(session.donorRecoverLiveView(force: false, reason: "SIMULATED wall-clock first"))
        wall += 4
        XCTAssertFalse(session.donorRecoverLiveView(force: false, reason: "SIMULATED wall-clock before"))
        wall += 1
        XCTAssertTrue(session.donorRecoverLiveView(force: false, reason: "SIMULATED wall-clock boundary"))
        await fence(driver, peer: peer)
        XCTAssertEqual(clock.time, 0, "Original cooldown is wall time, independently of monotonic waits")
        XCTAssertEqual(peer.snapshot.enables, 2)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime.timeIntervalSinceReferenceDate, wall)
        trace("wall time independently of wait clock", peer: peer)
    }

    func testDetachedNativeHostBlocksRecoverWithoutSpendingHistory() async throws {
        let clock = SessionRecoveryDonorClock()
        let wallOrigin = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime(policy) {}
        }
        XCTAssertFalse(session.decoder.isPresentationReady, "Actual zero-sized/unattached layer")
        XCTAssertFalse(session.donorRecoverLiveView(force: true, reason: "SIMULATED detached native host"))
        await fence(driver, peer: peer)
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 0)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime, .distantPast)
        XCTAssertFalse(session.liveViewDonorHistory.gateInFlight)
        trace("actual native readiness refusal", peer: peer)
    }

    func testClosedEndpointPreservesLegacyLocalAcceptanceWithoutReceipt() async throws {
        let clock = SessionRecoveryDonorClock()
        let wallOrigin = Date.timeIntervalSinceReferenceDate
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime((policy, display)) {}
        }
        await fence(driver, peer: peer)
        driver.close()
        XCTAssertTrue(driver.isClosed)
        XCTAssertTrue(session.donorRecoverLiveView(force: true, reason: "SIMULATED closed endpoint donor"))
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime.timeIntervalSinceReferenceDate, wallOrigin)
        XCTAssertEqual(peer.snapshot.enables, 0)
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        trace("closed endpoint local acceptance, no receipt", peer: peer)
    }

    private enum NativeDonorFixtureError: Error {
        case pictureNotEstablished
        case referenceLossNotEstablished
        case repairNotAdmitted
    }

    /// SIMULATED encoded bytes cross the real UDP assembler, VT and native host.
    /// Await both actual decoded-source and presentation events, never submission alone.
    private func establishNativePicture(_ session: CameraSession, driver: DjiAppleDatalink,
        peer: EndpointPinnedCamera) async throws -> Date {
        let decoder = session.decoder
        decoder.effects.histogram = true
        decoder.unlockHardwareDecoder()
        let output = expectation(description: "SIMULATED HEVC produces a native source lease")
        let presented = expectation(description: "SIMULATED HEVC reaches native presentation")
        var sawOutput = false
        var sawPresentation = false
        let originalSource = decoder.onSourceFrame
        let originalPresented = decoder.onPresentedFrame
        decoder.onSourceFrame = { lease in
            originalSource?(lease)
            if !sawOutput { sawOutput = true; output.fulfill() }
        }
        decoder.onPresentedFrame = {
            originalPresented?()
            if !sawPresentation { sawPresentation = true; presented.fulfill() }
        }
        defer {
            decoder.onSourceFrame = originalSource
            decoder.onPresentedFrame = originalPresented
        }
        // This borrowed decoder has no source-owner callback installed by the
        // CameraSession initializer. Bind real encoded delivery explicitly;
        // transport ownership still belongs to this fixture's actual driver.
        driver.onAccessUnit = { [weak decoder] in _ = decoder?.decode(accessUnit: $0) }
        XCTAssertTrue(peer.sendVideo([
            HevcFixture.packet(0, HevcFixture.keyframe),
            HevcFixture.packet(1, HevcFixture.pFrame)]))
        await fulfillment(of: [output, presented], timeout: 3)
        XCTAssertGreaterThan(driver.accessUnits, 0)
        XCTAssertNotNil(driver.lastVideoPacketAt)
        XCTAssertNotNil(driver.lastAccessUnitAt)
        XCTAssertGreaterThan(decoder.incidentDecodeSnapshot.output, 0)
        XCTAssertNotNil(decoder.lastSourceFrameAt)
        XCTAssertNotNil(decoder.lastIrapAt)
        XCTAssertTrue(decoder.canReleaseIDRHold)
        XCTAssertTrue(decoder.nativeOutputExpected)
        XCTAssertTrue(decoder.isPresentationReady)
        XCTAssertNil(driver.secondsSinceLastCommand,
            "No tracked liveness read may create SET grace before watchdog admission")
        guard sawOutput, sawPresentation, decoder.incidentDecodeSnapshot.output > 0,
            decoder.lastSourceFrameAt != nil, decoder.lastIrapAt != nil,
            decoder.canReleaseIDRHold, decoder.nativeOutputExpected, decoder.isPresentationReady,
            driver.secondsSinceLastCommand == nil
        else { throw NativeDonorFixtureError.pictureNotEstablished }
        print("SIMULATED NATIVE SOURCE videoPackets=\(driver.videoPackets) accessUnits=\(driver.accessUnits) "
            + "output=\(decoder.incidentDecodeSnapshot.output) "
            + "source=\(String(describing: decoder.lastSourceFrameAt)) "
            + "presented=\(String(describing: decoder.lastPresentedAt)) "
            + "irap=\(String(describing: decoder.lastIrapAt)) ready=\(decoder.isPresentationReady)")
        return try XCTUnwrap(decoder.lastPresentedAt)
    }

    /// Missing fragment 1 corrupts the pending P-frame. A later group makes the
    /// real assembler report discontinuity; dependent P-frames cannot repair it.
    private func deliverNativeReferenceLoss(_ session: CameraSession,
        driver: DjiAppleDatalink, peer: EndpointPinnedCamera) async throws {
        let lost = expectation(description: "SIMULATED UDP fragment gap reports reference loss")
        var reported = false
        let original = driver.onVideoDiscontinuity
        driver.onVideoDiscontinuity = {
            original?()
            session.decoder.noteCompressedDiscontinuity()
            if !reported { reported = true; lost.fulfill() }
        }
        defer { driver.onVideoDiscontinuity = original }
        var skippedFragment = HevcFixture.packet(1, HevcFixture.pFrame)
        skippedFragment[18] = 1 // Position 2 after position 0, skipping position 1.
        XCTAssertTrue(peer.sendVideo([
            skippedFragment, HevcFixture.packet(2, HevcFixture.pFrame),
            HevcFixture.packet(3, HevcFixture.pFrame)]))
        await fulfillment(of: [lost], timeout: 2)
        XCTAssertTrue(session.decoder.referenceRecoveryNeeded)
        XCTAssertTrue(session.decoder.awaitingIDR)
        XCTAssertFalse(session.decoder.canReleaseIDRHold)
        XCTAssertTrue(session.decoder.nativeOutputExpected)
        guard reported, session.decoder.referenceRecoveryNeeded,
            session.decoder.awaitingIDR, !session.decoder.canReleaseIDRHold,
            session.decoder.nativeOutputExpected
        else { throw NativeDonorFixtureError.referenceLossNotEstablished }
    }

    func testNativeRepairPollsDetachedHostEvery250msUntilReadinessDeadline() async throws {
        let clock = SessionRecoveryDonorClock()
        var wallOrigin = Date.timeIntervalSinceReferenceDate
        var nativeWaits: [Duration] = []
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time },
            recordWait: { nativeWaits.append($0) })
        let peer = try EndpointPinnedCamera(initialHandshakesToIgnore: 1)
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime((policy, display)) {}
        }
        let heldPicture = try await establishNativePicture(session, driver: driver, peer: peer)
        try await deliverNativeReferenceLoss(session, driver: driver, peer: peer)
        // Wall samples remain wall time. Native AU/output/presentation times
        // are untouched; known loss, not artificial output aging, admits repair.
        wallOrigin = Date.timeIntervalSinceReferenceDate
        let handshakesBeforeRepair = peer.snapshot.handshakes
        XCTAssertEqual(handshakesBeforeRepair, 2, "SIMULATED initial handshake retry is established")
        session.startKeepalive(ssid: "SIMULATED actual native readiness donor")
        clock.advance(to: 0)
        XCTAssertEqual(session.liveViewDonorHistory.watchdogStage, .rebuildVT)
        XCTAssertTrue(session.pictureRecovery.isBusy)
        guard session.liveViewDonorHistory.watchdogStage == .rebuildVT,
            session.pictureRecovery.isBusy else { throw NativeDonorFixtureError.repairNotAdmitted }
        // Selection was made while the actual host was ready. Detach geometry
        // before the admitted MainActor repair task starts its readiness loop.
        display.frame = .zero; display.layoutSubviews()
        XCTAssertFalse(session.decoder.isDisplayReady)
        session.sessionHeartbeat.stop()
        await clock.settle()
        XCTAssertEqual(nativeWaits, [.milliseconds(250)])
        XCTAssertTrue(session.pictureRecovery.isBusy)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 0)
        let beforeDeadline = await clock.drive {
            clock.time >= FeedWatchdog.decoderRepairDeadline - 0.25
        }
        XCTAssertTrue(beforeDeadline)
        XCTAssertEqual(clock.time, FeedWatchdog.decoderRepairDeadline - 0.25, accuracy: 1e-9)
        XCTAssertTrue(session.pictureRecovery.isBusy, "Last readiness wait still owns the repair")
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 0)
        let finished = await clock.drive { !session.pictureRecovery.isBusy }
        XCTAssertTrue(finished)
        XCTAssertEqual(nativeWaits, Array(repeating: .milliseconds(250), count: 64))
        XCTAssertEqual(clock.time, FeedWatchdog.decoderRepairDeadline, accuracy: 1e-9)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 0)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime, .distantPast)
        XCTAssertFalse(session.liveViewDonorHistory.initialAccepted)
        XCTAssertFalse(session.liveViewDonorHistory.gateInFlight)
        XCTAssertEqual(session.liveViewDonorHistory.watchdogStage, .rebuildVT)
        XCTAssertEqual(session.decoder.lastPresentedAt, heldPicture)
        XCTAssertFalse(session.decoder.displayedImageRemoved)
        XCTAssertEqual(peer.snapshot.handshakes, handshakesBeforeRepair,
            "Detached-display repair must not renegotiate the established endpoint")
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        XCTAssertEqual(peer.snapshot.enables, 0)
        print("SIMULATED NATIVE REPAIR readiness: waits=\(nativeWaits) "
            + "elapsed=\(clock.time) localEnables=0 peerEnables=0 "
            + "endpointHandshakes=\(peer.snapshot.handshakes) initialHandshakes=\(handshakesBeforeRepair)")
    }

    func testNativeRepairPollsEvery100msThenRenegotiatesAfterTwoUnansweredRequests() async throws {
        let clock = SessionRecoveryDonorClock()
        var wallOrigin = Date.timeIntervalSinceReferenceDate
        var nativeWaits: [Duration] = []
        let (session, policy) = timedSession(clock, wallNow: { wallOrigin + clock.time },
            recordWait: { nativeWaits.append($0) })
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        await bind(0x0022, session: session, driver: driver, policy: policy)
        let display = DisplayLayerView(session.decoder.displayLayer)
        display.frame = CGRect(x: 0, y: 0, width: 64, height: 64); display.layoutSubviews()
        defer {
            session.disconnect(); clock.cancelAll(); driver.close(); peer.stop()
            withExtendedLifetime((policy, display)) {}
        }
        _ = try await establishNativePicture(session, driver: driver, peer: peer)
        try await deliverNativeReferenceLoss(session, driver: driver, peer: peer)
        wallOrigin = Date.timeIntervalSinceReferenceDate
        let first = expectation(description: "SIMULATED native repair first actual enable")
        peer.observeNext(Commands.liveViewEnable(seq: 0, receiver: 0x08)) { first.fulfill() }
        session.startKeepalive(ssid: "SIMULATED actual native keyframe donor")
        clock.advance(to: 0)
        XCTAssertEqual(session.liveViewDonorHistory.watchdogStage, .rebuildVT)
        XCTAssertTrue(session.pictureRecovery.isBusy)
        guard session.liveViewDonorHistory.watchdogStage == .rebuildVT,
            session.pictureRecovery.isBusy else { throw NativeDonorFixtureError.repairNotAdmitted }
        session.sessionHeartbeat.stop()
        await fulfillment(of: [first], timeout: 2)
        await clock.settle()
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1)
        XCTAssertEqual(peer.snapshot.enables, 1)
        XCTAssertEqual(nativeWaits, [.milliseconds(100)])

        let second = expectation(description: "SIMULATED unanswered repair second actual enable")
        peer.observeNext(Commands.liveViewEnable(seq: 0, receiver: 0x08)) { second.fulfill() }
        let beforeSecond = await clock.drive {
            clock.time >= FeedWatchdog.keyframeResendInterval - 0.1 - 1e-9
        }
        XCTAssertTrue(beforeSecond)
        XCTAssertEqual(clock.time, FeedWatchdog.keyframeResendInterval - 0.1, accuracy: 1e-6)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1)
        XCTAssertEqual(peer.snapshot.enables, 1)
        let resent = await clock.drive { session.liveViewDonorHistory.locallyAcceptedEnables == 2 }
        XCTAssertTrue(resent)
        await fulfillment(of: [second], timeout: 2)
        let secondAt = clock.time
        XCTAssertEqual(secondAt, FeedWatchdog.keyframeResendInterval, accuracy: 1e-6)
        XCTAssertEqual(session.liveViewDonorHistory.lastEnableWallTime.timeIntervalSinceReferenceDate,
            wallOrigin + secondAt, accuracy: 1e-6)
        XCTAssertEqual(peer.snapshot.handshakes, 1)
        XCTAssertEqual(peer.snapshot.enables, 2)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08),
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08)]))

        let replacement = expectation(description: "SIMULATED negotiated replacement initial enable")
        peer.observeNext(Commands.liveViewEnable(seq: 0, receiver: 0x08)) { replacement.fulfill() }
        let beforeEndpoint = await clock.drive {
            clock.time >= secondAt + FeedWatchdog.keyframeResendInterval - 0.1 - 1e-9
        }
        XCTAssertTrue(beforeEndpoint)
        XCTAssertEqual(clock.time, 2 * FeedWatchdog.keyframeResendInterval - 0.1, accuracy: 1e-6)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 2)
        XCTAssertEqual(peer.snapshot.handshakes, 1)
        // Real native preparation clears the old count before negotiation;
        // observe that durable boundary rather than racing isRebuilding's lifetime.
        let preparedEndpoint = await clock.drive {
            session.liveViewDonorHistory.locallyAcceptedEnables != 2
        }
        XCTAssertTrue(preparedEndpoint)
        let endpointAt = clock.time
        let repairPauses = nativeWaits
        XCTAssertEqual(endpointAt, 2 * FeedWatchdog.keyframeResendInterval, accuracy: 1e-6)
        XCTAssertEqual(repairPauses, Array(repeating: .milliseconds(100), count: 40))
        await fulfillment(of: [replacement], timeout: 2)
        XCTAssertEqual(peer.snapshot.handshakes, 2, "Actual native negotiation, not an injected callback label")
        XCTAssertEqual(peer.snapshot.enables, 3)
        XCTAssertEqual(recipe(peer.snapshot.commands), recipe([
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08),
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08),
            Commands.liveViewPrepare(), Commands.liveViewEnable(seq: 0, receiver: 0x08)]))
        XCTAssertTrue(session.liveViewDonorHistory.initialAccepted)
        XCTAssertEqual(session.liveViewDonorHistory.locallyAcceptedEnables, 1,
            "Real endpoint preparation resets history before its new initial enable")
        session.pictureRecovery.cancel()
        clock.cancelAll()
        await clock.settle()
        XCTAssertFalse(session.pictureRecovery.isBusy)
        print("SIMULATED NATIVE REPAIR keyframe: waits=\(repairPauses) secondAt=\(secondAt) "
            + "endpointAt=\(endpointAt) peerEnables=3 endpointHandshakes=2")
    }

    /// Intended owner contract whose original donor red is archived separately:
    /// borrowing a transport must never admit its own live repair.
    /// Direct public-body admission is tested; no claim about a natural UI trigger.
    func testBorrowedTransportMustRefuseItsOwnLiveEnable() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession(borrowing: HevcDecoder())
        await bind(0x0022, session: session, driver: driver, borrowed: true)
        defer { session.releaseMultiview(); driver.close(); peer.stop() }
        let admitted = session.startCapturedLiveView(reason: "SIMULATED borrowed contract")
        await fence(driver, peer: peer)
        XCTAssertFalse(admitted, "A borrowed transport must not become the repair owner")
        XCTAssertTrue(recipe(peer.snapshot.commands).isEmpty)
        XCTAssertEqual(peer.snapshot.enables, 0)
        trace("intended borrowed contract", peer: peer)
    }
}

/// A UDP peer with the endpoint behavior observed in the physical capture:
/// ACK/presence from a new endpoint do not retarget its existing session.
private final class EndpointPinnedCamera: @unchecked Sendable {
    struct Snapshot {
        var handshakes = 0
        var registrations = 0
        var registrationSequences: [UInt16] = []
        var enables = 0
        var cameraSettings = 0
        var unnegotiatedCommands = 0
        var commands: [Duml.Frame] = []
    }
    private let queue = DispatchQueue(label: "test.endpoint-pinned-camera")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var peer: NWConnection?
    private var registered = false
    private var subscribed = false
    private var counts = Snapshot()
    private var rejectingHandshakes = false
    private let initialHandshakesToIgnore: Int
    private var holdInitialWindow: Bool
    private var nextObservedCommand: (Duml.Frame, @Sendable () -> Void)?

    init(holdInitialWindow: Bool = false, initialHandshakesToIgnore: Int = 0) throws {
        self.holdInitialWindow = holdInitialWindow
        self.initialHandshakesToIgnore = initialHandshakesToIgnore
        listener = try NWListener(using: .udp)
    }

    func releaseInitialWindow() {
        queue.sync {
            holdInitialWindow = false
            if let peer { sendInitialWindow(to: peer) }
        }
    }

    private func sendInitialWindow(to connection: NWConnection) {
        let payload = DumlTransport.ackPayload(peerCursor: 0x6000, baseSeq: 0x6000)
        let packet =
            DumlTransport.transportHeader(
                pktType: 1, payloadLen: payload.count, sessionId: 1, seq: 8) + payload
        connection.send(content: Data(packet), completion: .idempotent)
    }
    var snapshot: Snapshot { queue.sync { counts } }
    func rejectNewHandshakes() { queue.sync { rejectingHandshakes = true } }

    /// Event-driven fence for new donor cases; existing peer behavior is unchanged.
    func observeNext(_ frame: Duml.Frame, completion: @escaping @Sendable () -> Void) {
        queue.sync { nextObservedCommand = (frame, completion) }
    }

    /// Synthetic encoded datagrams only; receive/assembly/decode/present remain real.
    func sendVideo(_ packets: [[UInt8]]) -> Bool {
        queue.sync {
            guard let peer else { return false }
            for packet in packets { peer.send(content: Data(packet), completion: .idempotent) }
            return true
        }
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: self.listener.port!.rawValue)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections { connection.cancel() }
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { return }
            self.consume(Array(data), from: connection)
            self.receive(connection)
        }
    }

    private func consume(_ bytes: [UInt8], from connection: NWConnection) {
        if DumlTransport.isHandshake(bytes) {
            counts.handshakes += 1
            if counts.handshakes <= initialHandshakesToIgnore { return }
            if rejectingHandshakes { return }
            peer = connection
            registered = false
            subscribed = false
            // Real Pocket ACK is 15 bytes; it does not contain command window.
            let reply =
                DumlTransport.transportHeader(
                    pktType: 0, payloadLen: 7, sessionId: 1, seq: 0) + [1, 0, 0, 0, 0, 0, 0]
            connection.send(content: Data(reply), completion: .idempotent)
            if !holdInitialWindow { sendInitialWindow(to: connection) }
            return
        }
        let frames = DumlTransport.scanFrames(bytes)
        counts.commands.append(contentsOf: frames)
        if let (expected, completion) = nextObservedCommand,
            frames.contains(where: {
                $0.cmdSet == expected.cmdSet && $0.cmdId == expected.cmdId
                    && $0.flags == expected.flags && $0.payload == expected.payload
            }) {
            nextObservedCommand = nil
            completion()
        }
        if peer === connection {
            for frame in frames {
                if frame.cmdSet == 2 { counts.cameraSettings += 1 }
                if frame.cmdSet == 0, frame.cmdId == 0x81 {
                    registered = true
                    counts.registrations += 1
                    if let seq = DumlTransport.transportSeq(bytes) {
                        counts.registrationSequences.append(seq)
                    }
                }
                if frame.cmdSet == 0, frame.cmdId == 0x99 { subscribed = true }
                if frame.cmdSet == 9, frame.cmdId == 0xa8, registered, subscribed {
                    counts.enables += 1
                }
            }
        } else if !DumlTransport.scanFrames(bytes).isEmpty {
            counts.unnegotiatedCommands += 1
        }
        guard registered, subscribed, let peer else { return }
        let status = Duml.encode(
            Duml.Frame(
                sender: 8, receiver: 2, seq: 1, flags: 0x80,
                cmdSet: 4, cmdId: 5, payload: [0, 0]))
        let packet =
            DumlTransport.transportHeader(
                pktType: 1, payloadLen: status.count, sessionId: 1, seq: 8) + status
        peer.send(content: Data(packet), completion: .idempotent)
    }
}
