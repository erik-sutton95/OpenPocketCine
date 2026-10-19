import CoreGraphics
import Network
import OpenCineCore
import OpenCineDJI
import OpenCineDJIApple
import OpenCineHostedTestSupport
import OpenCineRelay
import OpenCineWatch
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual app admission ports. No camera report or native readiness is fabricated.
@MainActor
final class RemoteControlAdmissionTests: XCTestCase {
    /// SIMULATED loopback peer sees the real app Watch submission and native wire command.
    func testWatchAcceptsActualRecordAndPhotoDispatchWithoutInventingRecording() async throws {
        for photo in [false, true] {
            try await assertWatchDispatch(photo: photo, betweenPollingQueries: false)
        }
    }

    /// SIMULATED real queries on either side cannot substitute for, or duplicate, a capture.
    func testWatchDispatchIsExactlyOnceBetweenActualPollingQueries() async throws {
        for photo in [false, true] {
            try await assertWatchDispatch(photo: photo, betweenPollingQueries: true)
        }
    }

    /// PIA-366: the phone's interface lock guards touches on the phone, not the wrist remote. Before
    /// the shared watch policy the Watch recorded and captured with the phone locked (baseline
    /// `watchShutter(photo:)` had no lock check), like the Z and Insta Watch paths still do.
    func testWatchRecordsAndCapturesWhilePhoneInterfaceLocked() async throws {
        for photo in [false, true] {
            try await assertWatchDispatch(
                photo: photo, betweenPollingQueries: false, interfaceLocked: true)
        }
    }

    private func assertWatchDispatch(
        photo: Bool, betweenPollingQueries: Bool, interfaceLocked: Bool = false
    ) async throws {
        let peer = try WatchAckingCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        let session = CameraSession(borrowing: HevcDecoder())
        defer {
            session.disconnect()
            peer.stop()
            retainWireTrace(peer, name: "photo=\(photo) betweenQueries=\(betweenPollingQueries)")
        }
        session.datalink = driver
        driver.onStatusFrame = { [weak session] in session?.applyIncomingStatus($0) }
        try await driver.open()
        session.phase = .live
        session.status.shootingMode =
            photo ? Int(ShootingMode.photo.rawValue) : Int(ShootingMode.video.rawValue)
        session.status.recordingReported = true
        session.isLocked = interfaceLocked
        let model = AppModel(session: session)
        model.activateWatchRelay()
        let (phone, receipt) = try watchReceipt()
        defer { phone.close() }
        if betweenPollingQueries {
            let queryArrived = await HostedCondition.wait {
                peer.controlFrames.contains(where: WatchAckingCamera.isPollingRead)
            }
            XCTAssertTrue(queryArrived, "The real polling read must precede this capture")
        }
        let result = try XCTUnwrap(
            photo
                ? model.watchRelay.onAdmittedCapture?(receipt)
                : model.watchRelay.onAdmittedToggleRecord?(receipt))
        XCTAssertTrue(result.accepted)
        XCTAssertFalse(result.isRecording, "A dispatched command is not a recording observation")
        let expectedCommand: UInt8 = photo ? 0x01 : 0x02
        let captureArrived = await HostedCondition.wait {
            peer.controlFrames.contains { $0.cmdId == expectedCommand }
        }
        XCTAssertTrue(captureArrived, "The actual capture must reach the loopback")
        let settled = await HostedCondition.wait { !session.controlBusy }
        XCTAssertTrue(settled, "The actual command reply must settle before counting writes")
        XCTAssertFalse(session.status.isRecording, "A command reply is not a recording observation")
        if betweenPollingQueries {
            let nextQueryArrived = await HostedCondition.wait {
                let frames = peer.controlFrames
                guard let capture = frames.firstIndex(where: { $0.cmdId == expectedCommand }) else {
                    return false
                }
                return frames.dropFirst(capture + 1).contains(
                    where: WatchAckingCamera.isPollingRead)
            }
            XCTAssertTrue(nextQueryArrived, "The real polling read must continue after capture")
        }
        let writes = peer.nonPollingControlFrames
        XCTAssertEqual(
            writes.count, 1, "The actual native loopback must receive exactly one command")
        let command = try XCTUnwrap(writes.first)
        XCTAssertEqual(command.sender, 0x02)
        XCTAssertEqual(command.receiver, 0x01)
        XCTAssertEqual(command.flags, 0x40)
        XCTAssertEqual(command.cmdSet, 0x02)
        XCTAssertEqual(command.cmdId, expectedCommand)
        XCTAssertEqual(command.payload, [0x01])
    }

    /// SIMULATED observer tripwire: neither a parameter SET nor an unknown write is a polling read.
    func testLoopbackObserverRetainsParameterSetsAndUnknownCameraWrites() async throws {
        let peer = try WatchAckingCamera()
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await peer.start())
        defer {
            driver.close()
            peer.stop()
            retainWireTrace(peer, name: "unexpected-writes")
        }
        try await driver.open()
        let queryArrived = await HostedCondition.wait {
            peer.controlFrames.contains(where: WatchAckingCamera.isPollingRead)
        }
        XCTAssertTrue(queryArrived)
        let admission = DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true })
        let frames = [
            Duml.Frame(
                sender: 0x02, receiver: 0x01, seq: 0, flags: 0x40,
                cmdSet: 0x02, cmdId: 0x8E, payload: [0x01, 0x01, 0x4C, 0, 0x01, 0]),
            Duml.Frame(
                sender: 0x02, receiver: 0x01, seq: 0, flags: 0x40,
                cmdSet: 0x02, cmdId: 0x7F, payload: [0xA5]),
        ]
        for frame in frames {
            guard case .queued = driver.sendUntracked(frame, admission: admission) else {
                return XCTFail("The real native port must admit each SIMULATED tripwire write")
            }
        }
        let arrived = await HostedCondition.wait { peer.nonPollingControlFrames.count >= 2 }
        XCTAssertTrue(arrived)
        let writes = peer.nonPollingControlFrames
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes.map(\.cmdId).sorted(), [0x7F, 0x8E])
        XCTAssertEqual(
            writes.first(where: { $0.cmdId == 0x8E })?.payload,
            [0x01, 0x01, 0x4C, 0, 0x01, 0])
        XCTAssertEqual(writes.first(where: { $0.cmdId == 0x7F })?.payload, [0xA5])
    }

    private func retainWireTrace(_ peer: WatchAckingCamera, name: String) {
        let trace = "[WATCH-CASE] \(name)\n" + peer.wireTrace.joined(separator: "\n")
        let attachment = XCTAttachment(string: trace)
        attachment.name = "SIMULATED Watch wire \(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(trace)
    }

    func testWatchRefusesNilUnknownRecordUnsupportedModeAndMissingNativeLink() {
        let session = CameraSession(borrowing: HevcDecoder())
        let driver = DjiAppleDatalink(port: 9041, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        session.status.shootingMode = Int(ShootingMode.video.rawValue)
        let model = AppModel(session: session)
        model.publishWatchState()
        XCTAssertFalse(
            model.watchToggleRecord().accepted,
            "Unknown recording must not construct a record command")
        XCTAssertFalse(model.watchCapture().accepted)
        session.status.shootingMode = Int(ShootingMode.photo.rawValue)
        XCTAssertFalse(model.watchToggleRecord().accepted)
        session.datalink = nil
        model.publishWatchState()
        XCTAssertFalse(
            model.watchCapture().accepted, "Nil photo receipt must not imply an actual queued still"
        )
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(driver.secondsSinceLastCommand)
    }

    func testWatchRefusesRetiredShownNativeSourceAndUnadmittedWatchReceipt() throws {
        let session = CameraSession(borrowing: HevcDecoder())
        let driver = DjiAppleDatalink(port: 9042, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        session.status.shootingMode = Int(ShootingMode.video.rawValue)
        session.status.recordingReported = true
        let model = AppModel(session: session)
        model.activateWatchRelay()
        let (phone, receipt) = try watchReceipt()
        defer { phone.close() }
        driver.commandOwner.replaceSource()
        let stale = try XCTUnwrap(model.watchRelay.onAdmittedToggleRecord?(receipt))
        XCTAssertFalse(stale.accepted)
        XCTAssertEqual(stale.error, WatchRelayCopy.cameraChanged)
        phone.retireSource()
        XCTAssertFalse(model.watchRelay.onAdmittedToggleRecord?(receipt).accepted ?? true)
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(driver.secondsSinceLastCommand)
    }

    private func watchReceipt() throws -> (
        RelayWatchPhoneOwner<WatchRelayCodec, Int>, RelayWatchCommandAdmission
    ) {
        let phone = RelayWatchPhoneOwner<WatchRelayCodec, Int>(
            codec: WatchRelayCodec(),
            policy: .init(
                pacing: .init(
                    profiles: [.init(maximumWidth: 256, qualityPercent: 24)],
                    roundTripThresholds: [], initialIndex: 0), stateDelivery: .reachableMessage,
                releasesOutstandingOnRetirement: true), now: { 0 }, send: { _, _, _ in },
            encode: { _, _ in nil })
        var captured: RelayWatchCommandAdmission?
        phone.onAdmittedCommand = { _, receipt in
            captured = receipt
            return WatchCommandResult(accepted: true, isRecording: false, error: nil)
        }
        phone.acceptLink(activated: true, reachable: true)
        _ = phone.receiveCommand(
            try RelayWatchEnvelope.encode(WatchRelayCommand.capture, kind: .command),
            source: phone.source)
        return (phone, try XCTUnwrap(captured))
    }

    func testRevokedReceiptDoesNotCommitPinsBusyOrFocusBeforeAnyWrite() {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9031, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        session.status.isoIndex = .iso100
        session.status.colorMode = .normal
        session.status.whiteBalance = .auto(tint: 3)
        session.status.whiteBalanceTint = 3
        let receipt = DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true })
        driver.commandOwner.replaceSource()
        var refused = 0
        let stage: @MainActor (ControlWireEvent) -> Void = {
            if case .notSent = $0 { refused += 1 }
        }
        session.setISO(.iso800, admission: receipt, onStage: stage)
        session.setEv(.zero, admission: receipt, onStage: stage)
        session.setShutterDenom(100, admission: receipt, onStage: stage)
        session.setWhiteBalanceAuto(tint: 9, admission: receipt, onStage: stage)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: -5, admission: receipt, onStage: stage)
        session.setFocusMode(.continuous, admission: receipt, onStage: stage)
        session.setZoom(2, admission: receipt, onStage: stage)
        session.setZoomSlider(3, admission: receipt, onStage: stage)
        session.setRecording(true, admission: receipt, onStage: stage)
        session.takePhoto(admission: receipt)
        session.setColorMode(.dLog, admission: receipt)
        session.markFocus(at: .init(x: 0.1, y: 0.2), admission: receipt)
        XCTAssertEqual(refused, 9)
        XCTAssertFalse(session.controlBusy)
        XCTAssertEqual(session.status.isoIndex, .iso100)
        XCTAssertEqual(session.status.whiteBalance, .auto(tint: 3))
        XCTAssertEqual(session.status.colorMode, .normal)
        XCTAssertEqual(session.focusPoint.x, 0.5)
        XCTAssertEqual(session.focusPoint.y, 0.5)
        XCTAssertFalse(session.zoomColorHopPending)
        XCTAssertNil(driver.secondsSinceLastCommand)
    }

    func testReceiptFromAnotherNativeOwnerNeverFallsThroughTheActualPort() {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9032, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        session.phase = .live
        let other = DJICommandAdmission(owner: DJICommandOwner(), isCurrent: { true })
        var stages: [ControlWireEvent] = []
        session.setRecording(true, admission: other, onStage: { stages.append($0) })
        XCTAssertEqual(stages, [.notSent])
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(driver.secondsSinceLastCommand)
        XCTAssertTrue(session.commandOwner === driver.commandOwner)
    }

    func testConfirmationCannotBorrowTheCurrentNativeOwnerAfterRepair() {
        let session = CameraSession()
        let first = DjiAppleDatalink(port: 9033, tcpPoke: false, pairingToken: "")
        let successor = DjiAppleDatalink(port: 9034, tcpPoke: false, pairingToken: "")
        defer {
            first.close()
            session.disconnect()
        }
        session.datalink = first
        session.phase = .live
        session.status.shootingMode = 1
        session.status.recordingReported = true
        let target = session.control.target
        let admission = DJICommandAdmission(owner: first.commandOwner, isCurrent: { true })
        session.datalink = successor
        let refused = session.control.record(start: true, aimedAt: target, admission: admission)
        XCTAssertEqual(refused.stage, .rejected(.authorityExpired))
        XCTAssertFalse(session.controlBusy)
        XCTAssertNil(first.secondsSinceLastCommand)
        XCTAssertNil(successor.secondsSinceLastCommand)
    }

    func testOriginalZeroArgumentAndFunctionReferenceAPIsRemainAvailable() {
        let session = CameraSession()
        defer { session.disconnect() }
        let photo: () -> Void = session.takePhoto
        let color: (ColorMode) -> Void = session.setColorMode
        let focus: (CGPoint) -> Void = session.markFocus
        let record: (Bool, (@MainActor (ControlWireEvent) -> Void)?) -> Void = session.setRecording
        let model = AppModel(session: session)
        let watchRecord: () -> WatchCommandResult = model.watchToggleRecord
        let watchPhoto: () -> WatchCommandResult = model.watchCapture
        _ = (photo, color, focus, record)
        XCTAssertFalse(watchRecord().accepted)
        XCTAssertFalse(watchPhoto().accepted)
        XCTAssertFalse(session.controlBusy)
    }

    func testShownWatchSourceRefusesNativeReentryBeforeAnyNewPublication() throws {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9035, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.datalink = driver
        let model = AppModel(session: session)
        model.publishWatchState()
        let shown = try XCTUnwrap(model.watchCommandSource)
        XCTAssertTrue(shown.admits(driver.commandOwner))
        driver.commandOwner.replaceSource()
        XCTAssertFalse(shown.admits(driver.commandOwner))
        XCTAssertEqual(
            model.watchCommandSource?.source, shown.source,
            "A late watch action retains what was shown rather than acquiring the native successor")
        model.publishWatchState()
        let replacement = try XCTUnwrap(model.watchCommandSource)
        XCTAssertNotEqual(replacement.source, shown.source)
        XCTAssertTrue(replacement.admits(driver.commandOwner))
        XCTAssertFalse(shown.isCurrent)
    }

    func testShownWatchSourceCannotBorrowARecreatedCameraOwner() throws {
        let session = CameraSession()
        let driver = DjiAppleDatalink(port: 9036, tcpPoke: false, pairingToken: "")
        let successor = DjiAppleDatalink(port: 9037, tcpPoke: false, pairingToken: "")
        defer {
            driver.close()
            session.disconnect()
        }
        session.datalink = driver
        let model = AppModel(session: session)
        model.publishWatchState()
        let shown = try XCTUnwrap(model.watchCommandSource)
        session.datalink = successor
        XCTAssertFalse(shown.admits(session.commandOwner))
        model.publishWatchState()
        let current = try XCTUnwrap(model.watchCommandSource)
        XCTAssertTrue(current.admits(successor.commandOwner))
        XCTAssertFalse(shown.admits(successor.commandOwner))
        model.noteLeftLive()
        XCTAssertNil(model.watchCommandSource)
        XCTAssertNil(model.watchTarget)
        XCTAssertNil(successor.secondsSinceLastCommand)
    }
}

/// SIMULATED loopback transport only; this peer has no physical endpoint.
private final class WatchAckingCamera: @unchecked Sendable {
    private let queue = DispatchQueue(label: "test.SIMULATED-watch-camera")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var peer: NWConnection?
    private var frames: [Duml.Frame] = []
    private var trace: [String] = []
    var wireTrace: [String] { queue.sync { trace } }
    var controlFrames: [Duml.Frame] { queue.sync { frames } }
    // Count every other camera frame, including unexpected writes and retransmissions.
    var nonPollingControlFrames: [Duml.Frame] { controlFrames.filter { !Self.isPollingRead($0) } }

    static func isPollingRead(_ frame: Duml.Frame) -> Bool {
        frame.sender == 0x02 && frame.receiver == 0x01 && frame.flags == 0x40
            && frame.cmdSet == 0x02 && frame.cmdId == 0x8E && frame.payload == [0, 1, 0x38, 0]
    }
    private let reply: UInt8

    init(reply: UInt8 = 0x00) throws {
        self.reply = reply
        listener = try NWListener(using: .udp)
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

    private func notePacket(_ bytes: [UInt8], direction: String) {
        let raw = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let sequence = DumlTransport.transportSeq(bytes).map(String.init) ?? "nil"
        trace.append("[WATCH-WIRE] direction=\(direction) transportSeq=\(sequence) raw=\(raw)")
        for frame in DumlTransport.scanFrames(bytes) {
            trace.append(
                "[WATCH-WIRE] direction=\(direction) transportSeq=\(sequence) dumlSeq=\(frame.seq) sender=\(frame.sender) receiver=\(frame.receiver) set=\(frame.cmdSet) cmd=\(frame.cmdId) flags=\(frame.flags) payload=\(frame.payload)"
            )
        }
    }

    private func consume(_ bytes: [UInt8], from connection: NWConnection) {
        notePacket(bytes, direction: "app-to-peer")
        if DumlTransport.isHandshake(bytes) {
            peer = connection
            let ack =
                DumlTransport.transportHeader(
                    pktType: 0, payloadLen: 7, sessionId: 1, seq: 0) + [1, 0, 0, 0, 0, 0, 0]
            notePacket(ack, direction: "peer-to-app")
            connection.send(content: Data(ack), completion: .idempotent)
            let window = DumlTransport.ackPayload(peerCursor: 0x6000, baseSeq: 0x6000)
            let packet =
                DumlTransport.transportHeader(
                    pktType: 1, payloadLen: window.count, sessionId: 1, seq: 8) + window
            notePacket(packet, direction: "peer-to-app")
            connection.send(content: Data(packet), completion: .idempotent)
            return
        }
        guard peer === connection else { return }
        for frame in DumlTransport.scanFrames(bytes)
        where frame.cmdSet == 0x02 {
            frames.append(frame)
            // Preserve the original reply behavior; broader observation never grants a reply.
            guard Duml.isLiveCameraControl(set: frame.cmdSet, cmd: frame.cmdId) else { continue }
            let answer = Duml.encode(
                Duml.Frame(
                    sender: frame.receiver, receiver: frame.sender, seq: frame.seq, flags: 0x80,
                    cmdSet: frame.cmdSet, cmdId: frame.cmdId, payload: [reply]))
            let packet =
                DumlTransport.transportHeader(
                    pktType: 1, payloadLen: answer.count, sessionId: 1, seq: 8) + answer
            notePacket(packet, direction: "peer-to-app")
            connection.send(content: Data(packet), completion: .idempotent)
        }
    }
}
