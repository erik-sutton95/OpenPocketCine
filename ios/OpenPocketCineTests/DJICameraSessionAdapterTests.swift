import Foundation
import Network
import OpenCineCore
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

/// CORE-02 gate checks for the Pocket seam: declared support is routed, reported state stays
/// separate from requested state, an unconfirmed settle is never success, and record
/// start/stop is explicit and idempotent.
@MainActor
final class DJICameraSessionAdapterTests: XCTestCase {
    // MARK: Declared capabilities

    func testEveryDeclaredCapabilityReachesTheWire() throws {
        let probe = linked()
        defer { probe.disconnect() }
        let keys = probe.control.current.capabilities.descriptors.keys
        XCTAssertEqual(Set(keys), [.iso, .whiteBalance, .whiteBalanceTint, .recording])
        for key in keys {
            // A fresh session per key: a record send makes recording busy for the rest.
            let session = linked()
            defer { session.disconnect() }
            session.applyIncomingStatus(Self.recordPush(recording: false))
            session.applyIncomingStatus(Self.expoPush(.iso400))
            session.applyIncomingStatus(Self.whiteBalancePush(.auto(tint: 0)))
            let snapshot = session.control.current
            let intent = try XCTUnwrap(Self.validIntent(for: key, in: snapshot), "\(key)")
            let receipt = session.control.submit(
                CameraCommand(intent, preconditions: CommandPreconditions(snapshot)))
            XCTAssertEqual(
                receipt.stage, .sent,
                "\(key) is declared supported, so a valid request must reach the wire")
        }
    }

    func testAnglePreferenceIsDescribedAsEmulatedInTheCommonSnapshot() throws {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        defer { OperatorPrefs.shutterUsesAngle = usesAngle }
        OperatorPrefs.shutterUsesAngle = true
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        defer { session.disconnect() }
        let model = CameraModel.resolve(modelId: 0x22, name: "SIMULATED-Angle")
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.expoMode = .manual
        status.shutterDenom = 50
        status.fps = 25
        status.availableShutterDenoms = [25, 50, 100]
        session.updateMultiview(
            camera: DjiAppleSighting(
                id: UUID(), name: "SIMULATED-Angle", model: model, modelId: 0x22),
            driver: nil, status: status)
        let angle = session.control.current
        XCTAssertEqual(angle.capabilities[.shutter]?.semantics.implementation, .emulated)
        XCTAssertEqual(angle.value(of: .shutter).value, .shutter(.angle(180)))
        XCTAssertEqual(angle.value(of: .shutter).origin, .protocolDerived)
        OperatorPrefs.shutterUsesAngle = false
        let duration = session.control.current
        XCTAssertEqual(duration.capabilities[.shutter]?.semantics.implementation, .native)
        XCTAssertEqual(duration.value(of: .shutter).value, .shutter(.duration(Rational(1, 50))))
    }

    // MARK: Layout (SHELL-01)

    /// The monitor lays out the integration's projection of the connected body; the app adds
    /// clip delete, clip star and the internet hop, and single view shows the timecode and audio on
    /// every body, as Pocket main did (Nano included; Multi View reads the declaration).
    func testMonitorLayoutIsTheIntegrationProjectionOfTheBody() {
        for (id, name) in [(0x22, "OsmoPocket4P-Test"), (0x19, "OsmoNano-Test")] {
            let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
            defer { session.disconnect() }
            let model = CameraModel.resolve(modelId: id, name: name)
            session.updateMultiview(
                camera: DjiAppleSighting(id: UUID(), name: name, model: model, modelId: id),
                driver: nil, status: CameraStatus())
            let layout = OsmoMonitorPresentation.capabilities(session)
            var expected = session.control.layout()
            (expected.clipDelete, expected.clipStar, expected.requiresInternetHop) = (true, true, true)
            expected.timecode = true
            XCTAssertEqual(layout, expected, name)
            XCTAssertEqual(session.control.layout().timecode, id != 0x19, "\(name) declaration")
            XCTAssertEqual(layout.gimbal, model.hasGimbal, name)
            XCTAssertEqual(layout.headTracking, model.hasGimbal, name)
            XCTAssertEqual(layout.focus, model.supportsFocusMode, name)
            XCTAssertTrue(layout.timecode, name)
            XCTAssertTrue(layout.audio, name)
        }
        let unknown = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        XCTAssertFalse(OsmoMonitorPresentation.capabilities(unknown).focus, "no body, no claim")
        XCTAssertTrue(OsmoMonitorPresentation.capabilities(unknown).timecode)
        XCTAssertTrue(OsmoMonitorPresentation.capabilities(unknown).audio)
    }

    func testUndeclaredSettingStaysUnknownInsteadOfPretending() {
        let session = linked()
        defer { session.disconnect() }
        let receipt = session.control.request(.set(.shutter(.duration(Rational(1, 50)))))
        XCTAssertEqual(receipt.stage, .rejected(.supportUnknown))
    }

    // MARK: Requested versus reported

    func testWhiteBalanceRequestStaysPendingUntilTheCameraReportsIt() async throws {
        let camera = try AckingCamera()
        let (session, driver) = try await openLoopback(camera)
        defer {
            session.disconnect()
            driver.close()
            camera.stop()
        }
        session.applyIncomingStatus(Self.whiteBalancePush(.auto(tint: 0)))
        let receipt = session.control.setWhiteBalanceCustom(kelvin: 5_600, tint: 0)
        XCTAssertEqual(receipt.stage, .sent)
        // Requested: pending. Reported: still the camera's Auto.
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5_600, tint: 0))
        XCTAssertEqual(session.status.whiteBalance, .auto(tint: 0))
        XCTAssertEqual(
            session.control.current.value(of: .whiteBalance).value, .whiteBalance(.auto))

        let accepted = try await stage(of: receipt.operation, in: session) {
            $0 == .awaitingObservation
        }
        XCTAssertEqual(accepted, .awaitingObservation, "An ACK is acceptance, not a value")
        XCTAssertEqual(session.status.whiteBalance, .auto(tint: 0))

        session.applyIncomingStatus(Self.whiteBalancePush(.custom(kelvin: 5_600, tint: 0)))
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .confirmed)
        XCTAssertNil(session.pendingWhiteBalance)
        XCTAssertEqual(
            session.control.current.value(of: .whiteBalance).value,
            .whiteBalance(.kelvin(5_600)))
    }

    func testTintIsItsOwnSettingAndKeepsThePendingWhiteBalance() {
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.whiteBalancePush(.custom(kelvin: 5_600, tint: 0)))
        XCTAssertEqual(
            session.control.current.value(of: .whiteBalanceTint).value, .whiteBalanceTint(0))

        // Only the tint changed: one tint write, carried on the current Kelvin.
        let tint = session.control.setWhiteBalanceCustom(kelvin: 5_600, tint: 12)
        XCTAssertEqual(tint.intent, .set(.whiteBalanceTint(12)))
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5_600, tint: 12))

        // A Kelvin drum step keeps the pending tint (it coalesces behind the tint frame).
        session.control.request(.set(.whiteBalance(.kelvin(4_300))))
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 4_300, tint: 12))
        XCTAssertEqual(
            session.control.request(.set(.whiteBalanceTint(150))).stage, .rejected(.outOfDomain))
    }

    func testISOIsConfirmedOnlyByItsOwnReadback() async throws {
        let camera = try AckingCamera()
        let (session, driver) = try await openLoopback(camera)
        defer {
            session.disconnect()
            driver.close()
            camera.stop()
        }
        session.applyIncomingStatus(Self.expoPush(.iso400))
        let receipt = session.control.setISO(.iso800)
        _ = try await stage(of: receipt.operation, in: session) { $0 == .awaitingObservation }
        // An unrelated push cannot confirm, and the reported ISO stays the camera's.
        session.applyIncomingStatus(Self.whiteBalancePush(.auto(tint: 0)))
        XCTAssertEqual(
            session.control.receipt(of: receipt.operation)?.stage, .awaitingObservation)
        XCTAssertEqual(session.control.current.value(of: .iso).value, .iso(.manual(400)))
        session.applyIncomingStatus(Self.expoPush(.iso800))
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .confirmed)
    }

    func testAcknowledgedWithoutReadbackTimesOutInsteadOfSucceeding() async throws {
        let camera = try AckingCamera()
        let (session, driver) = try await openLoopback(camera)
        defer {
            session.disconnect()
            driver.close()
            camera.stop()
        }
        session.control.readbackTimeout = .milliseconds(100)
        session.applyIncomingStatus(Self.recordPush(recording: false))
        let receipt = session.control.record(start: true)
        let outcome = try await finished(receipt.operation, in: session)
        XCTAssertEqual(outcome.stage, .timedOut)
        XCTAssertEqual(session.control.current.recording.value, .idle)
    }

    func testCameraRefusalIsRejectedNotFailedOrConfirmed() async throws {
        let camera = try AckingCamera(reply: 0xD9)
        let (session, driver) = try await openLoopback(camera)
        defer {
            session.disconnect()
            driver.close()
            camera.stop()
        }
        session.applyIncomingStatus(Self.recordPush(recording: false))
        let receipt = session.control.record(start: true)
        let outcome = try await finished(receipt.operation, in: session)
        XCTAssertEqual(outcome.stage, .rejected(.cameraRefused))
    }

    // MARK: Settle without confirmation

    func testSettleWithoutAckOrMatchingStatusIsNeverSuccess() async throws {
        // An unopened driver admits the SET but no ACK can come back: the real 2 s
        // settle window ends in `.waitLate`, which used to report success.
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.whiteBalancePush(.auto(tint: 0)))
        let receipt = session.control.setWhiteBalanceCustom(kelvin: 4_300, tint: 0)
        XCTAssertEqual(receipt.stage, .sent)
        let outcome = try await finished(receipt.operation, in: session)
        XCTAssertEqual(outcome.stage, .timedOut)
        XCTAssertEqual(session.status.whiteBalance, .auto(tint: 0))
    }

    // MARK: Recording

    func testStartWhileRecordingSendsNothing() {
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.recordPush(recording: true))
        let receipt = session.control.record(start: true)
        XCTAssertEqual(receipt.stage, .confirmed)
        XCTAssertFalse(session.controlBusy, "No record frame was fired")
        session.applyIncomingStatus(Self.recordPush(recording: false))
        XCTAssertEqual(session.control.record(start: false).stage, .confirmed)
        XCTAssertFalse(session.controlBusy)
    }

    func testUnknownRecordingStateRefusesTheToggleShapedWire() {
        let session = linked()
        defer { session.disconnect() }
        XCTAssertNil(session.control.current.recording.value, "Unknown is not idle")
        let receipt = session.control.shutter()
        XCTAssertEqual(receipt?.stage, .rejected(.recordingStateUnknown))
        XCTAssertFalse(session.controlBusy)
    }

    func testShutterResolvesToAnExplicitIntentFromTheReportedState() {
        for recording in [false, true] {
            let session = linked()
            defer { session.disconnect() }
            session.applyIncomingStatus(Self.recordPush(recording: recording))
            let receipt = session.control.shutter()
            XCTAssertEqual(receipt?.intent, recording ? .stopRecording : .startRecording)
            XCTAssertEqual(receipt?.stage, .sent)
        }
    }

    // MARK: Link ownership and unknowns

    func testReplacedLinkEndsInFlightWorkAndRefusesOldPreconditions() {
        let session = linked()
        defer { session.disconnect() }
        let before = session.control.current
        let receipt = session.control.setISO(.iso800)
        XCTAssertEqual(receipt.stage, .sent)
        session.datalink = DjiAppleDatalink(port: 9005, tcpPoke: false, pairingToken: "")
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .outcomeUnknown)
        let stale = session.control.submit(
            CameraCommand(.set(.iso(.manual(400))), preconditions: CommandPreconditions(before)))
        XCTAssertEqual(stale.stage, .rejected(.staleEpoch))
    }

    func testMissingTelemetryStaysUnknown() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        defer { session.disconnect() }
        let snapshot = session.control.current
        XCTAssertEqual(snapshot.connection, .discovered)
        XCTAssertEqual(snapshot.recording, .unknown)
        XCTAssertEqual(snapshot.power.battery, .unknown)
        XCTAssertEqual(snapshot.storage, .unknown)
        XCTAssertTrue(snapshot.settings.isEmpty)
        XCTAssertEqual(session.control.setISO(.iso800).stage, .rejected(.notConnected))
    }

    // MARK: Helpers

    /// A session whose unopened driver admits commands without a socket.
    private func linked() -> OpenPocketCine.CameraSession {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        return session
    }

    private func openLoopback(_ camera: AckingCamera) async throws
        -> (OpenPocketCine.CameraSession, DjiAppleDatalink)
    {
        let driver = DjiAppleDatalink.loopbackForTesting(port: try await camera.start())
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        session.datalink = driver
        driver.onStatusFrame = { [weak session] frame in session?.applyIncomingStatus(frame) }
        try await driver.open()
        return (session, driver)
    }

    private func stage(
        of operation: OperationID, in session: OpenPocketCine.CameraSession,
        until done: (CommandStage) -> Bool
    ) async throws -> CommandStage? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while let stage = session.control.receipt(of: operation)?.stage, !done(stage),
            ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        return session.control.receipt(of: operation)?.stage
    }

    private func finished(_ operation: OperationID, in session: OpenPocketCine.CameraSession)
        async throws -> CommandReceipt
    {
        _ = try await stage(of: operation, in: session) { $0.isTerminal }
        return try XCTUnwrap(session.control.receipt(of: operation))
    }

    private static func validIntent(for key: SettingKey, in snapshot: CameraSnapshot)
        -> CameraCommandIntent?
    {
        let current = snapshot.value(of: key).value
        switch key {
        case .recording:
            return snapshot.recording.value == .recording ? .stopRecording : .startRecording
        case .iso:
            return snapshot.capabilities[key]?.domain?.choices.first { $0 != current }.map {
                .set($0)
            }
        case .whiteBalance:
            return .set(.whiteBalance(.kelvin(4_300)))
        case .whiteBalanceTint:
            return .set(.whiteBalanceTint(12))
        default:
            // A newly declared key needs a test value here, or this test cannot vouch for it.
            return nil
        }
    }

    static func whiteBalancePush(_ wb: WhiteBalance) -> Duml.Frame {
        subscribe("cam_image_effect", [0, 0, 0, 0] + wb.setPayload)
    }

    static func expoPush(_ index: IsoIndex) -> Duml.Frame {
        var value = [UInt8](repeating: 0, count: 46)
        value[5] = index.rawValue
        value[7] = 0x04  // Manual
        let iso = index.isoValue ?? 0
        value[16] = UInt8(iso & 0xFF)
        value[17] = UInt8(iso >> 8)
        return subscribe("cam_expo_param", value)
    }

    static func recordPush(recording: Bool) -> Duml.Frame {
        var payload = [UInt8](repeating: 0, count: 58)
        payload[0] = recording ? 0x81 : 0x01
        payload[57] = ShootingMode.video.rawValue
        return Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x02, cmdId: 0x80,
            payload: payload)
    }

    private static func subscribe(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }
}

/// Loopback Pocket: completes the UDP handshake and answers every camera SET with `reply`
/// (`00` ACK, anything else a NACK). Status is pushed by the test on the main actor.
private final class AckingCamera: @unchecked Sendable {
    private let queue = DispatchQueue(label: "test.acking-camera")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var peer: NWConnection?
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

    private func consume(_ bytes: [UInt8], from connection: NWConnection) {
        if DumlTransport.isHandshake(bytes) {
            peer = connection
            let ack =
                DumlTransport.transportHeader(
                    pktType: 0, payloadLen: 7, sessionId: 1, seq: 0) + [1, 0, 0, 0, 0, 0, 0]
            connection.send(content: Data(ack), completion: .idempotent)
            let window = DumlTransport.ackPayload(peerCursor: 0x6000, baseSeq: 0x6000)
            let packet =
                DumlTransport.transportHeader(
                    pktType: 1, payloadLen: window.count, sessionId: 1, seq: 8) + window
            connection.send(content: Data(packet), completion: .idempotent)
            return
        }
        guard peer === connection else { return }
        for frame in DumlTransport.scanFrames(bytes)
        where frame.cmdSet == 0x02 && Duml.isLiveCameraControl(set: frame.cmdSet, cmd: frame.cmdId)
        {
            let answer = Duml.encode(
                Duml.Frame(
                    sender: frame.receiver, receiver: frame.sender, seq: frame.seq, flags: 0x80,
                    cmdSet: frame.cmdSet, cmdId: frame.cmdId, payload: [reply]))
            let packet =
                DumlTransport.transportHeader(
                    pktType: 1, payloadLen: answer.count, sessionId: 1, seq: 8) + answer
            connection.send(content: Data(packet), completion: .idempotent)
        }
    }
}

/// STATE-01: remote surfaces (Apple Watch, watcher relay, record confirmations) command the
/// session and link they showed, never whichever session the app holds when the press lands.
extension DJICameraSessionAdapterTests {
    func testAimedCommandActsWhileItsTargetHolds() {
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.recordPush(recording: false))
        let receipt = session.control.shutter(aimedAt: session.control.target)
        XCTAssertEqual(receipt?.intent, .startRecording)
        XCTAssertEqual(receipt?.stage, .sent)
    }

    func testAimedCommandRefusesAnotherCameraSession() {
        let shown = linked()
        let swapped = linked()
        defer {
            shown.disconnect()
            swapped.disconnect()
        }
        shown.applyIncomingStatus(Self.recordPush(recording: false))
        swapped.applyIncomingStatus(Self.recordPush(recording: false))
        let target = shown.control.target

        let receipt = swapped.control.shutter(aimedAt: target)
        XCTAssertEqual(receipt?.stage, .rejected(.wrongSession))
        XCTAssertEqual(receipt?.targetChanged, true)
        XCTAssertFalse(swapped.controlBusy, "Nothing reached the other camera")
        XCTAssertFalse(target.isSameSession(as: swapped.control.target))
        let confirmed = swapped.control.record(start: true, aimedAt: target)
        XCTAssertEqual(confirmed.stage, .rejected(.wrongSession))
    }

    func testAimedCommandRefusesAReplacedLinkButKeepsTheSession() {
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.recordPush(recording: false))
        let target = session.control.target
        session.datalink = DjiAppleDatalink(port: 9006, tcpPoke: false, pairingToken: "")
        session.applyIncomingStatus(Self.recordPush(recording: false))

        let receipt = session.control.shutter(aimedAt: target)
        XCTAssertEqual(receipt?.stage, .rejected(.staleEpoch))
        XCTAssertEqual(receipt?.targetChanged, true)
        XCTAssertFalse(session.controlBusy)
        XCTAssertTrue(target.isSameSession(as: session.control.target), "Relay binding survives")
    }

    func testStreamOnlyReconfigurationKeepsControlValid() {
        let session = linked()
        defer { session.disconnect() }
        session.applyIncomingStatus(Self.recordPush(recording: false))
        let target = session.control.target
        let iso = session.control.setISO(.iso800)
        XCTAssertEqual(iso.stage, .sent)
        let generation = session.decoder.sourceFrameGeneration
        session.decoder.reset()
        XCTAssertNotEqual(session.decoder.sourceFrameGeneration, generation, "Stream reconfigured")

        XCTAssertEqual(session.control.target, target, "A picture change is not a control change")
        XCTAssertEqual(session.control.receipt(of: iso.operation)?.stage, .sent)
        XCTAssertEqual(session.control.shutter(aimedAt: target)?.stage, .sent)
    }

    func testWatchPressAfterASessionSwapIsRefusedWithAReason() {
        let model = AppModel(session: linked())
        let shown = model.session
        let swapped = linked()
        defer {
            shown.disconnect()
            swapped.disconnect()
        }
        for session in [shown, swapped] {
            session.phase = .live
            session.applyIncomingStatus(Self.recordPush(recording: false))
        }
        model.publishWatchState()
        model.session = swapped

        let result = model.watchToggleRecord()
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.error, WatchRelayCopy.cameraChanged)
        XCTAssertFalse(swapped.controlBusy, "The swapped-in camera was not commanded")
        XCTAssertFalse(shown.controlBusy)
        // The refusal republished, so the next press is aimed at what the watch now shows.
        XCTAssertEqual(model.watchTarget, swapped.control.target)
        XCTAssertTrue(model.watchToggleRecord().accepted)
    }

    func testWatcherRecordConfirmationIsBoundToItsSessionAndLink() {
        let model = AppModel(session: linked())
        defer { model.session.disconnect() }
        model.session.phase = .live
        model.session.applyIncomingStatus(Self.recordPush(recording: false))
        let approved = model.watcherRecordContext
        model.session.datalink = DjiAppleDatalink(port: 9007, tcpPoke: false, pairingToken: "")
        model.session.applyIncomingStatus(Self.recordPush(recording: false))
        XCTAssertNotEqual(approved, model.watcherRecordContext, "A new link dismisses the prompt")
        let receipt = model.session.control.record(start: true, aimedAt: approved.target)
        XCTAssertEqual(receipt.stage, .rejected(.staleEpoch))
    }
}
