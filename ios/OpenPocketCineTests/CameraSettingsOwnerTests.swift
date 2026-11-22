import OpenCineCameraVocabulary
import OpenCineDJIApple
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual native host with absent transport; unknown facts stay unknown.
@MainActor
final class CameraSettingsOwnerTests: XCTestCase {
    func testVoiceLensUsesReportedOpticalPosition() {
        var report = CameraStatus()
        XCTAssertNil(CameraSession.voiceLens(in: report, dualLens: true))
        report.zoomLens = CamFov.lens1x
        XCTAssertEqual(CameraSession.voiceLens(in: report, dualLens: true), .wide)
        XCTAssertEqual(CameraSession.voiceLens(in: report, dualLens: true)?.otherVoiceLens, .tele)
        report.zoomLens = CamFov.lens3x
        XCTAssertEqual(CameraSession.voiceLens(in: report, dualLens: true), .tele)
        XCTAssertEqual(CameraSession.voiceLens(in: report, dualLens: true)?.otherVoiceLens, .wide)
        XCTAssertNil(CameraSession.voiceLens(in: report, dualLens: false))
    }

    func testVoiceLensRequiresPocket4ProAndKnownIdleCompatibleSettings() {
        let pro = CameraModel(name: "Osmo Pocket 4 Pro")
        let pocket4 = CameraModel(name: "Osmo Pocket 4")
        let pocket3 = CameraModel(name: "Osmo Pocket 3")
        var report = CameraStatus()
        report.shootingMode = Int(ShootingMode.video.rawValue)
        report.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
        report.colorMode = .normal
        report.zoomLens = CamFov.lens1x
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pro, reported: report))
        report.recordingReported = true
        XCTAssertEqual(CameraSession.voiceLensPosition(.tele, model: pro, reported: report), CamFov.lens3x)
        report.zoomLens = CamFov.lens3x
        XCTAssertEqual(CameraSession.voiceLensPosition(.wide, model: pro, reported: report), CamFov.lens1x)
        report.zoomLens = CamFov.lens1x
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pocket3, reported: report))
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pocket4, reported: report))
        report.isRecording = true
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pro, reported: report))
        report.isRecording = false
        report.colorMode = .dLog2
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pro, reported: report))
        report.colorMode = .normal
        report.zoomLens = nil
        XCTAssertNil(CameraSession.voiceLensPosition(.tele, model: pro, reported: report))
    }

    func testActualUnconnectedChannelRollbackUsesOriginalUnknownPreviousValue() async {
        let session = CameraSession()
        XCTAssertNil(session.status.audioChannel)
        session.setAudioChannel(.mono)
        XCTAssertEqual(session.status.audioChannel, .mono)
        await session.refreshAudioState()
        XCTAssertNil(session.status.audioChannel)
        XCTAssertNil(session.status.audioDspBlob)
        XCTAssertNil(session.status.audioDspAt2)
        XCTAssertFalse(session.controlLinkReady)
    }

    func testActualUnconnectedDSPAndGlamourDoNotManufactureCameraState() async {
        let session = CameraSession()
        session.setWindNR(.on)
        await session.refreshAudioState()
        XCTAssertEqual(session.status.windNR, .on)
        XCTAssertNil(session.status.directionalAudio)
        XCTAssertNil(session.status.audioDspBlob)
        XCTAssertNil(session.status.audioDspAt2)
        await session.clearGlamourIfEnabled()
        XCTAssertNil(session.status.glamourBlob)
        XCTAssertNil(session.status.glamourEnabled)
        XCTAssertFalse(session.controlLinkReady)
    }
}
