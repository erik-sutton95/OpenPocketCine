import OpenCineDJIApple
import XCTest

@testable import OpenPocketCine

/// SIMULATED actual native host with absent transport; unknown facts stay unknown.
@MainActor
final class CameraSettingsOwnerTests: XCTestCase {
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
