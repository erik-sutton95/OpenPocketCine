import Foundation
import Network
import Observation
import OpenCineDJI
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// SIMULATED real native composition with an unopened borrowed driver; no camera or radio.
@MainActor
final class EditorReconciliationOwnerTests: XCTestCase {
    @MainActor private final class Reentry { var value = false }

    private func borrowed() -> CameraSession {
        let session = CameraSession(borrowing: HevcDecoder(), controlsOnly: true)
        session.multiviewControlAdmission = { true }
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps24)
        status.videoResolution = .p4K
        status.fps = 24
        status.expoMode = .manual
        status.shutterDenom = 48
        status.availableShutterDenoms = [24, 48, 60, 120, 240]
        status.whiteBalance = .auto
        session.updateMultiview(
            camera: DjiAppleSighting(
                id: UUID(), name: "OsmoPocket3-Test",
                model: CameraModel.resolve(modelId: nil, name: "OsmoPocket3-Test"), modelId: nil),
            driver: DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: ""), status: status)
        return session
    }

    func testActualCommittedWhiteBalanceObserverCanReplaceBeforeOutgoingWireAdmission() {
        let session = borrowed()
        let driver = session.datalink
        defer {
            session.releaseMultiview()
            driver?.close()
        }
        let reentry = Reentry()
        var outgoingNotSent = 0
        withObservationTracking {
            _ = session.pendingWhiteBalance
        } onChange: {
            MainActor.assumeIsolated {
                guard !reentry.value else { return }
                reentry.value = true
                XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5600, tint: 0))
                session.setWhiteBalanceCustom(kelvin: 6500, tint: 0)
            }
        }
        session.setWhiteBalanceCustom(
            kelvin: 5600, tint: 0,
            onStage: {
                if case .notSent = $0 { outgoingNotSent += 1 }
            })
        XCTAssertTrue(reentry.value)
        XCTAssertEqual(outgoingNotSent, 1)
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 6500, tint: 0))
        XCTAssertEqual(
            session.whiteBalanceDisplayStatus.whiteBalance, .custom(kelvin: 6500, tint: 0))
        XCTAssertEqual(session.status.whiteBalance, .auto)
    }

    func testActualSparseConfirmationCallbackCannotPublishOverSuccessorEditorRequest() {
        let session = borrowed()
        let driver = session.datalink
        defer {
            session.releaseMultiview()
            driver?.close()
        }
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        let reentry = Reentry()
        withObservationTracking {
            _ = session.pendingWhiteBalance
        } onChange: {
            MainActor.assumeIsolated {
                guard !reentry.value else { return }
                reentry.value = true
                XCTAssertNil(session.pendingWhiteBalance)
                session.setWhiteBalanceCustom(kelvin: 6500, tint: 0)
            }
        }
        let report =
            [UInt8](repeating: 0, count: 4)
            + WhiteBalance.custom(kelvin: 5600, tint: 0).setPayload
        session.receiveMultiview(subscribe("cam_image_effect", report))
        XCTAssertTrue(reentry.value)
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 6500, tint: 0))
        XCTAssertEqual(
            session.whiteBalanceDisplayStatus.whiteBalance, .custom(kelvin: 6500, tint: 0))
        XCTAssertEqual(session.status.whiteBalance, .auto)
    }

    func testActualEarlyExposureAndLatestAngleWaitForSparseFormatConfirmation() {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let session = borrowed()
        let driver = session.datalink
        defer {
            session.releaseMultiview()
            driver?.close()
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
        XCTAssertTrue(session.isFormatPinActive)
        var exposure = [UInt8](repeating: 0, count: 23)
        exposure[2] = 120
        exposure[3] = 0x80
        exposure[5] = 3
        exposure[6] = 0x10
        exposure[7] = ExpoMode.manual.rawValue
        session.receiveMultiview(subscribe("cam_expo_param", exposure))
        XCTAssertTrue(session.isFormatPinActive)
        XCTAssertEqual(session.status.fps, 60)
        XCTAssertEqual(session.status.shutterDenom, 120)
        session.setShutterAngle(90)
        XCTAssertTrue(session.isFormatPinActive)
        XCTAssertEqual(OperatorPrefs.shutterAngleDegrees, 90)
        session.receiveMultiview(subscribe("cam_video_param_v2", [0x10, 0x06]))
        XCTAssertFalse(session.isFormatPinActive)
        XCTAssertEqual(session.status.shutterDenom, 240)
        XCTAssertEqual(OperatorPrefs.shutterAngleDegrees, 90)
    }

    func testActualOwnedDisconnectRetiresPendingEditorWithoutInventingCameraConfirmation() {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        session.datalink = driver
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5600, tint: 0))
        XCTAssertNil(session.status.whiteBalance)
        session.disconnect()
        XCTAssertNil(session.pendingWhiteBalance)
        XCTAssertNil(session.whiteBalanceDisplayStatus.whiteBalance)
        XCTAssertNil(session.datalink)
        XCTAssertTrue(driver.isClosed)
        XCTAssertEqual(session.phase, .idle)
    }

    func testActualSuccessfulFormatACKKeepsWireOwnerResultDuringUnrelatedEditorReentry()
        async throws
    {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        defer {
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        try await withWireFixture { session, peer in
            try await acknowledgedWhiteBalance(session, peer: peer)
            try await Task.sleep(for: .milliseconds(2150))
            let reentry = Reentry()
            withObservationTracking {
                _ = session.pendingWhiteBalance
            } onChange: {
                MainActor.assumeIsolated {
                    guard !reentry.value else { return }
                    reentry.value = true
                    XCTAssertNil(session.pendingWhiteBalance)
                    session.setIsoLimit(.max800)
                }
            }
            session.setVideoFormat(resolution: .p4K, frameRate: .fps60)
            try await waitFor { peer.frames.contains { $0.cmdSet == 2 && $0.cmdId == 0x18 } }
            let format = try XCTUnwrap(peer.frames.first { $0.cmdSet == 2 && $0.cmdId == 0x18 })
            session.receiveMultiview(reply(format, payload: [0]))
            try await waitFor {
                reentry.value
                    && peer.frames.contains {
                        $0.payload == Commands.setIsoLimit(.max800).payload
                            && $0.cmdId == Commands.setIsoLimit(.max800).cmdId
                    }
            }
            XCTAssertTrue(session.isFormatPinActive)
            XCTAssertEqual(
                session.status.videoFormat, VideoFormat(resolution: .p4K, frameRate: .fps60))
            XCTAssertEqual(session.status.fps, 60)
            XCTAssertEqual(session.status.isoLimit, .max800)
            XCTAssertEqual(
                Set(peer.frames.filter { $0.cmdSet == 2 && $0.cmdId == 0x18 }.map(\.seq)).count, 1)
            XCTAssertFalse(peer.frames.contains { $0.cmdSet == 2 && $0.cmdId == 0x28 })
        }
    }

    func testActualConsumedPositiveRequestReplyCannotRollbackChannelAfterUnrelatedReentry()
        async throws
    {
        try await withWireFixture { session, peer in
            session.status.audioChannel = .stereo
            try await acknowledgedWhiteBalance(session, peer: peer)
            try await Task.sleep(for: .milliseconds(2150))
            let reentry = Reentry()
            withObservationTracking {
                _ = session.pendingWhiteBalance
            } onChange: {
                MainActor.assumeIsolated {
                    guard !reentry.value else { return }
                    reentry.value = true
                    XCTAssertNil(session.pendingWhiteBalance)
                    session.setIsoLimit(.max800)
                }
            }
            session.setAudioChannel(.mono)
            let command = Commands.setAudioChannel(.mono)
            try await waitFor {
                peer.frames.contains {
                    $0.cmdSet == command.cmdSet && $0.cmdId == command.cmdId
                        && $0.payload == command.payload
                }
            }
            let sent = try XCTUnwrap(
                peer.frames.first {
                    $0.cmdSet == command.cmdSet && $0.cmdId == command.cmdId
                        && $0.payload == command.payload
                })
            session.receiveMultiview(reply(sent, payload: [0]))
            // This real request resumes on the owner actor; allow its event and FIFO tail to settle.
            for _ in 0..<100 { await Task.yield() }
            XCTAssertTrue(reentry.value)
            XCTAssertEqual(session.status.audioChannel, .mono)
            XCTAssertEqual(session.status.isoLimit, .max800)
            XCTAssertNil(session.pendingWhiteBalance)
            XCTAssertEqual(
                Set(
                    peer.frames.filter {
                        $0.cmdSet == command.cmdSet && $0.cmdId == command.cmdId
                            && $0.payload == command.payload
                    }.map(\.seq)
                ).count, 1)
        }
    }

    func testActualMandatoryDSPGETUsesFreshCapturedBytesDuringUnrelatedWhiteBalanceReentry()
        async throws
    {
        try await withWireFixture { session, peer in
            XCTAssertNil(session.status.audioDspBlob)
            try await acknowledgedWhiteBalance(session, peer: peer)
            try await Task.sleep(for: .milliseconds(2150))
            let reentry = Reentry()
            let blob = Array(UInt8(0)..<UInt8(26))
            withObservationTracking {
                _ = session.pendingWhiteBalance
            } onChange: {
                MainActor.assumeIsolated {
                    guard !reentry.value else { return }
                    reentry.value = true
                    XCTAssertNil(session.pendingWhiteBalance)
                    XCTAssertEqual(session.cameraReportedCapture.audioDspBlob, blob)
                    XCTAssertNil(session.status.audioDspBlob)
                    session.setIsoLimit(.max800)
                }
            }
            session.setWindNR(.on)
            let get = Commands.audioDspGet()
            try await waitFor {
                peer.frames.contains { $0.cmdSet == get.cmdSet && $0.cmdId == get.cmdId }
            }
            let sent = try XCTUnwrap(
                peer.frames.first { $0.cmdSet == get.cmdSet && $0.cmdId == get.cmdId })
            session.receiveMultiview(reply(sent, payload: [0] + blob))
            let set = Commands.audioDspSet(AudioDspBlob.patchWind(blob, .on))
            try await waitFor {
                peer.frames.contains { $0.cmdSet == set.cmdSet && $0.cmdId == set.cmdId }
            }
            let actual = try XCTUnwrap(
                peer.frames.first { $0.cmdSet == set.cmdSet && $0.cmdId == set.cmdId })
            XCTAssertTrue(reentry.value)
            XCTAssertEqual(actual.payload, set.payload)
            XCTAssertEqual(Array(actual.payload[..<2]), Array(blob[..<2]))
            XCTAssertEqual(Array(actual.payload[3...]), Array(blob[3...]))
            XCTAssertEqual(session.status.isoLimit, .max800)
            XCTAssertNil(session.pendingWhiteBalance)
            XCTAssertEqual(
                Set(
                    peer.frames.filter { $0.cmdSet == get.cmdSet && $0.cmdId == get.cmdId }.map(
                        \.seq)
                ).count, 1)
            XCTAssertEqual(
                Set(
                    peer.frames.filter { $0.cmdSet == set.cmdSet && $0.cmdId == set.cmdId }.map(
                        \.seq)
                ).count, 1)
            session.receiveMultiview(reply(actual, payload: [0]))
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(session.status.audioDspBlob, AudioDspBlob.patchWind(blob, .on))
            XCTAssertEqual(session.status.windNR, .on)
            XCTAssertEqual(session.status.isoLimit, .max800)
        }
    }

    func testActualMandatoryGETSourceRetirementCannotContinueOntoBorrowedTransport() async throws {
        try await withWireFixture { session, peer in
            let driver = session.datalink
            try await acknowledgedWhiteBalance(session, peer: peer)
            try await Task.sleep(for: .milliseconds(2150))
            let reentry = Reentry()
            withObservationTracking {
                _ = session.pendingWhiteBalance
            } onChange: {
                MainActor.assumeIsolated {
                    guard !reentry.value else { return }
                    reentry.value = true
                    session.releaseMultiview()
                }
            }
            session.setWindNR(.on)
            let get = Commands.audioDspGet()
            try await waitFor {
                peer.frames.contains { $0.cmdSet == get.cmdSet && $0.cmdId == get.cmdId }
            }
            let sent = try XCTUnwrap(
                peer.frames.first { $0.cmdSet == get.cmdSet && $0.cmdId == get.cmdId })
            session.receiveMultiview(reply(sent, payload: [0] + Array(UInt8(0)..<UInt8(26))))
            for _ in 0..<100 { await Task.yield() }
            XCTAssertTrue(reentry.value)
            XCTAssertNil(session.datalink)
            XCTAssertEqual(driver?.isClosed, false)
            let forbiddenSet = Commands.audioDspSet(
                AudioDspBlob.patchWind(Array(UInt8(0)..<UInt8(26)), .on))
            XCTAssertFalse(
                peer.frames.contains {
                    $0.cmdSet == forbiddenSet.cmdSet && $0.cmdId == forbiddenSet.cmdId
                })
        }
    }

    private func acknowledgedWhiteBalance(_ session: CameraSession, peer: EditorReconciliationPeer)
        async throws
    {
        var acknowledged = false
        session.setWhiteBalanceCustom(
            kelvin: 5600, tint: 0,
            onStage: {
                if case .acknowledged = $0 { acknowledged = true }
            })
        let command = Commands.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        try await waitFor {
            peer.frames.contains { $0.cmdSet == command.cmdSet && $0.cmdId == command.cmdId }
        }
        let sent = try XCTUnwrap(
            peer.frames.first { $0.cmdSet == command.cmdSet && $0.cmdId == command.cmdId })
        session.receiveMultiview(reply(sent, payload: [0]))
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5600, tint: 0))
    }

    private func withWireFixture(
        _ body: (CameraSession, EditorReconciliationPeer) async throws -> Void
    ) async throws {
        let peer = try EditorReconciliationPeer()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = borrowed()
        let unusedDriver = session.datalink
        session.datalink = driver
        unusedDriver?.close()
        defer {
            session.releaseMultiview()
            driver.close()
            peer.stop()
        }
        try await driver.open()
        try await body(session, peer)
    }

    private func reply(_ frame: Duml.Frame, payload: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: frame.receiver, receiver: frame.sender, seq: frame.seq,
            flags: 0xC0, cmdSet: frame.cmdSet, cmdId: frame.cmdId, payload: payload)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    private func subscribe(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }
}

/// The real datalink sends to this local peer; no camera, radio or recording is used.
private final class EditorReconciliationPeer: @unchecked Sendable {
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
                self.captured += DumlTransport.scanFrames(bytes)
            }
            self.receive(connection)
        }
    }
}
