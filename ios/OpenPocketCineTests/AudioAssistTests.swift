import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class AudioAssistTests: XCTestCase {
    func testOpenZCineTapOnlyMenu() {
        XCTAssertEqual(AudioAssist.longPressPanelWidth, 400)
        XCTAssertEqual(AudioAssist.panelSize, CGSize(width: 28, height: 168))
        XCTAssertEqual(
            AudioAssist.helpCopy,
            "Meters the camera's audio. Available while live view is up.")
        XCTAssertEqual(AudioAssist.displayedSensitivity(nil), "—")
        XCTAssertEqual(AudioAssist.displayedSensitivity("  stereo "), "STEREO")
        XCTAssertFalse(LiveAssistTool.audioMeters.hasConfiguration)
    }

    func testMeterReadsCameraStatusNotFloorDefaults() {
        var status = CameraStatus()
        XCTAssertEqual(status.audioMeters, .silent)
        // live1.pcap louder frame: L=8 R=9 on the 0…14 segment scale.
        let louder: [UInt8] = [
            0x00, 0x00, 0x00, 0x08, 0x00, 0x03, 0x00, 0x08, 0x00, 0x09, 0x00, 0x64, 0x00, 0x64,
        ]
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: CamAudioStatus.subscribeKey, value: louder),
            to: &status)
        XCTAssertEqual(
            status.audioMeters.left.levelDB,
            AudioMeterBallistics.floorDB * (1 - 8.0 / 14.0),
            accuracy: 1e-9)
        XCTAssertEqual(
            status.audioMeters.right.levelDB,
            AudioMeterBallistics.floorDB * (1 - 9.0 / 14.0),
            accuracy: 1e-9)
        XCTAssertNotEqual(status.audioMeters, .silent)
    }
}
