import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

@MainActor
final class CameraDialReconciliationTests: XCTestCase {
    func testShootingModeDoesNotBounceThroughAnOlderStatusPush() {
        let session = CameraSession(borrowing: HevcDecoder())
        // An unopened driver admits the command without opening a socket.
        session.datalink = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
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
        let session = CameraSession(borrowing: HevcDecoder())
        session.datalink = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
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
        XCTAssertEqual(session.status.whiteBalance, .custom(kelvin: 5600, tint: 0))
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
        let session = CameraSession(borrowing: HevcDecoder())
        session.datalink = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
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
        let session = CameraSession(borrowing: HevcDecoder())
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
