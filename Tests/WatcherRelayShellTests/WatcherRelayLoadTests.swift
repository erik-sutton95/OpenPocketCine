import CoreVideo
import Foundation
import Network
import OpenPocketViewCore
import XCTest

@testable import WatcherRelayShell

final class WatcherRelayLoadTests: XCTestCase {
    func testRelayNeverEnablesPeerToPeerFallback() {
        let parameters = WatcherRelayNetwork.parameters()
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertTrue(parameters.prohibitedInterfaceTypes?.contains(.cellular) == true)
        XCTAssertEqual(parameters.serviceClass, .interactiveVideo)
        let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
        XCTAssertTrue(tcp?.noDelay == true)
        XCTAssertTrue(tcp?.enableKeepalive == true)
        XCTAssertEqual(tcp?.keepaliveIdle, 10)
        XCTAssertEqual(tcp?.keepaliveInterval, 5)
        XCTAssertEqual(tcp?.keepaliveCount, 3)
    }

    @MainActor
    func testControlTrafficDoesNotDropVideoFrames() throws {
        var frames = 0
        let host = WatcherRelayTransport(sendWire: { data, _, _ in
            if (try? WatcherRelayFraming.decode(from: data)?.kind) == .frame { frames += 1 }
            // Model a link whose completions arrive after two camera frame intervals.
        })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(
                host: "127.0.0.1", port: 9000, using: .tcp))
        host.peers[ObjectIdentifier(peer)] = peer
        let hello = try JSONEncoder().encode(WatcherRelayHello(hostName: "Watcher"))
        try host.onMessage(peer: peer, msg: .init(kind: .hello, payload: hello, consumedBytes: 0))
        host.broadcast(hevc: Data([1]), isKey: true, sets: nil)
        host.broadcast(hevc: Data([2]), isKey: false, sets: nil)
        XCTAssertEqual(frames, 2, "Hello and control-token sends must not consume video capacity")
    }
}

extension WatcherRelayLoadTests {
    func testSlowWatcherDoesNotReduceHealthyWatchersDelivery() {
        var delivered: [ObjectIdentifier: Int] = [:]
        var completions: [(ObjectIdentifier, () -> Void)] = []
        let host = WatcherRelayTransport(sendWire: { data, connection, completion in
            guard (try? WatcherRelayFraming.decode(from: data)?.kind) == .frame else { return }
            let id = ObjectIdentifier(connection)
            delivered[id, default: 0] += 1
            completions.append((id, completion))
        })
        let peers = (0..<9).map { _ in
            let peer = WatcherRelayTransport.Peer(
                conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
            peer.authorized = true
            return peer
        }
        host.queue.sync {
            for peer in peers { host.peers[ObjectIdentifier(peer)] = peer }
        }
        for frame in 0..<300 {
            host.queue.sync {
                completions.removeAll()
                host.broadcast(hevc: Data([1]), isKey: frame % 25 == 0, sets: nil)
                // Keep just the first peer stalled; other links drain every frame.
                for (id, completion) in completions where id != ObjectIdentifier(peers[0].conn) {
                    completion()
                }
            }
        }
        host.queue.sync {}
        XCTAssertEqual(delivered[ObjectIdentifier(peers[0].conn)], 2)
        for peer in peers.dropFirst() {
            XCTAssertEqual(delivered[ObjectIdentifier(peer.conn)], 300)
        }
        host.queue.sync {
            peers[0].inFlight = 0
            host.broadcast(hevc: Data([1]), isKey: false, sets: nil)
            XCTAssertEqual(delivered[ObjectIdentifier(peers[0].conn)], 2)
            host.broadcast(hevc: Data([1]), isKey: true, sets: nil)
            XCTAssertEqual(delivered[ObjectIdentifier(peers[0].conn)], 3)
        }
    }

    func testBlockedEncoderCannotAccumulateSourceFrames() throws {
        var encoded = 0
        var outputs: [(WatcherRelayEncoder.Annex?, Bool) -> Void] = []
        let host = WatcherRelayTransport(encodeFrame: { _, _, completion in
            encoded += 1
            outputs.append(completion)
        })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
        host.queue.sync {
            peer.authorized = true
            host.peers[ObjectIdentifier(peer)] = peer
        }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer),
            kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        for _ in 0..<1_000 { host.submit(source) }
        host.queue.sync { XCTAssertEqual(encoded, 2) }
        outputs[0](nil, false)
        host.queue.sync {}
        host.submit(source)
        host.queue.sync { XCTAssertEqual(encoded, 3) }
        host.queue.sync { host.stop() }
        // Late completion cannot reopen a stopped transport.
        outputs[1](nil, false)
        host.submit(source)
        host.queue.sync { XCTAssertEqual(encoded, 3) }
    }

    func testStalledPeerHasOnlyOnePendingState() {
        var time = 0.0
        var stateMessages = 0
        let host = WatcherRelayTransport(
            now: { time },
            sendWire: { data, _, _ in
                if (try? WatcherRelayFraming.decode(from: data)?.kind) == .state {
                    stateMessages += 1
                }
            })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
        host.queue.sync {
            peer.authorized = true
            host.peers[ObjectIdentifier(peer)] = peer
            for tick in 0..<300 {
                time = Double(tick)
                host.update(state: WatcherRelayState())
            }
        }
        XCTAssertEqual(stateMessages, 1)
    }
}

extension WatcherRelayLoadTests {
    func testRealEncoderCompletesWithStandaloneHEVC() throws {
        let encoder = WatcherRelayEncoder()
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        XCTAssertEqual(
            CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, attributes, &buffer),
            kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(source, [])
        if let base = CVPixelBufferGetBaseAddress(source) {
            memset(base, 128, CVPixelBufferGetBytesPerRow(source) * 360)
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        let finished = expectation(description: "VT output, including asynchronous completion")
        finished.assertForOverFulfill = true
        encoder.encode(source, forceKey: true) { frame, failed in
            XCTAssertFalse(failed)
            XCTAssertEqual(frame?.isKey, true)
            XCTAssertFalse(frame?.data.isEmpty ?? true)
            XCTAssertEqual(frame?.sets?.count, 3)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        encoder.invalidate()
    }
}

extension WatcherRelayLoadTests {
    func testCameraSlowdownLowersBitrateWithoutNewVideoFrames() {
        var time = 0.0
        let host = WatcherRelayTransport(now: { time }, sendWire: { _, _, done in done() })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
        host.queue.sync {
            var state = WatcherRelayState()
            state.liveFPS = "25.00"
            host.update(state: state)
            peer.authorized = true
            host.peers[ObjectIdentifier(peer)] = peer
            state.liveFPS = "12.00"
            for tick in 1...30 {
                time = Double(tick) / 5
                host.update(state: state)
            }
            XCTAssertEqual(host.bitsPerSecond, 7_000_000)
        }
    }

    func testReaderHandlesFragmentedFramesOffMain() throws {
        let reader = WatcherRelayReader()
        let listener = try NWListener(using: .tcp, on: .any)
        let listening = expectation(description: "loopback listener")
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
        }
        var server: NWConnection?
        let meta = WatcherRelayFrameMetadata(isKeyframe: true)
        let payload = try WatcherRelayFrameBlob.encode(
            metadata: meta, hevc: Data(repeating: 7, count: 300_000))
        let wire = WatcherRelayFraming.encode(kind: .frame, payload: payload)
        listener.newConnectionHandler = { connection in
            server = connection
            connection.start(queue: reader.queue)
            connection.send(
                content: Data(wire.prefix(3)),
                completion: .contentProcessed { _ in
                    connection.send(
                        content: Data(wire.dropFirst(3)), completion: .contentProcessed { _ in })
                })
        }
        listener.start(queue: reader.queue)
        wait(for: [listening], timeout: 5)
        let connection = NWConnection(
            host: "127.0.0.1", port: try XCTUnwrap(listener.port), using: .tcp)
        connection.start(queue: reader.queue)
        let received = expectation(description: "complete frame")
        func receiveNext() {
            reader.receive(on: connection) { messages, complete, error in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertNil(error)
                if let message = messages.first {
                    guard case .frame(let metadata, let hevc) = message else {
                        XCTFail("Expected frame")
                        received.fulfill()
                        return
                    }
                    XCTAssertTrue(metadata.isKeyframe)
                    XCTAssertEqual(hevc, [UInt8](repeating: 7, count: 300_000))
                    received.fulfill()
                } else if complete || error != nil {
                    XCTFail("Frame truncated")
                    received.fulfill()
                } else {
                    receiveNext()
                }
            }
        }
        receiveNext()
        wait(for: [received], timeout: 5)
        connection.cancel()
        reader.queue.sync { server?.cancel() }
        listener.cancel()
    }
}

extension WatcherRelayLoadTests {
    func testDisconnectPublishesClearedControlRequest() {
        let host = WatcherRelayTransport(sendWire: { _, _, done in done() })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
        host.queue.sync {
            peer.watcherID = "watcher"
            host.peers[ObjectIdentifier(peer)] = peer
            host.pendingControlRequest = ("Watcher", "watcher")
            var publishedRequest: String? = "stale"
            host.onChange = { publishedRequest = host.pendingControlRequest?.watcherID }
            host.drop(peer)
            XCTAssertNil(publishedRequest)
            host.onChange = nil
        }
    }

    @MainActor
    func testReclaimRejectsAlreadyQueuedControlSnapshotAndCommand() async throws {
        let host = WatcherRelayHost()
        host.start(
            hostName: "Relay test", cameraName: "Test", passcode: "", ceilingIndex: 0,
            allowsControl: true)
        defer { host.stop() }
        let transport = try XCTUnwrap(host.transport)
        let unexpected = expectation(forNotification: .opcWatcherRelayCommand, object: nil)
        unexpected.isInverted = true
        transport.queue.sync {
            transport.lease.grant(name: "Watcher", watcherID: "watcher")
            transport.onChange?()
            transport.onCommand?(.toggleRecording, "watcher")
        }
        // The old snapshot and command are enqueued but MainActor has not yielded to them.
        host.reclaimControl()
        await fulfillment(of: [unexpected], timeout: 0.1)
        XCTAssertNil(host.applyCommand(.toggleRecording, from: "watcher"))
    }

    func testOrientationIsCapturedWithSourceBeforeDispatch() throws {
        var mirrors: [Bool] = []
        let sent = expectation(description: "both source orientations")
        sent.expectedFulfillmentCount = 2
        let host = WatcherRelayTransport(
            encodeFrame: { _, _, completion in
                completion(.init(data: Data([1]), isKey: true, sets: nil), false)
            },
            sendWire: { wire, _, done in
                if let message = try? WatcherRelayFraming.decode(from: wire),
                    message.kind == .frame,
                    let (metadata, _) = try? WatcherRelayFrameBlob.decode(message.payload)
                {
                    mirrors.append(metadata.extraMirrored)
                    sent.fulfill()
                }
                done()
            })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9000, using: .tcp))
        host.queue.sync {
            peer.authorized = true
            host.peers[ObjectIdentifier(peer)] = peer
        }
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer),
            kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        host.submit(source)
        host.updateOrientation(true)
        host.submit(source)
        wait(for: [sent], timeout: 2)
        XCTAssertEqual(mirrors, [false, true])
    }
}

extension WatcherRelayLoadTests {
    func testJoinDenialFinishesSendingBeforeClosingConnection() throws {
        var finishDenial: (() -> Void)?
        var denial: WatcherRelayJoinDenied?
        let host = WatcherRelayTransport(sendWire: { wire, _, completion in
            if let message = try? WatcherRelayFraming.decode(from: wire),
                message.kind == .joinDenied
            {
                denial = try? JSONDecoder().decode(
                    WatcherRelayJoinDenied.self, from: message.payload)
                finishDenial = completion
            }
        })
        let peer = WatcherRelayTransport.Peer(
            conn: NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
        try host.queue.sync {
            host.start(
                hostName: "Test host", cameraName: "Test camera", passcode: "example-only",
                ceilingIndex: 3, allowsControl: false)
            host.peers[ObjectIdentifier(peer)] = peer
            let hello = try JSONEncoder().encode(WatcherRelayHello(hostName: "Test watcher"))
            try host.onMessage(
                peer: peer, msg: .init(kind: .hello, payload: hello, consumedBytes: 0))
            XCTAssertTrue(denial?.passcodeRequired == true)
            XCTAssertNotNil(
                host.peers[ObjectIdentifier(peer)],
                "Keep the connection until the denial write completes, so the watcher can show its passcode prompt"
            )
            XCTAssertFalse(peer.authorized)
        }
        try XCTUnwrap(finishDenial)()
        host.queue.sync {
            XCTAssertNil(host.peers[ObjectIdentifier(peer)])
            host.stop()
        }
    }
}
