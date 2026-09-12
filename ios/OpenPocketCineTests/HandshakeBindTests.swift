import Foundation
import Network
import OpenPocketViewCore
import XCTest
import os

@testable import OpenPocketCine

@MainActor
final class HandshakeBindTests: XCTestCase {
    func testRepairRetiresAnActiveAudioChainEvenWhenAnotherWorkItemOwnsItsTail() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let session = CameraSession(borrowing: HevcDecoder())
        session.datalink = driver
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
        }
        try await driver.open()
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
        let repair = Task { await session.repairDatalink(reason: "audio ownership regression") }
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
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let session = CameraSession(borrowing: HevcDecoder())
        session.datalink = driver
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
        }
        try await driver.open()
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
        let repair = Task { await session.repairDatalink(reason: "command ownership regression") }
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
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let decoder = HevcDecoder()
        let session = CameraSession(borrowing: decoder)
        session.isMultiviewBorrowed = true
        session.updateMultiview(
            camera: FoundCamera(
                id: UUID(), name: "Pocket4Pro-Test",
                model: .resolve(modelId: 0x22, name: "Pocket4Pro-Test"), modelId: 0x22),
            driver: driver, status: CameraStatus())
        session.isMultiviewBorrowed = false
        defer {
            session.disconnect()
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
        await session.repairDatalink(
            reason: "picture regression", pictureDeadline: .milliseconds(40))
        XCTAssertTrue(session.holdsMonitor, "Handshake alone cannot release recovery ownership")
        XCTAssertTrue(session.sessionRecovery.isRecovering)
        XCTAssertTrue(driver.isClosed, "The failed picture attempt must release its transport")
        XCTAssertEqual(peer.snapshot.handshakes, 2)
        XCTAssertEqual(peer.snapshot.enables, 2, "No duplicate enable within one repair")
    }

    func testCancelledEndpointNegotiationCannotPublishSuccessOrKeepSending() async throws {
        let peer = try EndpointPinnedCamera()
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
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
        let driver = DatalinkDriver.loopbackForTesting(port: port)
        defer {
            driver.close()
            peer.stop()
        }
        try await driver.open()
        driver.startLiveView()
        let firstDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while driver.lastStatusAt == nil, ContinuousClock.now < firstDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(driver.lastStatusAt, "Initial negotiated endpoint receives the peer")
        XCTAssertEqual(peer.snapshot.handshakes, 1)

        try await driver.rebuildUDP(reason: "endpoint regression")
        driver.startLiveView()  // the shell owns exactly one enable after repair
        let repairedDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while driver.lastStatusAt == nil, ContinuousClock.now < repairedDeadline {
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

    func testReplacementCannotInheritAlreadyArmedOldReceiveAck() {
        let state = OSAllocatedUnfairLock(initialState: (generation: 0, acked: false))
        let queue = DispatchQueue(label: "test.old-receive")
        let oldGeneration = 0
        let oldSocket = NWConnection(host: "127.0.0.1", port: 9004, using: .udp)
        DatalinkDriver.prepareHandshakeBind(
            existingSocket: oldSocket,
            discard: {
                state.withLock { $0.generation += 1 }
                queue.sync {}
            },
            reset: {
                state.withLock { $0.acked = false }
                // An old callback may run immediately after reset. Generation
                // invalidation must already have happened before this point.
                queue.async {
                    state.withLock {
                        if $0.generation == oldGeneration { $0.acked = true }
                    }
                }
                queue.sync {}
            })
        XCTAssertFalse(state.withLock { $0.acked })
    }

    func testFirstBindResetsWithoutDiscardingFreshTransport() {
        var reset = false
        DatalinkDriver.prepareHandshakeBind(
            existingSocket: nil,
            discard: { XCTFail("First bind must not discard a fresh driver") },
            reset: { reset = true })
        XCTAssertTrue(reset)
    }
}

/// A UDP peer with the endpoint behavior observed in the physical capture:
/// ACK/presence from a new endpoint do not retarget its existing session.
private final class EndpointPinnedCamera: @unchecked Sendable {
    struct Snapshot {
        var handshakes = 0
        var registrations = 0
        var enables = 0
        var cameraSettings = 0
        var unnegotiatedCommands = 0
    }
    private let queue = DispatchQueue(label: "test.endpoint-pinned-camera")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var peer: NWConnection?
    private var registered = false
    private var subscribed = false
    private var counts = Snapshot()
    private var rejectingHandshakes = false

    init() throws { listener = try NWListener(using: .udp) }
    var snapshot: Snapshot { queue.sync { counts } }
    func rejectNewHandshakes() { queue.sync { rejectingHandshakes = true } }

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
            if rejectingHandshakes { return }
            peer = connection
            registered = false
            subscribed = false
            connection.send(content: Data(bytes), completion: .idempotent)
            return
        }
        if peer === connection {
            for frame in DumlTransport.scanFrames(bytes) {
                if frame.cmdSet == 2 { counts.cameraSettings += 1 }
                if frame.cmdSet == 0, frame.cmdId == 0x81 {
                    registered = true
                    counts.registrations += 1
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
