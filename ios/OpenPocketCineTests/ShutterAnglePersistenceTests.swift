import OpenPocketViewCore
import Network
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class ShutterAnglePersistenceTests: XCTestCase {
    func testOpeningAnglePickerCannotOverwriteIntentDuringFormatTransition() async throws {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let model = AppModel()
        model.session = fixture(controlsOnly: true)
        model.session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
        let controller = UIHostingController(
            rootView: CapturePickerPanel(sheet: .shutter, maximumHeight: 350, onClose: {})
                .environment(model).environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            model.session.disconnect()
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(OperatorPrefs.shutterAngleDegrees, 180)
    }

    func testFormatRematchWritesCorrectShutterOnlyAfterReportedFormat() async throws {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let peer = try ShutterAnglePeer()
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let session = fixture(controlsOnly: true)
        session.datalink = driver
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        try await driver.open()
        session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
        try await waitFor { peer.frames.contains { $0.cmdSet == 2 && $0.cmdId == 0x18 } }
        XCTAssertFalse(
            peer.frames.contains { $0.cmdSet == 2 && $0.cmdId == 0x28 },
            "The old encoder format must not race the new shutter SET")
        session.receiveMultiview(subscribe("cam_video_param_v2", [0x10, 0x06]))
        try await waitFor { peer.frames.contains { $0.cmdSet == 2 && $0.cmdId == 0x28 } }
        XCTAssertEqual(
            peer.frames.last { $0.cmdSet == 2 && $0.cmdId == 0x28 }?.payload,
            Commands.setShutter(denom: 120).payload)
    }

    func testEarlyExposureEchoAndStaleAutoCannotReleasePendingAngle() {
        withAngleFixture { session in
            session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
            session.receiveMultiview(exposure(120))
            session.receiveMultiview(exposure(48))
            XCTAssertEqual(readout(session), "180°", "An exposure echo cannot confirm FORMAT")
        }
        withAngleFixture { session in
            session.status.expoMode = .auto
            session.setExpoMode(.manual)
            session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
            session.receiveMultiview(exposure(48, mode: .auto))
            XCTAssertEqual(session.status.expoMode, .manual)
            XCTAssertEqual(readout(session), "180°", "Stale Auto must obey the newer Manual pin")
        }
    }

    func testDelayedFormatKeepsLatestAngleAndSendsOnlyAfterConfirmation() async throws {
        try await withWireFixture { session, peer in
            session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
            try await waitFor { peer.frames.contains { $0.cmdId == 0x18 } }
            let sent = try XCTUnwrap(peer.frames.first { $0.cmdId == 0x18 })
            session.receiveMultiview(reply(sent, payload: [0]))
            try await Task.sleep(for: .milliseconds(2150))
            session.setShutterAngle(90)
            XCTAssertFalse(peer.frames.contains { $0.cmdId == 0x28 })
            session.receiveMultiview(subscribe("cam_video_param_v2", [0x10, 0x06]))
            try await waitFor { peer.frames.contains { $0.cmdId == 0x28 } }
            XCTAssertEqual(peer.frames.last { $0.cmdId == 0x28 }?.payload,
                Commands.setShutter(denom: 240).payload)
            XCTAssertEqual(OperatorPrefs.shutterAngleDegrees, 90)
        }
    }

    func testAutoAndRetiredEditorsCannotReleasePendingAngle() async throws {
        for retire in [false, true] {
            try await withWireFixture { session, peer in
                session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
                try await waitFor { peer.frames.contains { $0.cmdId == 0x18 } }
                if retire { session.releaseMultiview() } else { session.setExpoMode(.auto) }
                session.receiveMultiview(subscribe("cam_video_param_v2", [0x10, 0x06]))
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertFalse(peer.frames.contains { $0.cmdId == 0x28 })
            }
        }
    }

    private func withAngleFixture(_ body: (CameraSession) throws -> Void) rethrows {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let session = fixture(controlsOnly: true)
        defer {
            session.disconnect()
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        try body(session)
    }

    private func withWireFixture(_ body: (CameraSession, ShutterAnglePeer) async throws -> Void) async throws {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let peer = try ShutterAnglePeer()
        let driver = DatalinkDriver.loopbackForTesting(port: try await peer.start())
        let session = fixture(controlsOnly: true)
        session.datalink = driver
        defer {
            session.disconnect()
            driver.close()
            peer.stop()
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        try await driver.open()
        try await body(session, peer)
    }

    private func reply(_ frame: Duml.Frame, payload: [UInt8]) -> Duml.Frame {
        Duml.Frame(sender: frame.receiver, receiver: frame.sender, seq: frame.seq,
            flags: 0xC0, cmdSet: frame.cmdSet, cmdId: frame.cmdId, payload: payload)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    func testFormatChangeKeeps180DegreesUntilExposureTelemetryCatchesUp() {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        defer {
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180

        for controlsOnly in [false, true] {
            let session = fixture(controlsOnly: controlsOnly)
            defer { session.disconnect() }
            XCTAssertEqual(readout(session), "180°")

            session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
            XCTAssertEqual(session.status.fps, 60)
            XCTAssertEqual(
                readout(session), "180°",
                "Changing FPS must not reinterpret the previous frame rate's shutter")

            session.receiveMultiview(subscribe("cam_video_param_v2", [0x10, 0x06]))
            session.receiveMultiview(exposure(48))
            XCTAssertEqual(readout(session), "180°", "Older exposure must not replace chosen angle")
            XCTAssertEqual(OperatorPrefs.shutterAngleDegrees, 180)

            session.receiveMultiview(exposure(120))
            XCTAssertEqual(readout(session), "180°")
            session.setVideoFormat(resolution: .p4K, frameRate: .fps30, fromOperator: false)
            XCTAssertEqual(
                readout(session), "180°", "Preset/internal format path must preserve the angle too")
        }
    }

    private func fixture(controlsOnly: Bool) -> CameraSession {
        let session = CameraSession(borrowing: HevcDecoder(), controlsOnly: controlsOnly)
        session.multiviewControlAdmission = { true }
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps24)
        status.videoResolution = .p4K
        status.fps = 24
        status.expoMode = .manual
        status.shutterDenom = 48
        status.availableShutterDenoms = [24, 48, 50, 60, 120, 240]
        session.updateMultiview(
            camera: FoundCamera(
                id: UUID(), name: "OsmoPocket3-Test",
                model: CameraModel.resolve(modelId: nil, name: "OsmoPocket3-Test"), modelId: nil),
            driver: DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: ""), status: status)
        return session
    }

    private func readout(_ session: CameraSession) -> String {
        CaptureQuickSnapshot.shutterReadout(
            status: session.status, shutterUsesAngle: OperatorPrefs.shutterUsesAngle,
            shutterAngleDegrees: OperatorPrefs.shutterAngleDegrees)
    }

    private func exposure(_ denom: Int, mode: ExpoMode = .manual) -> Duml.Frame {
        var value = [UInt8](repeating: 0, count: 23)
        value[2] = UInt8(denom & 0xFF)
        value[3] = UInt8(denom >> 8) | 0x80
        value[5] = 3
        value[6] = 0x10
        value[7] = mode.rawValue
        return subscribe("cam_expo_param", value)
    }

    private func subscribe(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }
}

/// The real datalink sends to this local peer; no camera, radio or recording is used.
private final class ShutterAnglePeer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "test.shutter-angle")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var captured: [Duml.Frame] = []
    var frames: [Duml.Frame] { queue.sync { captured } }

    init() throws { listener = try NWListener(using: .udp) }

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
                let reply = DumlTransport.transportHeader(
                    pktType: 0, payloadLen: 7, sessionId: 1, seq: 0) + [1, 0, 0, 0, 0, 0, 0]
                connection.send(content: Data(reply), completion: .idempotent)
                let payload = DumlTransport.ackPayload(peerCursor: 0x6000, baseSeq: 0x6000)
                let window = DumlTransport.transportHeader(
                    pktType: 1, payloadLen: payload.count, sessionId: 1, seq: 8) + payload
                connection.send(content: Data(window), completion: .idempotent)
            } else {
                self.captured += DumlTransport.scanFrames(bytes)
            }
            self.receive(connection)
        }
    }
}
