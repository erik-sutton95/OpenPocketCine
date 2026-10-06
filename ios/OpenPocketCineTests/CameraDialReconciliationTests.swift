import MonitorPresentation
import OpenCineCore
import OpenPocketViewCore
import XCTest
import OpenCineDJIApple

@testable import OpenPocketCine

@MainActor
final class CameraDialReconciliationTests: XCTestCase {
    func testCommonFocusReadsReportsWhileLegacyDisplayIsPinned() {
        let session = commonFixture()
        defer { session.disconnect() }
        let receipt = session.control.request(.set(.focusMode(.continuous)))
        XCTAssertEqual(receipt.stage, .sent)
        XCTAssertEqual(session.status.focusMode, .continuous)
        XCTAssertEqual(session.control.current.value(of: .focusMode).value, .focusMode(.single))
        session.applyIncomingStatus(subscribe("cam_lens_state", [0xB1]))
        XCTAssertEqual(session.status.focusMode, .continuous)
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .sent)
        session.applyIncomingStatus(subscribe("cam_lens_state", [0xB2]))
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .confirmed)
        XCTAssertEqual(session.control.current.value(of: .focusMode).value, .focusMode(.continuous))
    }

    func testCommonDurationRequiresReportedManualAndDoesNotConfirmItsPin() {
        let session = commonFixture()
        defer { session.disconnect() }
        let receipt = session.control.request(.set(.shutter(.duration(Rational(1, 100)))))
        XCTAssertEqual(receipt.stage, .sent)
        XCTAssertEqual(session.control.current.value(of: .shutter).value,
                       .shutter(.duration(Rational(1, 50))))
        var value = [UInt8](repeating: 0, count: 23)
        value[2] = 100
        value[3] = 0x80
        value[7] = ExpoMode.manual.rawValue
        session.applyIncomingStatus(subscribe("cam_expo_param", value))
        XCTAssertEqual(session.control.receipt(of: receipt.operation)?.stage, .confirmed)
        value[7] = ExpoMode.auto.rawValue
        session.applyIncomingStatus(subscribe("cam_expo_param", value))
        XCTAssertEqual(session.control.request(.set(.shutter(.duration(Rational(1, 50))))).stage,
                       .rejected(.unavailable(.mode)))
        XCTAssertEqual(session.status.expoMode, .auto)
    }

    func testQueuedCommonZoomReplacesOnlyTheUnsentColorHopTarget() {
        let session = commonFixture(color: .dLog2)
        defer { session.disconnect() }
        let controls = session.control
        let first = controls.request(.set(.zoom(2)))
        XCTAssertEqual(first.stage, .admitted)
        let latest = session.control.request(.set(.zoom(3)))
        XCTAssertEqual(latest.stage, .admitted)
        XCTAssertEqual(session.control.receipt(of: first.operation)?.stage, .failed(.notSent))
        XCTAssertEqual(session.control.current.value(of: .zoom).value, .zoom(1))
        session.disconnect()
        XCTAssertEqual(controls.receipt(of: latest.operation)?.stage, .failed(.notSent))
    }

    private func commonFixture(color: ColorMode = .normal) -> OpenPocketCine.CameraSession {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        var actual = CameraStatus()
        actual.shootingMode = Int(ShootingMode.video.rawValue)
        actual.recordingReported = true
        actual.expoMode = .manual
        actual.shutterDenom = 50
        actual.availableShutterDenoms = [50, 100]
        actual.focusMode = .single
        actual.zoomLens = CamFov.lensPosition(for: 1)
        actual.colorMode = color
        let model = CameraModel.resolve(modelId: 0x0020, name: "OsmoPocket3-Test")
        session.updateMultiview(camera: DjiAppleSighting(id: UUID(), name: model.name, model: model, modelId: 0x0020),
                                driver: DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: ""),
                                status: actual)
        return session
    }

    func testAutoShutterCaptionTracksTelemetryWhileEVIsSettling() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.status.expoMode = .auto
        session.setEv(EvComp(thirds: 1))
        for (shutter, iso) in [(25, 800), (200, 100)] {
            var value = [UInt8](repeating: 0, count: 46)
            value[2] = 0x40
            value[3] = 0x9F  // Remembered 1/8000 stays fixed.
            value[6] = 0x10  // Older EV must not pin the live shutter or ISO.
            value[7] = 0x01
            value[16] = UInt8(iso & 0xFF)
            value[17] = UInt8(iso >> 8)
            value[20] = UInt8(shutter)
            value[21] = 0x80
            session.applyIncomingStatus(subscribe("cam_expo_param", value))
            XCTAssertEqual(
                MonitorExposureReadout.autoEvCaption(shutterDenom: session.status.shutterDenom),
                "EV 1/\(shutter)s")
            XCTAssertEqual(session.status.iso, iso)
            XCTAssertEqual(session.status.evComp, EvComp(thirds: 1))
        }
    }

    func testShootingModeDoesNotBounceThroughAnOlderStatusPush() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        // An unopened driver admits the command without opening a socket.
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.status.shootingMode = Int(ShootingMode.video.rawValue)
        session.setShootingMode(.slowMo)
        XCTAssertEqual(session.currentShootingMode, .slowMo)
        session.applyIncomingStatus(modeFrame(.video))
        XCTAssertEqual(
            session.currentShootingMode, .slowMo, "Old telemetry must not reseat the dial")
        session.applyIncomingStatus(modeFrame(.slowMo))
        XCTAssertEqual(session.currentShootingMode, .slowMo)
        session.applyIncomingStatus(modeFrame(.video))
        XCTAssertEqual(
            session.currentShootingMode, .video, "A later external change must still apply")
    }

    func testUnrelatedPushCannotConfirmFocusOrWhiteBalance() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.status.focusMode = .single
        session.status.whiteBalance = .auto
        session.setFocusMode(.continuous)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        session.applyIncomingStatus(modeFrame(.video))
        session.applyIncomingStatus(subscribe("cam_lens_state", [0xB1]))
        session.applyIncomingStatus(
            subscribe("cam_image_effect", [0, 0, 0, 0] + WhiteBalance.auto.setPayload))
        XCTAssertEqual(session.status.focusMode, .continuous)
        // The WB request stays pending; reported status keeps what the camera said.
        XCTAssertEqual(session.pendingWhiteBalance, .custom(kelvin: 5600, tint: 0))
        XCTAssertEqual(session.status.whiteBalance, .auto)
        session.applyIncomingStatus(subscribe("cam_lens_state", [0xB2]))
        session.applyIncomingStatus(
            subscribe(
                "cam_image_effect",
                [0, 0, 0, 0] + WhiteBalance.custom(kelvin: 5600, tint: 0).setPayload))
        session.applyIncomingStatus(subscribe("cam_lens_state", [0xB1]))
        session.applyIncomingStatus(
            subscribe("cam_image_effect", [0, 0, 0, 0] + WhiteBalance.auto.setPayload))
        XCTAssertEqual(session.status.focusMode, .single)
        XCTAssertEqual(session.status.whiteBalance, .auto)
    }

    func testParameterDialsIgnoreUnrelatedFramesUntilTheirOwnConfirmation() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        session.datalink = DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: "")
        defer { session.disconnect() }
        session.status.isoLimit = .max800
        session.status.audioChannel = .stereo
        session.status.focusTrack = .subjectLock
        session.setIsoLimit(.max1600)
        session.setAudioChannel(.mono)
        session.setFocusTrack(.registeredPriority)
        session.applyIncomingStatus(modeFrame(.video))
        session.applyIncomingStatus(parameter(0x0F, [IsoLimit.max800.rawValue]))
        session.applyIncomingStatus(parameter(0x20, [AudioChannel.stereo.rawValue]))
        session.applyIncomingStatus(parameter(0x3B, [1, FocusTrackMode.subjectLock.rawValue]))
        XCTAssertEqual(session.status.isoLimit, .max1600)
        XCTAssertEqual(session.status.audioChannel, .mono)
        XCTAssertEqual(session.status.focusTrack, .registeredPriority)
        session.applyIncomingStatus(parameter(0x0F, [IsoLimit.max1600.rawValue]))
        session.applyIncomingStatus(parameter(0x20, [AudioChannel.mono.rawValue]))
        session.applyIncomingStatus(
            parameter(0x3B, [1, FocusTrackMode.registeredPriority.rawValue]))
        session.applyIncomingStatus(parameter(0x0F, [IsoLimit.max800.rawValue]))
        session.applyIncomingStatus(parameter(0x20, [AudioChannel.stereo.rawValue]))
        session.applyIncomingStatus(parameter(0x3B, [1, FocusTrackMode.subjectLock.rawValue]))
        XCTAssertEqual(session.status.isoLimit, .max800)
        XCTAssertEqual(session.status.audioChannel, .stereo)
        XCTAssertEqual(session.status.focusTrack, .subjectLock)
    }

    func testRejectedChoiceRestoresPriorValueAndReleasesItsPin() {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        defer { session.disconnect() }
        // No datalink: command admission fails synchronously.
        session.status.shootingMode = Int(ShootingMode.video.rawValue)
        session.status.whiteBalance = .auto
        session.setShootingMode(.slowMo)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 0)
        XCTAssertEqual(session.currentShootingMode, .video)
        XCTAssertEqual(session.status.whiteBalance, .auto)
        session.applyIncomingStatus(modeFrame(.photo))
        XCTAssertEqual(session.currentShootingMode, .photo)
    }

    private func parameter(_ pid: UInt8, _ value: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 2, cmdId: 0x8E,
            payload: [0, 0, 1, pid, 0, UInt8(value.count)] + value)
    }

    private func subscribe(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }

    private func modeFrame(_ mode: ShootingMode) -> Duml.Frame {
        var payload = [UInt8](repeating: 0, count: 58)
        payload[57] = mode.rawValue
        return Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0,
            cmdSet: 0x02, cmdId: 0x80, payload: payload)
    }
}
