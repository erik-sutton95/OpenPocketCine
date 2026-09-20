import MonitorPresentation
import Network
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class CapturePreviewTrafficTests: XCTestCase {
    func testMountedHeldPanelsAndTheirDetentsAreReadOnlyUntilExplicitReleaseCommit() async throws {
        let peer = try CaptureTrafficPeer()
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let model = AppModel()
        model.session = CameraSession(borrowing: HevcDecoder())
        model.session.datalink = driver
        let size = CGSize(width: 874, height: 402)
        let host = UIHostingController(
            rootView: LiveCaptureDrumHost(viewport: size)
                .environment(model)
                .environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer {
            model.captureDrum = nil
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
            driver.close()
            peer.stop()
        }
        try await driver.open()
        let baseline = peer.cameraCommands
        var status = CameraStatus()
        status.colorMode = .normal
        status.isoIndex = .auto
        status.whiteBalance = .custom(kelvin: 5600, tint: 17)
        status.whiteBalanceKelvin = 5600
        status.whiteBalanceTint = 17
        model.session.status = status

        for sheet in [CaptureSheet.iso, .audio, .wb] {
            let snapshot = try XCTUnwrap(CaptureQuickSnapshot.primary(sheet, model: model))
            let id = UUID()
            for travel in [0.0, -28, -56, -112, 0] {
                model.captureDrum = CaptureDrumPresentation(
                    id: id, sheet: sheet, snapshot: snapshot,
                    position: MonitorDrumSelection.position(
                        origin: snapshot.index, translation: travel, count: snapshot.options.count))
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
                XCTAssertEqual(
                    model.session.status, status, "Preview changed native state: \(sheet)")
                XCTAssertEqual(
                    peer.cameraCommands, baseline, "Preview emitted a GET or SET: \(sheet)")
            }
            model.captureDrum = nil
            try await Task.sleep(for: .milliseconds(30))
        }

        // Positive control: the same connected transport must observe an
        // explicit commit, so the zero-traffic assertions cannot pass on a dead sink.
        let snapshot = try XCTUnwrap(CaptureQuickSnapshot.primary(.wb, model: model))
        let value = try XCTUnwrap(snapshot.changedValue(translation: -56, current: snapshot))
        snapshot.apply(value, model: model)
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while peer.cameraCommands == baseline, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(peer.cameraCommands, baseline)
        XCTAssertEqual(model.session.status.whiteBalanceKelvin, 5700)
        XCTAssertEqual(model.session.status.whiteBalanceTint, 17)
    }
}

/// Uses the production datalink against a local handshake peer. All camera
/// control frames are counted regardless of GET/SET, except the datalink-owned
/// periodic Selfie Flip GET. That production poll runs even with no UI mounted;
/// its exact opcode, flags and payload are excluded, never other parameter GETs.
private final class CaptureTrafficPeer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "test.capture-preview-traffic")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var commands = 0

    init() throws { listener = try NWListener(using: .udp) }
    var cameraCommands: Int { queue.sync { commands } }

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
            let bytes = Array(data)
            if DumlTransport.isHandshake(bytes) {
                // The camera ACK and initial command window are separate datagrams.
                let reply =
                    DumlTransport.transportHeader(
                        pktType: 0, payloadLen: 7, sessionId: 1, seq: 0) + [1, 0, 0, 0, 0, 0, 0]
                connection.send(content: Data(reply), completion: .idempotent)
                let payload = DumlTransport.ackPayload(peerCursor: 0x6000, baseSeq: 0x6000)
                let window =
                    DumlTransport.transportHeader(
                        pktType: 1, payloadLen: payload.count, sessionId: 1, seq: 8) + payload
                connection.send(content: Data(window), completion: .idempotent)
            } else {
                let poll = Commands.getSelfieFlip()
                self.commands +=
                    DumlTransport.scanFrames(bytes).filter { frame in
                        frame.cmdSet == 2
                            && !(frame.cmdId == poll.cmdId
                                && frame.flags == poll.flags && frame.payload == poll.payload)
                    }.count
            }
            self.receive(connection)
        }
    }
}
